#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

variant="${1:-z103}"
out="${2:-$repo_root/.config/fieldmesh/$variant-jtag-fast-rootfs.cpio.gz}"

case "$variant" in
  z103|z203) ;;
  *)
    echo "usage: $0 [z103|z203] [out.cpio.gz]" >&2
    exit 2
    ;;
esac

if ! command -v cpio >/dev/null 2>&1; then
  echo "Missing required command: cpio" >&2
  exit 1
fi

fieldmesh_resolve_image_paths "$variant" "$repo_root"
rootfs_tar="$FIELDMESH_ROOTFS_TAR"
if [[ ! -f "$rootfs_tar" ]]; then
  echo "Missing rootfs tarball: $rootfs_tar" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/root" "$(dirname "$out")"
tar -xzf "$rootfs_tar" -C "$work_dir/root"

# Keep the transient JTAG RAM rootfs focused on the RF/IP endpoint. These files
# are large and not needed for iiod, USB Ethernet, SSH, FieldMesh daemon, or iperf.
rm -f "$work_dir/root/opt/vfat.img"
rm -f "$work_dir/root/etc/udev/hwdb.bin"
rm -rf "$work_dir/root/etc/udev/hwdb.d"
rm -f "$work_dir/root/usr/lib/locale/locale-archive"
rm -rf "$work_dir/root/usr/share/locale"
rm -rf "$work_dir/root/usr/share/mime"
rm -rf "$work_dir/root/usr/share/mobile-broadband-provider-info"

required_paths=(
  bin/busybox
  etc/init.d/S23udc
  etc/init.d/S40network
  etc/init.d/S55fieldmesh-state-daemon
  usr/bin/fieldmesh-state-daemon-demo
  usr/bin/fieldmesh-ctrl-write
  usr/bin/iperf3
  usr/sbin/iiod
  usr/sbin/dropbear
  usr/lib/libiio.so.0
)
for path in "${required_paths[@]}"; do
  if [[ ! -e "$work_dir/root/$path" ]]; then
    echo "Fast JTAG rootfs missing required path after strip: /$path" >&2
    exit 1
  fi
done

tmp_out="$out.tmp.$$"
(
  cd "$work_dir/root"
  find . -depth -print0 | cpio --null -o -H newc --owner=0:0 2>/dev/null
) | gzip -9 > "$tmp_out"
mv "$tmp_out" "$out"

python3 - "$rootfs_tar" "$out" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
out = Path(sys.argv[2])

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

report = {
    "event": "fieldmesh_jtag_fast_rootfs",
    "source_rootfs_tar": str(source),
    "out": str(out),
    "out_size_bytes": out.stat().st_size,
    "out_sha256": sha256(out),
    "keeps_rf_ip_endpoint": True,
    "production_rootfs_modified": False,
}
print(json.dumps(report, sort_keys=True))
PY
