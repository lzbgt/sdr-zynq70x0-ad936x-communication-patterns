#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="${1:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"

if [ ! -d "$vendor_root" ]; then
    echo "Vendor source root not found: $vendor_root" >&2
    exit 1
fi

link_rel() {
    local link_path="$1"
    local target="$2"
    mkdir -p "$(dirname "$link_path")"
    if [ -e "$link_path" ] || [ -L "$link_path" ]; then
        rm -rf "$link_path"
    fi
    ln -s "$target" "$link_path"
}

# p7zip on this WSL host ignores several relative symlinks in the vendor zip as
# "Dangerous link path". These are the source-tree links needed for Linux and
# U-Boot devicetree builds.
link_rel "$vendor_root/u-boot-xlnx/arch/arm/dts/include/dt-bindings" "../../../../include/dt-bindings"
link_rel "$vendor_root/u-boot-xlnx/arch/arm/include/asm/arch" "../../mach-zynq/include/mach"

link_rel "$vendor_root/linux/include/dt-bindings/input/linux-event-codes.h" "../../uapi/linux/input-event-codes.h"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/arm" "../../../arch/arm/boot/dts"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/arm64" "../../../arch/arm64/boot/dts"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/dt-bindings" "../../../include/dt-bindings"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/microblaze" "../../../arch/microblaze/boot/dts"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/mips" "../../../arch/mips/boot/dts"
link_rel "$vendor_root/linux/scripts/dtc/include-prefixes/nios2" "../../../arch/nios2/boot/dts"

chmod -R a+rX "$repo_root/src/extracted/plutosdr-fw-2r2t"

