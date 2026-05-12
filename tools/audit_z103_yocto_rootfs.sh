#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rootfs="${1:-$repo_root/yocto/builds/sdr-z103-arm/tmp/deploy/images/sdr-z103-zynq7/sdr-z103-arm-image-sdr-z103-zynq7.rootfs.tar.gz}"

exec "$repo_root/tools/audit_yocto_rootfs.sh" "$rootfs"
