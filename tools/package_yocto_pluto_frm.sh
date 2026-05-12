#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deploy_dir="${DEPLOY_DIR:-$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7}"
vendor_fw="${SDR_Z203_VENDOR_FW:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
bitstream="${BITSTREAM:-$vendor_fw/build/system_top.bit}"
dtb="${DTB:-$deploy_dir/zynq-pluto-sdr.dtb}"
out_dir="${OUT_DIR:-$repo_root/yocto/builds/sdr-z203-arm/fit-work}"

require_file() {
    if [ ! -f "$1" ]; then
        echo "Missing required file: $1" >&2
        exit 1
    fi
}

require_file "$deploy_dir/zImage"
require_file "$dtb"
require_file "$deploy_dir/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz"
require_file "$vendor_fw/scripts/pluto.its"
require_file "$bitstream"

rm -rf "$out_dir"
mkdir -p "$out_dir/build" "$out_dir/scripts"

cp "$vendor_fw/scripts/pluto.its" "$out_dir/scripts/pluto.its"
ln -sf "$deploy_dir/zImage" "$out_dir/build/zImage"
ln -sf "$dtb" "$out_dir/build/zynq-pluto-sdr.dtb"
ln -sf "$deploy_dir/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz" "$out_dir/build/rootfs.cpio.gz"
ln -sf "$bitstream" "$out_dir/build/system_top.bit"

(
    cd "$out_dir"
    mkimage -f scripts/pluto.its build/pluto.itb
    md5sum build/pluto.itb | cut -d ' ' -f 1 > build/pluto.frm.md5
    cat build/pluto.itb build/pluto.frm.md5 > build/pluto.frm
)

ls -lh "$out_dir/build/pluto.itb" "$out_dir/build/pluto.frm" "$out_dir/build/pluto.frm.md5"
