#!/usr/bin/env bash

fieldmesh_resolve_image_paths() {
    local variant="$1"
    local repo_root_arg="${2:-$repo_root}"
    local build_name image_name machine legacy_machine

    case "$variant" in
        z203)
            build_name="sdr-z203-arm"
            image_name="sdr-z203-arm-image"
            machine="fm-z203"
            legacy_machine="sdr-z203-zynq7"
            ;;
        z103)
            build_name="sdr-z103-arm"
            image_name="sdr-z103-arm-image"
            machine="fm-z103"
            legacy_machine="sdr-z103-zynq7"
            ;;
        *)
            echo "Unsupported FieldMesh variant: $variant" >&2
            return 2
            ;;
    esac

    FIELDMESH_BUILD_NAME="$build_name"
    FIELDMESH_IMAGE_NAME="$image_name"
    FIELDMESH_MACHINE="$machine"
    FIELDMESH_LEGACY_MACHINE="$legacy_machine"

    if [[ -n "${DEPLOY_DIR:-}" ]]; then
        FIELDMESH_DEPLOY_DIR="$DEPLOY_DIR"
        FIELDMESH_ROOTFS_TAR="${ROOTFS_TAR:-$FIELDMESH_DEPLOY_DIR/$image_name-$machine.rootfs.tar.gz}"
        FIELDMESH_ROOTFS_CPIO_GZ="${ROOTFS_CPIO_GZ:-$FIELDMESH_DEPLOY_DIR/$image_name-$machine.rootfs.cpio.gz}"
        return 0
    fi

    local deploy_root="$repo_root_arg/yocto/builds/$build_name/tmp/deploy/images"
    local product_dir="$deploy_root/$machine"
    local legacy_dir="$deploy_root/$legacy_machine"

    FIELDMESH_DEPLOY_DIR="$product_dir"
    FIELDMESH_ROOTFS_TAR="$product_dir/$image_name-$machine.rootfs.tar.gz"
    FIELDMESH_ROOTFS_CPIO_GZ="$product_dir/$image_name-$machine.rootfs.cpio.gz"

    if [[ ! -f "$FIELDMESH_ROOTFS_TAR" && -f "$legacy_dir/$image_name-$legacy_machine.rootfs.tar.gz" ]]; then
        FIELDMESH_DEPLOY_DIR="$legacy_dir"
        FIELDMESH_ROOTFS_TAR="$legacy_dir/$image_name-$legacy_machine.rootfs.tar.gz"
        FIELDMESH_ROOTFS_CPIO_GZ="$legacy_dir/$image_name-$legacy_machine.rootfs.cpio.gz"
    fi
}
