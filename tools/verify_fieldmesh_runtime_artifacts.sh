#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-all}"

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "Missing required file: $1" >&2
        exit 1
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

verify_variant() {
    local name="$1"
    local machine
    local image
    local build_name
    local package_dir
    local jtag_dir
    local dtb
    local rootfs_tar
    local rootfs_cpio
    local strings_out

    case "$name" in
        z203)
            machine="sdr-z203-zynq7"
            image="sdr-z203-arm-image"
            build_name="sdr-z203-arm"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z203"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z203"
            dtb="$package_dir/devicetree/z203/z203-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        z103)
            machine="sdr-z103-zynq7"
            image="sdr-z103-arm-image"
            build_name="sdr-z103-arm"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z103"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z103"
            dtb="$package_dir/devicetree/z103/z103-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        *)
            echo "usage: $0 [all|z203|z103]" >&2
            exit 2
            ;;
    esac

    rootfs_tar="$repo_root/yocto/builds/$build_name/tmp/deploy/images/$machine/$image-$machine.rootfs.tar.gz"
    rootfs_cpio="$repo_root/yocto/builds/$build_name/tmp/deploy/images/$machine/$image-$machine.rootfs.cpio.gz"

    require_file "$rootfs_tar"
    require_file "$rootfs_cpio"
    require_file "$package_dir/fit-work/build/pluto.frm"
    require_file "$package_dir/fit-work/build/pluto.itb"
    require_file "$dtb"
    require_file "$jtag_dir/SHA256SUMS"
    require_file "$jtag_dir/boot/uImage"
    require_file "$jtag_dir/boot/uramdisk.image.gz"
    require_file "$jtag_dir/boot/devicetree.dtb"

    strings_out="$(mktemp)"
    trap 'rm -f "$strings_out"' RETURN
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-udp-probe | strings > "$strings_out"

    for token in adaptive-listen advertise dt-scan ctrl-scan dma-scan dma-plan iio-scan iio-plan pl-replay; do
        if ! grep -qxF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe role in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in udp-command user_command; do
        if ! grep -qF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe command path in $name rootfs: $token" >&2
            exit 1
        fi
    done

    (cd "$jtag_dir" && sha256sum -c SHA256SUMS >/dev/null)

    if ! cmp -s "$dtb" "$jtag_dir/boot/devicetree.dtb"; then
        echo "FieldMesh package DTB and JTAG RAM-boot DTB differ for $name" >&2
        exit 1
    fi

    printf 'fieldmesh_runtime_artifacts=%s\n' "$name"
    sha256sum \
        "$rootfs_cpio" \
        "$rootfs_tar" \
        "$package_dir/fit-work/build/pluto.frm" \
        "$package_dir/fit-work/build/pluto.itb" \
        "$dtb" \
        "$jtag_dir/boot/uImage" \
        "$jtag_dir/boot/uramdisk.image.gz" \
        "$jtag_dir/boot/devicetree.dtb"
}

require_cmd tar
require_cmd strings
require_cmd sha256sum

case "$variant" in
    all)
        verify_variant z203
        verify_variant z103
        ;;
    z203|z103)
        verify_variant "$variant"
        ;;
    *)
        echo "usage: $0 [all|z203|z103]" >&2
        exit 2
        ;;
esac
