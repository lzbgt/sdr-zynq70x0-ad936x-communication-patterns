#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"
fieldmesh_resolve_image_paths z203 "$repo_root"
rootfs="${1:-$FIELDMESH_ROOTFS_TAR}"

if [ ! -f "$rootfs" ]; then
    echo "Rootfs tarball not found: $rootfs" >&2
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
tar -tzf "$rootfs" | sed 's#^\./#/#' | sort > "$tmp"

required_paths=(
    /etc/device_config
    /etc/fw_env.config
    /etc/init.d/S20pluto-preboot
    /etc/init.d/S21misc
    /etc/init.d/S23udc
    /etc/init.d/S24usb-getty
    /etc/init.d/S40network
    /etc/init.d/S45msd
    /etc/init.d/S55fieldmesh-state-daemon
    /etc/init.d/S98autostart
    /etc/rcS.d/S20pluto-preboot
    /etc/rcS.d/S21misc
    /etc/rcS.d/S23udc
    /etc/rcS.d/S24usb-getty
    /etc/rcS.d/S40network
    /etc/rcS.d/S45msd
    /etc/rcS.d/S55fieldmesh-state-daemon
    /etc/rcS.d/S98autostart
    /sbin/update.sh
    /sbin/update_frm.sh
    /sbin/update_from_github.sh
    /sbin/udc_handle_suspend.sh
    /usr/sbin/device_reboot
    /usr/sbin/device_passwd
    /usr/sbin/device_persistent_keys
    /usr/sbin/device_format_jffs2
    /usr/sbin/pluto_reboot
    /usr/sbin/iiod
    /usr/bin/iio_info
    /usr/bin/iperf3
    /usr/bin/fieldmesh-camera-stream-demo
    /usr/bin/fieldmesh-device-iio-demo
    /usr/bin/fieldmesh-mac-frame-demo
    /usr/bin/fieldmesh-gnss-nmea-reporter
    /usr/bin/fieldmesh-native-ip-socket-demo
    /usr/bin/fieldmeshctl
    /usr/bin/fieldmesh-state-daemon-demo
    /usr/bin/fieldmesh-swarm-adapter-demo
    /usr/bin/fieldmesh-tun-gateway-demo
    /usr/bin/fieldmesh-tun-packetizer-demo
    /usr/bin/fieldmesh-two-pc-flow-demo
    /usr/bin/fieldmesh-ctrl-write
    /usr/bin/fieldmesh-radio-safe-tune
    /usr/bin/fieldmesh-radio-tx-enable
    /usr/bin/fieldmesh-radio-tx-disable
    /usr/bin/fieldmesh-udp-probe
    /usr/libexec/fieldmesh/fieldmesh-radio-common.sh
    /usr/libexec/fieldmesh/fieldmesh-rf-tx-enable-backend
    /usr/bin/fw_printenv
    /usr/bin/fw_setenv
    /usr/sbin/flash_erase
    /usr/sbin/mkfs.jffs2
    /usr/sbin/udhcpd
    /usr/sbin/lighttpd
    /etc/init.d/lighttpd
    /etc/lighttpd/lighttpd.conf
    /etc/rc5.d/S70lighttpd
    /opt/VERSIONS
    /opt/vfat.img
    /www/index.html
    /dev/iio_ffs/
    /mnt/jffs2/
    /mnt/msd/
)

missing=0
for path in "${required_paths[@]}"; do
    if grep -qxF "$path" "$tmp"; then
        printf 'OK      %s\n' "$path"
    else
        printf 'MISSING %s\n' "$path"
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    exit 1
fi

check_contains() {
    local path="$1"
    local pattern="$2"
    local content

    content="$(mktemp)"
    if tar -xOf "$rootfs" ".${path}" > "$content" &&
        grep -a -qF "$pattern" "$content"; then
        printf 'OK      %s contains %s\n' "$path" "$pattern"
        rm -f "$content"
    else
        printf 'BAD     %s missing %s\n' "$path" "$pattern"
        rm -f "$content"
        missing=1
    fi
}

check_not_contains() {
    local path="$1"
    local pattern="$2"
    local content

    content="$(mktemp)"
    if tar -xOf "$rootfs" ".${path}" > "$content" &&
        grep -a -qF "$pattern" "$content"; then
        printf 'BAD     %s still contains %s\n' "$path" "$pattern"
        rm -f "$content"
        missing=1
    else
        printf 'OK      %s excludes %s\n' "$path" "$pattern"
        rm -f "$content"
    fi
}

check_contains /etc/init.d/S40network '/usr/sbin/udhcpd /etc/udhcpd.conf'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'fieldmesh-state-daemon-demo'
check_contains /etc/init.d/S55fieldmesh-state-daemon '55441'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'REQUESTS=0'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'LOG_MAX_BYTES'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'rotate_log_if_needed'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'fieldmesh-gnss-nmea-reporter'
check_contains /etc/init.d/S55fieldmesh-state-daemon 'gnss_nmea_device'
check_contains /usr/bin/fieldmesh-mac-frame-demo 'sdk_mac_frame'
check_contains /usr/bin/fieldmesh-mac-frame-demo 'BLR'
check_contains /usr/bin/fieldmesh-gnss-nmea-reporter 'fieldmesh_gnss_nmea_report'
check_contains /usr/bin/fieldmesh-gnss-nmea-reporter 'FIELDMESH_RTLS_REPORT'
check_contains /usr/bin/fieldmesh-native-ip-socket-demo 'uses_normal_tcp_udp_sockets'
check_contains /usr/bin/fieldmesh-state-daemon-demo 'mac_magic'
check_contains /usr/bin/fieldmesh-state-daemon-demo 'uses_json_on_air'
check_contains /sbin/update.sh 'copy_without_trailing_bytes "$FILE"'
check_contains /sbin/update_frm.sh 'copy_without_trailing_bytes "$FILE"'
check_not_contains /sbin/update.sh 'head -c -33'
check_not_contains /sbin/update_frm.sh 'head -c -33'
check_not_contains /etc/lighttpd/lighttpd.conf 'server.username'
check_not_contains /etc/lighttpd/lighttpd.conf 'server.groupname'

if [ "$missing" -ne 0 ]; then
    exit 1
fi

echo "Yocto rootfs Pluto-runtime audit passed: $rootfs"
