#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_uboot_source_path_$(date +%Y%m%d-%H%M%S)}"
uboot_src="${UBOOT_SRC:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/u-boot-xlnx}"
uboot_build="${UBOOT_BUILD:-$repo_root/yocto/builds/sdr-z203-arm/tmp/work/sdr_z203_zynq7-poky-linux-gnueabi/u-boot-sdr-z203/2026.01+vendor/u-boot-build}"
uboot_config="${UBOOT_CONFIG:-$uboot_build/.config}"

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        echo "Missing required file: $path" >&2
        exit 1
    fi
}

require_file "$uboot_src/drivers/mtd/spi/sf_ops.c"
require_file "$uboot_src/drivers/mtd/spi/spi_flash.c"
require_file "$uboot_src/drivers/mtd/spi/sf_params.c"
require_file "$uboot_src/drivers/mtd/spi/sf_internal.h"
require_file "$uboot_src/drivers/spi/zynq_qspi.c"
require_file "$uboot_config"

mkdir -p "$out_dir"

capture_range() {
    local src="$1"
    local start="$2"
    local end="$3"
    local dst="$4"
    nl -ba "$src" | sed -n "${start},${end}p" | sed 's/[[:space:]]*$//' > "$out_dir/$dst"
}

{
    echo "fieldmesh_z203_qspi_uboot_source_path_begin"
    echo "uboot_src=$uboot_src"
    echo "uboot_build=$uboot_build"
    echo "uboot_config=$uboot_config"
    echo "uboot_config_sha256=$(sha256sum "$uboot_config" | awk '{print $1}')"
    echo "sf_ops_sha256=$(sha256sum "$uboot_src/drivers/mtd/spi/sf_ops.c" | awk '{print $1}')"
    echo "spi_flash_sha256=$(sha256sum "$uboot_src/drivers/mtd/spi/spi_flash.c" | awk '{print $1}')"
    echo "zynq_qspi_sha256=$(sha256sum "$uboot_src/drivers/spi/zynq_qspi.c" | awk '{print $1}')"
    echo "config_flags_begin"
    rg -n 'CONFIG_(DM_SPI_FLASH|SPI_FLASH_BAR|SPI_FLASH_MTD|SPI_FLASH_WINBOND|SPI_FLASH_USE_4K_SECTORS|ZYNQ_QSPI|SF_DEFAULT|SPI_FLASH=|CMD_SF)' "$uboot_config" || true
    echo "config_flags_end"
    echo "source_refs_begin"
    rg -n 'SPI_FLASH_16MB_BOUN|SPI_4BYTE_MODE|spi_flash_bank|bank_write_cmd|CMD_EXTNADDR_WREAR|CMD_BANKADDR_BRWR|W25Q256|CMD_PAGE_PROGRAM|CMD_QUAD_PAGE_PROGRAM|spi_flash_cmd_write_ops|spi_flash_scan' \
        "$uboot_src/drivers/mtd/spi/sf_ops.c" \
        "$uboot_src/drivers/mtd/spi/spi_flash.c" \
        "$uboot_src/drivers/mtd/spi/sf_internal.h" \
        "$uboot_src/drivers/mtd/spi/sf_params.c" \
        "$uboot_src/include/spi.h" || true
    echo "source_refs_end"
    echo "fieldmesh_z203_qspi_uboot_source_path_end"
} > "$out_dir/source_path_inventory.txt"

capture_range "$uboot_src/drivers/mtd/spi/sf_ops.c" 160 230 "sf_ops_bank_register_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/sf_ops.c" 470 525 "sf_ops_write_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/sf_ops.c" 600 645 "sf_ops_read_bank_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/spi_flash.c" 150 250 "spi_flash_bar_setup_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/spi_flash.c" 1240 1450 "spi_flash_scan_address_mode_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/spi_flash.c" 1465 1508 "spi_flash_program_opcode_path.txt"
capture_range "$uboot_src/drivers/mtd/spi/sf_params.c" 126 138 "sf_params_w25q256.txt"
capture_range "$uboot_src/drivers/mtd/spi/sf_internal.h" 44 116 "sf_internal_bar_defs.txt"
capture_range "$uboot_src/drivers/spi/zynq_qspi.c" 1 220 "zynq_qspi_driver_defs.txt"

python3 - "$out_dir/source_path_inventory.txt" "$out_dir/summary.json" <<'PY'
import json
import re
import sys
from pathlib import Path

inventory = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
summary_path = Path(sys.argv[2])

def has(pattern):
    return re.search(pattern, inventory, re.MULTILINE) is not None

summary = {
    "event": "fieldmesh_z203_qspi_uboot_source_path",
    "read_only": True,
    "writes_flash": False,
    "uboot_config_sha256": re.search(r"^uboot_config_sha256=(.*)$", inventory, re.MULTILINE).group(1),
    "sf_ops_sha256": re.search(r"^sf_ops_sha256=(.*)$", inventory, re.MULTILINE).group(1),
    "spi_flash_sha256": re.search(r"^spi_flash_sha256=(.*)$", inventory, re.MULTILINE).group(1),
    "zynq_qspi_sha256": re.search(r"^zynq_qspi_sha256=(.*)$", inventory, re.MULTILINE).group(1),
    "config": {
        "dm_spi_flash": has(r"CONFIG_DM_SPI_FLASH=y"),
        "cmd_sf": has(r"CONFIG_CMD_SF=y"),
        "spi_flash_bar": has(r"CONFIG_SPI_FLASH_BAR=y"),
        "spi_flash_mtd_disabled": has(r"# CONFIG_SPI_FLASH_MTD is not set"),
        "spi_flash_winbond": has(r"CONFIG_SPI_FLASH_WINBOND=y"),
        "spi_flash_4k_sectors": has(r"CONFIG_SPI_FLASH_USE_4K_SECTORS=y"),
        "zynq_qspi": has(r"CONFIG_ZYNQ_QSPI=y"),
    },
    "source_inference": {
        "w25q256_is_32_mib": has(r"W25Q256.*512"),
        "bar_boundary_is_16_mib": has(r"SPI_FLASH_16MB_BOUN"),
        "non_4byte_path_calls_bank_select": has(r"spi_flash_bank"),
        "bar_write_command_can_be_wrear": has(r"CMD_EXTNADDR_WREAR"),
        "default_program_command_is_page_program": has(r"CMD_PAGE_PROGRAM"),
        "qpp_program_possible_if_controller_advertises_qpp": has(r"CMD_QUAD_PAGE_PROGRAM"),
    },
    "diagnosis": (
        "The built Z203 U-Boot source/config uses the SPI flash stack with BAR/EAR bank "
        "support for the 32 MiB Winbond W25Q256. For offsets above 16 MiB, the configured "
        "sf path is expected to select a bank/extended-address register and then issue a "
        "3-byte page-program style transfer unless the SPI slave is explicitly in 4-byte "
        "mode. Therefore the raw 4-byte sspi probe is not equivalent to the failing sf "
        "write path. Full QSPI FIT repair remains blocked until a small bank-register plus "
        "page-program path is instrumented and passes write/readback."
    ),
    "next_probe": (
        "Do not attempt a full FIT write. Add an instrumented U-Boot probe around the "
        "configured sf path: capture EAR/BAR before and after bank select, capture SR1/SR2 "
        "after write-enable, log the selected write opcode, address bytes, and first data "
        "bytes, then verify one rollback-protected scratch write/readback."
    ),
}

summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(summary_path.read_text(encoding="utf-8"), end="")
PY

echo "Capture directory: $out_dir"
