#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"
fieldmesh_resolve_image_paths z103 "$repo_root"
rootfs="${1:-$FIELDMESH_ROOTFS_TAR}"

exec "$repo_root/tools/audit_yocto_rootfs.sh" "$rootfs"
