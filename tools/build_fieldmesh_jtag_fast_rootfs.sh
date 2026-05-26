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

# Remove interactive/user-facing services from the transient RAM image. The
# JTAG boot payload only needs USB Ethernet, SSH, IIO, FieldMesh C tools, and
# iperf; keeping Wi-Fi/Bluetooth/NFC/ofono/web/mass-storage services only
# slows the RAM load and boot path used for RF bandwidth measurement.
rm -f "$work_dir/root/etc/init.d/S45msd"
rm -f "$work_dir/root/etc/init.d/bluetooth"
rm -f "$work_dir/root/etc/init.d/lighttpd"
rm -f "$work_dir/root/etc/init.d/neard"
rm -f "$work_dir/root/etc/init.d/ofono"
rm -f "$work_dir/root/etc/rc"?.d/*bluetooth
rm -f "$work_dir/root/etc/rc"?.d/*lighttpd
rm -f "$work_dir/root/etc/rc"?.d/*neard
rm -f "$work_dir/root/etc/rc"?.d/*ofono
rm -f "$work_dir/root/etc/network/if-pre-up.d/wpa-supplicant"
rm -f "$work_dir/root/etc/network/if-post-down.d/wpa-supplicant"
rm -f "$work_dir/root/etc/default/volatiles/99_wpa_supplicant"
rm -f "$work_dir/root/etc/dbus-1/system.d/dbus-wpa_supplicant.conf"
rm -f "$work_dir/root/etc/dbus-1/system.d/ofono.conf"
rm -f "$work_dir/root/etc/dbus-1/system.d/org.neard.conf"
rm -f "$work_dir/root/usr/share/dbus-1/system.d/bluetooth.conf"
rm -f "$work_dir/root/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service"
rm -rf "$work_dir/root/etc/bluetooth"
rm -rf "$work_dir/root/etc/lighttpd" "$work_dir/root/etc/lighttpd.d"
rm -rf "$work_dir/root/etc/ofono"
rm -rf "$work_dir/root/etc/wpa_supplicant" "$work_dir/root/etc/wpa_supplicant.conf"
rm -rf "$work_dir/root/usr/lib/lighttpd"
rm -rf "$work_dir/root/usr/libexec/bluetooth"
rm -rf "$work_dir/root/usr/libexec/gio-launch-desktop"
rm -rf "$work_dir/root/usr/libexec/gio-querymodules"
rm -rf "$work_dir/root/usr/libexec/nfc"
rm -rf "$work_dir/root/usr/lib/gio"
rm -rf "$work_dir/root/usr/share/glib-2.0"
rm -rf "$work_dir/root/usr/share/ofono"
rm -rf "$work_dir/root/www"
rm -f "$work_dir/root/usr/bin/bluemoon"
rm -f "$work_dir/root/usr/bin/bluetoothctl"
rm -f "$work_dir/root/usr/bin/btattach"
rm -f "$work_dir/root/usr/bin/btmon"
rm -f "$work_dir/root/usr/bin/ciptool"
rm -f "$work_dir/root/usr/bin/hciattach"
rm -f "$work_dir/root/usr/bin/hciconfig"
rm -f "$work_dir/root/usr/bin/hcidump"
rm -f "$work_dir/root/usr/bin/hcitool"
rm -f "$work_dir/root/usr/bin/isotest"
rm -f "$work_dir/root/usr/bin/l2ping"
rm -f "$work_dir/root/usr/bin/l2test"
rm -f "$work_dir/root/usr/bin/mpris-proxy"
rm -f "$work_dir/root/usr/bin/nfctool"
rm -f "$work_dir/root/usr/bin/rctest"
rm -f "$work_dir/root/usr/bin/rfcomm"
rm -f "$work_dir/root/usr/bin/sdptool"
rm -f "$work_dir/root/usr/sbin/lighttpd"
rm -f "$work_dir/root/usr/sbin/lighttpd-angel"
rm -f "$work_dir/root/usr/sbin/ofonod"
rm -f "$work_dir/root/usr/sbin/iw"
rm -f "$work_dir/root/usr/sbin/wpa_cli"
rm -f "$work_dir/root/usr/sbin/wpa_passphrase"
rm -f "$work_dir/root/usr/sbin/wpa_supplicant"
rm -f "$work_dir/root/usr/lib/libbluetooth.so"*
rm -f "$work_dir/root/usr/lib/libell.so"*
rm -f "$work_dir/root/usr/lib/libgio-2.0.so"*
rm -f "$work_dir/root/usr/lib/libglib-2.0.so"*
rm -f "$work_dir/root/usr/lib/libgobject-2.0.so"*
rm -f "$work_dir/root/usr/lib/libstdc++.so"*
rm -f "$work_dir/root/usr/lib/libX11.so"*
rm -f "$work_dir/root/usr/lib/libxcb.so"*

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

if command -v readelf >/dev/null 2>&1; then
  for path in "${required_paths[@]}"; do
    if [[ ! -f "$work_dir/root/$path" ]]; then
      continue
    fi
    while read -r lib; do
      if [[ -z "$lib" ]]; then
        continue
      fi
      if ! find "$work_dir/root/lib" "$work_dir/root/usr/lib" -maxdepth 1 \
          \( -name "$lib" -o -name "$lib.*" \) -print -quit | grep -q .; then
        echo "Fast JTAG rootfs stripped dependency needed by /$path: $lib" >&2
        exit 1
      fi
    done < <(readelf -d "$work_dir/root/$path" 2>/dev/null |
      sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p')
  done
fi

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
