#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/network-profile-writer"
mkdir -p "$out_dir"

good_identity="$out_dir/z103-good-identity.txt"
bad_identity="$out_dir/z203-bad-identity.txt"
good_plan="$out_dir/z103-profile-plan.json"
bad_plan="$out_dir/z103-profile-bad-variant.json"
bad_gnss_plan="$out_dir/z103-profile-bad-gnss-console.json"

cat > "$good_identity" <<'EOF_GOOD'
fieldmesh_identity_begin
hostname=pluto
uname=Linux pluto 6.1.0 armv7l
cmdline=console=ttyPS0,115200 maxcpus=1
model=Analog Devices PlutoSDR Rev.C (Z7010-AD9361)
hostname=pluto
mode=1r1t
ipaddr=192.168.2.1
ipaddr_host=192.168.2.10
netmask=255.255.255.0
fieldmeshctl=present
fw_setenv=present
persistent_backup=writable
serial_devices=/dev/ttyPS0,/dev/ttyPS1
fieldmesh_identity_end
EOF_GOOD

cat > "$bad_identity" <<'EOF_BAD'
fieldmesh_identity_begin
hostname=sdr-z203
uname=Linux sdr-z203 6.1.0 armv7l
cmdline=console=ttyPS0,115200n8 root=/dev/ram
model=SDR-Z203 Z7020 2R2T
hostname=sdr-z203
mode=2r2t
ipaddr=192.168.2.1
ipaddr_host=192.168.2.10
netmask=255.255.255.0
fieldmeshctl=present
fw_setenv=present
persistent_backup=writable
serial_devices=/dev/ttyPS0
fieldmesh_identity_end
EOF_BAD

"$repo_root/tools/apply_fieldmesh_network_profile_ssh.py" \
    --mock-identity-file "$good_identity" \
    --variant z103 \
    --device-eui 020000000103 \
    --node-id node-b \
    --network-id fieldmesh-lab \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id 020000000203 \
    --gnss-nmea-device /dev/ttyPS1 \
    --gnss-nmea-baud 115200 \
    --gnss-pps-lock 1 \
    > "$good_plan"

set +e
"$repo_root/tools/apply_fieldmesh_network_profile_ssh.py" \
    --mock-identity-file "$bad_identity" \
    --variant z103 \
    --device-eui 020000000103 \
    --node-id node-b \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    > "$bad_plan" 2> "$out_dir/bad.stderr"
bad_rc=$?
set -e

set +e
"$repo_root/tools/apply_fieldmesh_network_profile_ssh.py" \
    --mock-identity-file "$good_identity" \
    --variant z103 \
    --device-eui 020000000103 \
    --node-id node-b \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --gnss-nmea-device /dev/ttyPS0 \
    > "$bad_gnss_plan" 2> "$out_dir/bad-gnss.stderr"
bad_gnss_rc=$?
set -e

python3 - "$good_plan" "$bad_plan" "$bad_rc" "$bad_gnss_plan" "$bad_gnss_rc" <<'PY'
import json
import sys

good = json.loads(open(sys.argv[1], encoding="utf-8").read())
bad = json.loads(open(sys.argv[2], encoding="utf-8").read())
bad_rc = int(sys.argv[3])
bad_gnss = json.loads(open(sys.argv[4], encoding="utf-8").read())
bad_gnss_rc = int(sys.argv[5])

if good.get("event") != "fieldmesh_network_profile_plan":
    raise SystemExit("missing profile plan event")
if good.get("safe_to_apply") is not True:
    raise SystemExit("good Z103 identity was not safe to apply")
profile = good.get("profile", {})
if profile.get("usb_device_ip") != "192.168.3.1":
    raise SystemExit("planned USB device IP mismatch")
if profile.get("device_eui") != "020000000103":
    raise SystemExit("planned device EUI mismatch")
if profile.get("gnss_nmea_device") != "/dev/ttyPS1":
    raise SystemExit("planned GNSS device mismatch")
if profile.get("gnss_nmea_baud") != 115200:
    raise SystemExit("planned GNSS baud mismatch")
if profile.get("gnss_pps_lock") != 1:
    raise SystemExit("planned GNSS PPS lock mismatch")
if profile.get("netmask") != "255.255.255.0":
    raise SystemExit("planned netmask mismatch")
fw_lines = "\n".join(good.get("fw_setenv", []))
for token in ("ipaddr 192.168.3.1", "ipaddr_host 192.168.3.10",
              "fieldmesh_device_eui 020000000103",
              "fieldmesh_node_id node-b",
              "fieldmesh_ap_policy hybrid"):
    if token not in fw_lines:
        raise SystemExit(f"missing fw_setenv token: {token}")
identity_lines = "\n".join(good.get("identity_store", []))
for token in ("/mnt/jffs2/fieldmesh/device_eui 020000000103",
              "/etc/fieldmesh/device_eui 020000000103"):
    if token not in identity_lines:
        raise SystemExit(f"missing identity-store token: {token}")
gnss_lines = "\n".join(good.get("gnss_store", []))
for token in ("/mnt/jffs2/fieldmesh/gnss_nmea_device /dev/ttyPS1",
              "/mnt/jffs2/fieldmesh/gnss_nmea_baud 115200",
              "/mnt/jffs2/fieldmesh/gnss_pps_lock 1",
              "/etc/fieldmesh/gnss_nmea_device /dev/ttyPS1"):
    if token not in gnss_lines:
        raise SystemExit(f"missing GNSS-store token: {token}")
if bad_rc == 0:
    raise SystemExit("bad variant identity unexpectedly passed")
if bad.get("safe_to_apply") is not False:
    raise SystemExit("bad variant identity did not mark safe_to_apply=false")
if not any("identity does not match" in err for err in bad.get("errors", [])):
    raise SystemExit("bad variant error did not explain identity mismatch")
if bad_gnss_rc == 0:
    raise SystemExit("console GNSS device unexpectedly passed")
if not any("active console" in err for err in bad_gnss.get("errors", [])):
    raise SystemExit("console GNSS error did not explain active console")
PY

echo "fieldmesh_network_profile_writer_check=pass"
