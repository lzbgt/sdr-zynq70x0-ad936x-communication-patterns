#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
serial_port="${SERIAL_PORT:-COM5}"
run_uboot="${RUN_UBOOT:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-qspi-controller-state-$(date +%Y%m%d-%H%M%S)}"

qspi_regs=(
    "0xe000d000:CONFIG"
    "0xe000d004:INT_STATUS"
    "0xe000d010:INT_MASK"
    "0xe000d014:ENABLE"
    "0xe000d018:DELAY"
    "0xe000d028:TX_THRESH"
    "0xe000d02c:RX_THRESH"
    "0xe000d030:GPIO"
    "0xe000d0a0:LQSPI_CFG"
    "0xe000d0a4:LQSPI_STS"
    "0xe000d0fc:MODULE_ID"
)

find_cross_cc() {
    local candidate
    candidate="${CROSS_CC:-}"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    candidate="$repo_root/yocto/builds/sdr-z203-arm/tmp/work/cortexa9t2hf-neon-poky-linux-gnueabi/fieldmesh-udp-probe/0.1/recipe-sysroot-native/usr/bin/arm-poky-linux-gnueabi/arm-poky-linux-gnueabi-gcc"
    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    find "$repo_root/yocto/builds/sdr-z203-arm/tmp/work" \
        -path '*/recipe-sysroot-native/usr/bin/arm-poky-linux-gnueabi/arm-poky-linux-gnueabi-gcc' \
        -type f -perm -111 2>/dev/null | head -n 1
}

find_cross_sysroot() {
    local cc="$1"
    local sysroot
    sysroot="${CROSS_SYSROOT:-}"
    if [[ -n "$sysroot" && -d "$sysroot" ]]; then
        printf '%s\n' "$sysroot"
        return 0
    fi
    sysroot="$(cd "$(dirname "$cc")/../../../../.." && pwd)/recipe-sysroot"
    if [[ -d "$sysroot" ]]; then
        printf '%s\n' "$sysroot"
        return 0
    fi
    sysroot="$repo_root/yocto/builds/sdr-z203-arm/tmp/work/cortexa9t2hf-neon-poky-linux-gnueabi/fieldmesh-udp-probe/0.1/recipe-sysroot"
    if [[ -d "$sysroot" ]]; then
        printf '%s\n' "$sysroot"
        return 0
    fi
    return 1
}

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi
if [[ "$run_uboot" = "1" ]] && ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; U-Boot capture requires WSL on the Windows host." >&2
    exit 1
fi

mkdir -p "$out_dir"
cross_cc="$(find_cross_cc)"
if [[ -z "$cross_cc" || ! -x "$cross_cc" ]]; then
    echo "Could not find arm-poky-linux-gnueabi-gcc; set CROSS_CC=/path/to/cross-gcc." >&2
    exit 1
fi
cross_sysroot="$(find_cross_sysroot "$cross_cc")"
if [[ -z "$cross_sysroot" || ! -d "$cross_sysroot" ]]; then
    echo "Could not find target sysroot; set CROSS_SYSROOT=/path/to/recipe-sysroot." >&2
    exit 1
fi

cat > "$out_dir/devmem_read32.c" <<'EOF_C'
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <phys-addr>\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    unsigned long addr = strtoul(argv[1], &end, 0);
    if (!end || *end != '\0' || (addr & 0x3ul)) {
        fprintf(stderr, "invalid aligned address: %s\n", argv[1]);
        return 2;
    }
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        perror("sysconf");
        return 1;
    }
    unsigned long page_base = addr & ~((unsigned long)page_size - 1ul);
    unsigned long page_off = addr - page_base;
    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 1;
    }
    void *map = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, fd, (off_t)page_base);
    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }
    volatile uint32_t *ptr = (volatile uint32_t *)((char *)map + page_off);
    uint32_t value = *ptr;
    printf("0x%08lx=0x%08x\n", addr, value);
    munmap(map, (size_t)page_size);
    close(fd);
    return 0;
}
EOF_C

"$cross_cc" --sysroot="$cross_sysroot" -Os -Wall -Wextra \
    -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -mthumb \
    -o "$out_dir/devmem_read32.arm" "$out_dir/devmem_read32.c"
file "$out_dir/devmem_read32.arm" > "$out_dir/devmem_read32.file.txt"

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_qspi_controller_state_plan","board_ip":"$board_ip","serial_port":"$serial_port","run_uboot":$run_uboot,"cross_cc":"$cross_cc","cross_sysroot":"$cross_sysroot","read_only":true,"writes_flash":false}
EOF_PLAN
cat "$out_dir/plan.json"

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
)
remote_prefix="/tmp/fieldmesh-z203-qspi-controller-state-$$"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/devmem_read32.arm" "$remote:${remote_prefix}.devmem_read32" >/dev/null

reg_script=""
for entry in "${qspi_regs[@]}"; do
    addr="${entry%%:*}"
    label="${entry#*:}"
    reg_script="${reg_script}
printf 'reg.%s ' '$label'
${remote_prefix}.devmem_read32 '$addr' 2>&1 || true"
done

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "remote_prefix='$remote_prefix' sh -s" > "$out_dir/linux_qspi_controller_state.txt" 2>&1 <<REMOTE_SH
set +e
chmod +x \${remote_prefix}.devmem_read32
echo fieldmesh_z203_linux_qspi_controller_state_begin
echo hostname=\$(hostname 2>/dev/null || true)
echo uname=\$(uname -a 2>/dev/null || true)
echo cmdline=\$(cat /proc/cmdline 2>/dev/null || true)
echo proc_iomem_begin
cat /proc/iomem 2>&1
echo proc_iomem_end
echo qspi_sysfs_begin
for p in /sys/bus/spi/devices/spi0.0 /sys/class/mtd/mtd3 /sys/devices/soc0/axi/e000d000.spi; do
    echo path=\$p
    ls -la "\$p" 2>&1 || true
    for key in modalias driver_override name size erasesize flags; do
        [ -e "\$p/\$key" ] && printf '%s=' "\$key" && cat "\$p/\$key" 2>/dev/null
    done
done
echo qspi_sysfs_end
echo spi_nor_debugfs_begin
if [ -d /sys/kernel/debug/spi-nor/spi0.0 ]; then
    find /sys/kernel/debug/spi-nor/spi0.0 -maxdepth 1 -type f | sort | while read f; do
        echo file=\$f
        cat "\$f" 2>&1
    done
else
    echo missing=/sys/kernel/debug/spi-nor/spi0.0
fi
echo spi_nor_debugfs_end
echo mtd_debugfs_begin
if [ -d /sys/kernel/debug/mtd/mtd3 ]; then
    find /sys/kernel/debug/mtd/mtd3 -maxdepth 1 -type f | sort | while read f; do
        echo file=\$f
        cat "\$f" 2>&1
    done
fi
echo mtd_debugfs_end
echo clk_debugfs_begin
for c in spi0 spi0_aper spi0_div spi0_mux lqspi lqspi_aper lqspi_div lqspi_mux; do
    d=/sys/kernel/debug/clk/\$c
    [ -d "\$d" ] || continue
    echo clk=\$c
    for f in clk_rate clk_flags clk_enable_count clk_prepare_count clk_parent; do
        [ -e "\$d/\$f" ] && printf '%s=' "\$f" && cat "\$d/\$f" 2>/dev/null
    done
done
echo clk_debugfs_end
echo dmesg_qspi_begin
dmesg 2>/dev/null | grep -Ei 'spi|qspi|mtd|w25|jedec|flash|ear|quad|protect|status' | tail -180 || true
echo dmesg_qspi_end
echo qspi_registers_begin
$reg_script
echo qspi_registers_end
echo fieldmesh_z203_linux_qspi_controller_state_end
rm -f \${remote_prefix}.devmem_read32
REMOTE_SH

if [[ "$run_uboot" = "1" ]]; then
    commands_file="$out_dir/uboot_qspi_controller_commands.txt"
    {
        echo "version"
        echo "sf probe"
        echo "echo __FIELDMESH_UBOOT_QSPI_REGISTERS_BEGIN__"
        for entry in "${qspi_regs[@]}"; do
            addr="${entry%%:*}"
            label="${entry#*:}"
            echo "echo __FIELDMESH_REG_${label}__"
            echo "md.l $addr 1"
        done
        echo "echo __FIELDMESH_UBOOT_SPI_STATUS_BEGIN__"
        echo "sspi 0:0.0 32 9F000000"
        echo "sspi 0:0.0 16 0500"
        echo "sspi 0:0.0 16 3500"
        echo "sspi 0:0.0 16 1500"
        echo "sspi 0:0.0 16 7000"
        echo "echo __FIELDMESH_UBOOT_QSPI_REGISTERS_END__"
        echo "reset"
    } > "$commands_file"
    powershell.exe -NoProfile -ExecutionPolicy Bypass \
        -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
        -Port "$serial_port" \
        -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_controller_state.txt")" \
        -CommandsFile "$(wslpath -w "$commands_file")" \
        -ReadAfterCommandMs 1400 \
        -ReadAfterFinalCommandSeconds 60
    perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
        "$out_dir/serial_uboot_qspi_controller_state.txt"
    LC_ALL=C tr -d '\000' < "$out_dir/serial_uboot_qspi_controller_state.txt" \
        > "$out_dir/serial_uboot_qspi_controller_state.clean.txt"
    perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
        "$out_dir/serial_uboot_qspi_controller_state.clean.txt"
    deadline=$((SECONDS + 150))
    while (( SECONDS < deadline )); do
        if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
fi

python3 - "$out_dir/linux_qspi_controller_state.txt" \
    "${out_dir}/serial_uboot_qspi_controller_state.clean.txt" \
    "$out_dir/summary.json" "$board_ip" "$run_uboot" <<'PY'
import json
import re
import sys
from pathlib import Path

linux_text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
uboot_path = Path(sys.argv[2])
uboot_text = uboot_path.read_text(encoding="utf-8", errors="replace") if uboot_path.exists() else ""
out_path = Path(sys.argv[3])
board_ip = sys.argv[4]
run_uboot = sys.argv[5] == "1"

def linux_reg(label):
    match = re.search(rf"^reg\.{re.escape(label)}\s+0x[0-9a-fA-F]+=0x([0-9a-fA-F]{{8}})$", linux_text, re.M)
    return f"0x{int(match.group(1), 16):08x}" if match else None

def uboot_reg(label):
    pattern = re.compile(
        rf"__FIELDMESH_REG_{re.escape(label)}__.*?\n(?:md\.l[^\n]*\n)?\s*([0-9A-Fa-f]{{8}}):\s*([0-9A-Fa-f]{{8}})",
        re.S,
    )
    match = pattern.search(uboot_text)
    return f"0x{int(match.group(2), 16):08x}" if match else None

labels = [
    "CONFIG", "INT_STATUS", "INT_MASK", "ENABLE", "DELAY", "TX_THRESH",
    "RX_THRESH", "GPIO", "LQSPI_CFG", "LQSPI_STS", "MODULE_ID",
]
linux_regs = {label: linux_reg(label) for label in labels}
uboot_regs = {label: uboot_reg(label) for label in labels} if run_uboot else {}
matched = {
    label: {"linux": linux_regs.get(label), "uboot": uboot_regs.get(label)}
    for label in labels
    if linux_regs.get(label) is not None and uboot_regs.get(label) is not None
}
differences = {
    label: values
    for label, values in matched.items()
    if values["linux"] != values["uboot"]
}
jedec = None
for match in re.finditer(r"^\s*([0-9A-Fa-f]{6,8})\s*$", uboot_text, re.M):
    raw = match.group(1).upper()
    if raw.endswith("EF4019"):
        jedec = "0xEF4019"
        break

summary = {
    "event": "fieldmesh_z203_qspi_controller_state",
    "board_ip": board_ip,
    "hostname": re.search(r"^hostname=(.*)$", linux_text, re.M).group(1).strip()
    if re.search(r"^hostname=(.*)$", linux_text, re.M) else "",
    "linux_registers": linux_regs,
    "uboot_registers": uboot_regs,
    "matched_register_differences": differences,
    "uboot_jedec_id": jedec,
    "has_linux_spi_nor_debugfs": "/sys/kernel/debug/spi-nor/spi0.0" in linux_text,
    "has_linux_qspi_devicetree": "e000d000.spi" in linux_text,
    "run_uboot": run_uboot,
    "read_only": True,
    "writes_flash": False,
}
if linux_regs.get("MODULE_ID") and uboot_regs.get("MODULE_ID") and linux_regs["MODULE_ID"] == uboot_regs["MODULE_ID"]:
    summary["diagnosis"] = "Linux and U-Boot can both read the Zynq QSPI controller register block; continue by comparing controller mode bits and SPI-NOR status/config before programming."
else:
    summary["diagnosis"] = "Captured Linux QSPI controller state; U-Boot register comparison is incomplete or differs at MODULE_ID."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

echo "Capture directory: $out_dir"
