#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/network-profile-writer"
mkdir -p "$out_dir"

good_identity="$out_dir/z103-good-identity.txt"
bad_identity="$out_dir/z203-bad-identity.txt"
good_plan="$out_dir/z103-profile-plan.json"
bad_plan="$out_dir/z103-profile-bad-variant.json"

cat > "$good_identity" <<'EOF_GOOD'
fieldmesh_identity_begin
hostname=pluto
uname=Linux pluto 6.1.0 armv7l
model=Analog Devices PlutoSDR Rev.C (Z7010-AD9361)
hostname=pluto
mode=1r1t
ipaddr=192.168.2.1
ipaddr_host=192.168.2.10
netmask=255.255.255.0
fieldmeshctl=present
fw_setenv=present
persistent_backup=writable
fieldmesh_identity_end
EOF_GOOD

cat > "$bad_identity" <<'EOF_BAD'
fieldmesh_identity_begin
hostname=sdr-z203
uname=Linux sdr-z203 6.1.0 armv7l
model=SDR-Z203 Z7020 2R2T
hostname=sdr-z203
mode=2r2t
ipaddr=192.168.2.1
ipaddr_host=192.168.2.10
netmask=255.255.255.0
fieldmeshctl=present
fw_setenv=present
persistent_backup=writable
fieldmesh_identity_end
EOF_BAD

"$repo_root/tools/apply_fieldmesh_network_profile_ssh.py" \
    --mock-identity-file "$good_identity" \
    --variant z103 \
    --node-id z103-endpoint \
    --network-id fieldmesh-lab \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id z203-hub \
    > "$good_plan"

set +e
"$repo_root/tools/apply_fieldmesh_network_profile_ssh.py" \
    --mock-identity-file "$bad_identity" \
    --variant z103 \
    --node-id z103-endpoint \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    > "$bad_plan" 2> "$out_dir/bad.stderr"
bad_rc=$?
set -e

python3 - "$good_plan" "$bad_plan" "$bad_rc" <<'PY'
import json
import sys

good = json.loads(open(sys.argv[1], encoding="utf-8").read())
bad = json.loads(open(sys.argv[2], encoding="utf-8").read())
bad_rc = int(sys.argv[3])

if good.get("event") != "fieldmesh_network_profile_plan":
    raise SystemExit("missing profile plan event")
if good.get("safe_to_apply") is not True:
    raise SystemExit("good Z103 identity was not safe to apply")
profile = good.get("profile", {})
if profile.get("usb_device_ip") != "192.168.3.1":
    raise SystemExit("planned USB device IP mismatch")
if profile.get("netmask") != "255.255.255.0":
    raise SystemExit("planned netmask mismatch")
fw_lines = "\n".join(good.get("fw_setenv", []))
for token in ("ipaddr 192.168.3.1", "ipaddr_host 192.168.3.10",
              "fieldmesh_node_id z103-endpoint",
              "fieldmesh_ap_policy hybrid"):
    if token not in fw_lines:
        raise SystemExit(f"missing fw_setenv token: {token}")
if bad_rc == 0:
    raise SystemExit("bad variant identity unexpectedly passed")
if bad.get("safe_to_apply") is not False:
    raise SystemExit("bad variant identity did not mark safe_to_apply=false")
if not any("identity does not match" in err for err in bad.get("errors", [])):
    raise SystemExit("bad variant error did not explain identity mismatch")
PY

echo "fieldmesh_network_profile_writer_check=pass"
