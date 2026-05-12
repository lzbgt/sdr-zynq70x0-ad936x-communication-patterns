#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${Z103_YOCTO_BUILD_DIR:-$repo_root/yocto/builds/sdr-z103-arm}"
vendor_fw="${SDR_Z103_VENDOR_FW:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"

if [ ! -d "$repo_root/yocto/layers/poky" ]; then
    echo "Missing Yocto poky layer: $repo_root/yocto/layers/poky" >&2
    exit 1
fi
if [ ! -d "$repo_root/yocto/layers/meta-openembedded/meta-oe" ]; then
    echo "Missing meta-openembedded/meta-oe layer" >&2
    exit 1
fi
if [ ! -d "$repo_root/meta-sdr-z103" ]; then
    echo "Missing Z103 Yocto layer: $repo_root/meta-sdr-z103" >&2
    exit 1
fi
if [ ! -d "$vendor_fw/linux" ] || [ ! -d "$vendor_fw/u-boot-xlnx" ]; then
    echo "Missing Z103 vendor Linux/U-Boot source under: $vendor_fw" >&2
    exit 1
fi

mkdir -p "$build_dir/conf"

cat > "$build_dir/conf/bblayers.conf" <<EOF
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly.
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  $repo_root/yocto/layers/poky/meta \\
  $repo_root/yocto/layers/poky/meta-poky \\
  $repo_root/yocto/layers/poky/meta-yocto-bsp \\
  $repo_root/yocto/layers/meta-openembedded/meta-oe \\
  $repo_root/meta-sdr-z103 \\
  "
EOF

cat > "$build_dir/conf/local.conf" <<EOF
MACHINE ??= "sdr-z103-zynq7"
DISTRO ?= "poky"
PACKAGE_CLASSES ?= "package_rpm"
EXTRA_IMAGE_FEATURES ?= "debug-tweaks"
USER_CLASSES ?= "buildstats"
PATCHRESOLVE = "noop"

DL_DIR ?= "$repo_root/yocto/downloads"
SSTATE_DIR ?= "$repo_root/yocto/sstate-cache"
TMPDIR = "\${TOPDIR}/tmp"

SDR_Z103_VENDOR_FW = "$vendor_fw"

BB_DISKMON_DIRS ??= " \\
    STOPTASKS,\${TMPDIR},1G,100K \\
    STOPTASKS,\${DL_DIR},1G,100K \\
    STOPTASKS,\${SSTATE_DIR},1G,100K \\
    STOPTASKS,/tmp,100M,100K \\
    HALT,\${TMPDIR},100M,1K \\
    HALT,\${DL_DIR},100M,1K \\
    HALT,\${SSTATE_DIR},100M,1K \\
    HALT,/tmp,10M,1K"
EOF

echo "Prepared Z103 Yocto build directory: $build_dir"
