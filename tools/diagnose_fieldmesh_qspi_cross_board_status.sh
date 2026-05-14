#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/qspi-cross-board-status-$(date +%Y%m%d-%H%M%S)}"

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
    find "$repo_root/yocto/builds" \
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
    find "$repo_root/yocto/builds" \
        -path '*/fieldmesh-udp-probe/*/recipe-sysroot' \
        -type d 2>/dev/null | head -n 1
}

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
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
    printf("0x%08lx=0x%08x\n", addr, *ptr);
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
{"event":"fieldmesh_qspi_cross_board_status_plan","z203_ip":"$z203_ip","z103_ip":"$z103_ip","cross_cc":"$cross_cc","cross_sysroot":"$cross_sysroot","read_only":true,"writes_flash":false,"reboots":false}
EOF_PLAN
cat "$out_dir/plan.json"

ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
)

capture_board() {
    local label="$1"
    local ip="$2"
    local board_dir="$out_dir/$label"
    local remote="${ssh_user}@${ip}"
    local remote_prefix="/tmp/fieldmesh-qspi-status-${label}-$$"
    local reg_script=""
    mkdir -p "$board_dir"

    echo "fieldmesh_qspi_capture_${label}=begin"
    if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "true" > "$board_dir/reachability.txt" 2>&1; then
        cat > "$board_dir/summary.json" <<EOF_UNREACHABLE
{"label":"$label","ip":"$ip","reachable":false}
EOF_UNREACHABLE
        echo "fieldmesh_qspi_capture_${label}=unreachable"
        return 0
    fi

    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/devmem_read32.arm" \
        "$remote:${remote_prefix}.devmem_read32" >/dev/null

    for entry in "${qspi_regs[@]}"; do
        local addr="${entry%%:*}"
        local name="${entry#*:}"
        reg_script="${reg_script}
printf 'reg.%s ' '$name'
${remote_prefix}.devmem_read32 '$addr' 2>&1 || true"
    done

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "remote_prefix='$remote_prefix' sh -s" > "$board_dir/linux_qspi_status.txt" 2>&1 <<REMOTE_SH
set +e
chmod +x \${remote_prefix}.devmem_read32
echo fieldmesh_linux_qspi_status_begin
echo label=$label
echo ip=$ip
echo hostname=\$(hostname 2>/dev/null || true)
echo uname=\$(uname -a 2>/dev/null || true)
echo cmdline=\$(cat /proc/cmdline 2>/dev/null || true)
echo proc_mtd_begin
cat /proc/mtd 2>&1
echo proc_mtd_end
echo proc_iomem_begin
cat /proc/iomem 2>&1
echo proc_iomem_end
echo qspi_sysfs_begin
for p in /sys/bus/spi/devices/spi0.0 /sys/class/mtd/mtd0 /sys/class/mtd/mtd1 /sys/class/mtd/mtd2 /sys/class/mtd/mtd3 /sys/devices/soc0/axi/e000d000.spi; do
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
dmesg 2>/dev/null | grep -Ei 'spi|qspi|mtd|w25|jedec|flash|ear|quad|protect|status' | tail -220 || true
echo dmesg_qspi_end
echo qspi_registers_begin
$reg_script
echo qspi_registers_end
echo fieldmesh_linux_qspi_status_end
rm -f \${remote_prefix}.devmem_read32
REMOTE_SH

    python3 - "$label" "$ip" "$board_dir/linux_qspi_status.txt" "$board_dir/summary.json" <<'PY'
import json
import re
import sys
from pathlib import Path

label, ip, status_path, summary_path = sys.argv[1:5]
text = Path(status_path).read_text(encoding="utf-8", errors="replace")

def grab(pattern, default=None, flags=0):
    m = re.search(pattern, text, flags)
    return m.group(1).strip() if m else default

def grab_reg(name):
    m = re.search(rf"reg\.{re.escape(name)}\s+0x[0-9a-fA-F]+=0x([0-9a-fA-F]+)", text)
    return f"0x{m.group(1).lower()}" if m else None

summary = {
    "label": label,
    "ip": ip,
    "reachable": True,
    "hostname": grab(r"^hostname=(.*)$", flags=re.MULTILINE),
    "flash_name": grab(r"^name\s+([^\n]+)$", flags=re.MULTILINE),
    "flash_size": grab(r"^size\s+([^\n]+)$", flags=re.MULTILINE),
    "read_opcode": grab(r"^\s*opcode\s+0x([0-9a-fA-F]+)\s*$", flags=re.MULTILINE),
    "program_opcode": grab(r"^\s*opcode\s+0x([0-9a-fA-F]+)\s*$", flags=re.MULTILINE),
    "has_spi_nor_debugfs": "missing=/sys/kernel/debug/spi-nor/spi0.0" not in text,
    "dmesg_failed_ear": bool(re.search(r"failed to read ear reg", text, re.IGNORECASE)),
    "dmesg_mentions_quad": bool(re.search(r"quad|qspi", text, re.IGNORECASE)),
    "qspi_module_id": grab_reg("MODULE_ID"),
    "qspi_config": grab_reg("CONFIG"),
    "qspi_enable": grab_reg("ENABLE"),
    "qspi_gpio": grab_reg("GPIO"),
    "qspi_lqspi_cfg": grab_reg("LQSPI_CFG"),
}

params = re.search(r"file=/sys/kernel/debug/spi-nor/spi0\.0/params\n(.*?)(?:\nfile=|\nspi_nor_debugfs_end)", text, re.S)
if params:
    block = params.group(1)
    m = re.search(r"^\s*read\s+0x([0-9a-fA-F]+)", block, re.M)
    if m:
        summary["read_opcode"] = f"0x{m.group(1).lower()}"
    m = re.search(r"^\s*program\s+0x([0-9a-fA-F]+)", block, re.M)
    if m:
        summary["program_opcode"] = f"0x{m.group(1).lower()}"

Path(summary_path).write_text(json.dumps(summary, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(summary, sort_keys=True))
PY
    echo "fieldmesh_qspi_capture_${label}=done"
}

capture_board z203 "$z203_ip"
capture_board z103 "$z103_ip"

python3 - "$out_dir" <<'PY' > "$out_dir/comparison.json"
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
rows = {}
for label in ("z203", "z103"):
    path = out / label / "summary.json"
    if path.exists():
        rows[label] = json.loads(path.read_text(encoding="utf-8"))
    else:
        rows[label] = {"label": label, "reachable": False}

z203 = rows["z203"]
z103 = rows["z103"]
same_flash = z203.get("flash_name") == z103.get("flash_name") and z203.get("flash_size") == z103.get("flash_size")
same_program_opcode = z203.get("program_opcode") == z103.get("program_opcode")
same_module = z203.get("qspi_module_id") == z103.get("qspi_module_id")
result = {
    "event": "fieldmesh_qspi_cross_board_status",
    "read_only": True,
    "writes_flash": False,
    "reboots": False,
    "boards": rows,
    "same_flash": same_flash,
    "same_program_opcode": same_program_opcode,
    "same_qspi_module_id": same_module,
    "z203_has_failed_ear": bool(z203.get("dmesg_failed_ear")),
    "z103_has_failed_ear": bool(z103.get("dmesg_failed_ear")),
}
if not z203.get("reachable") or not z103.get("reachable"):
    result["diagnosis"] = "incomplete_cross_board_capture"
elif same_flash and same_program_opcode and same_module:
    result["diagnosis"] = "z203_failure_not_explained_by_basic_linux_flash_identity"
elif z203.get("dmesg_failed_ear") and not z103.get("dmesg_failed_ear"):
    result["diagnosis"] = "z203_specific_ear_or_status_path_difference"
else:
    result["diagnosis"] = "cross_board_qspi_configuration_difference_present"
print(json.dumps(result, sort_keys=True))
PY

cat "$out_dir/comparison.json"
echo "fieldmesh_qspi_cross_board_status=pass"
