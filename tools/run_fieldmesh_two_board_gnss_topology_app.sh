#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="${BUILD_DIR:-$repo_root/.config/fieldmesh/imgui-control-build}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-gnss-topology-app-$(date +%Y%m%d-%H%M%S)}"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_port="${Z203_PORT:-55441}"
z103_port="${Z103_PORT:-55441}"
z203_eui="${Z203_EUI:-020000000203}"
z103_eui="${Z103_EUI:-020000000103}"
candidates="${FIELDMESH_DISCOVERY_CANDIDATES:-$z203_ip:$z203_port,$z103_ip:$z103_port}"

mkdir -p "$out_dir"

make -C "$app_dir" BUILD_DIR="$build_dir" all >/dev/null
cc -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -o "$out_dir/fieldmesh-state-daemon-demo"

app="$build_dir/fieldmesh-imgui-control-headless"
if [ ! -x "$app" ]; then
    echo "Missing ImGui app binary: $app" >&2
    exit 1
fi

# Seed peer discovery first, then override any demo timing positions with explicit
# GNSS/BDS reports. This proves the app path without allowing default startup to
# display unverified packet-timing coordinates.
"$out_dir/fieldmesh-state-daemon-demo" query "$z203_ip" "$z203_port" 5000 \
    "$z103_eui" "$z103_eui" "$z103_eui" \
    >"$out_dir/z203_preseed_daemon.ndjson"
"$out_dir/fieldmesh-state-daemon-demo" query "$z103_ip" "$z103_port" 5000 \
    "$z203_eui" "$z203_eui" "$z203_eui" \
    >"$out_dir/z103_preseed_daemon.ndjson"

python3 - "$out_dir/gnss_injection.ndjson" \
    "$z203_ip" "$z203_port" "$z203_eui" \
    "$z103_ip" "$z103_port" "$z103_eui" <<'PY'
import json
import socket
import sys
import time
from pathlib import Path

output = Path(sys.argv[1])
z203_ip, z203_port, z203_eui = sys.argv[2], int(sys.argv[3]), sys.argv[4]
z103_ip, z103_port, z103_eui = sys.argv[5], int(sys.argv[6]), sys.argv[7]

nodes = {
    z203_eui: {"lat_e7": 100000000, "lon_e7": 100000000},
    z103_eui: {"lat_e7": 100000120, "lon_e7": 100000160},
}
daemons = [
    ("z203", z203_ip, z203_port),
    ("z103", z103_ip, z103_port),
]


def request(host: str, port: int, text: str) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.5)
    last_error = None
    try:
        for _ in range(8):
            try:
                sock.sendto((text + "\n").encode("ascii"), (host, port))
                payload, _addr = sock.recvfrom(4096)
                return json.loads(payload.decode("utf-8", errors="strict"))
            except (OSError, json.JSONDecodeError) as exc:
                last_error = exc
                time.sleep(0.1)
    finally:
        sock.close()
    raise SystemExit(f"{host}:{port} did not ACK GNSS RTLS report: {last_error}")


with output.open("w", encoding="utf-8") as out:
    for daemon_label, host, port in daemons:
        for eui, fix in nodes.items():
            line = (
                "FIELDMESH_RTLS_REPORT v1 "
                f"node={eui} gps_lock=1 pps_lock=1 "
                "turnaround_calibrated=0 measured_age_ms=35 "
                f"gps_lat_e7={fix['lat_e7']} gps_lon_e7={fix['lon_e7']} "
                "rssi_dbm=-58 snr_db=24"
            )
            report = request(host, port, line)
            report["daemon_label"] = daemon_label
            out.write(json.dumps(report, sort_keys=True) + "\n")
            if report.get("ok") is not True:
                raise SystemExit(f"{daemon_label}: GNSS report failed: {report}")
            if report.get("position_source") != "gps_pps_fused":
                raise SystemExit(f"{daemon_label}: expected gps_pps_fused: {report}")
PY

FIELDMESH_IM_BUS_DIR="$out_dir/im-bus" "$app" --self-test \
    --discover-candidates "$candidates" \
    --api-select-board "$z203_eui" \
    --api-refresh-topology \
    --snapshot-output "$out_dir/z203_selected.json"

FIELDMESH_IM_BUS_DIR="$out_dir/im-bus" "$app" --self-test \
    --discover-candidates "$candidates" \
    --api-select-board "$z103_eui" \
    --api-refresh-topology \
    --snapshot-output "$out_dir/z103_selected.json"

python3 - "$out_dir/z203_selected.json" "$out_dir/z103_selected.json" \
    "$z203_eui" "$z103_eui" "$out_dir" <<'PY'
import json
import sys
from pathlib import Path

z203 = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
z103 = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
z203_eui, z103_eui = sys.argv[3], sys.argv[4]
out_dir = Path(sys.argv[5])


def check(label: str, snap: dict, selected: str, peer: str) -> float:
    if snap.get("profile_source") != "runtime_discovery":
        raise SystemExit(f"{label}: not runtime discovery")
    if snap.get("selected_board_eui") != selected:
        raise SystemExit(f"{label}: wrong selected board {snap.get('selected_board_eui')!r}")
    if snap.get("active_remote_peer_eui") != peer:
        raise SystemExit(f"{label}: wrong active peer {snap.get('active_remote_peer_eui')!r}")
    if snap.get("topology_metrics_live") is not True:
        raise SystemExit(f"{label}: topology did not refresh from daemon")
    if snap.get("topology_range_evidence_source") != "daemon_gnss_bds_position":
        raise SystemExit(
            f"{label}: GNSS/BDS evidence not surfaced: "
            f"{snap.get('topology_range_evidence_source')!r}"
        )
    if snap.get("topology_range_production_ready") is not False:
        raise SystemExit(f"{label}: GNSS topology range claimed RF production readiness")
    if snap.get("topology_gnss_position_peers", 0) < 1:
        raise SystemExit(f"{label}: missing GNSS topology peer")
    if snap.get("topology_timing_position_peers", 0) != 0:
        raise SystemExit(f"{label}: unverified timing position leaked into GNSS gate")
    value = snap.get("topology_max_peer_range_m")
    if not isinstance(value, (int, float)) or not (21.8 <= value <= 22.2):
        raise SystemExit(f"{label}: expected GNSS-derived range near 22.0 m, got {value!r}")
    return float(value)


z203_range = check("z203", z203, z203_eui, z103_eui)
z103_range = check("z103", z103, z103_eui, z203_eui)
summary = {
    "event": "fieldmesh_two_board_gnss_topology_app",
    "ok": True,
    "range_source": "daemon_gnss_bds_position",
    "z203_range_m": z203_range,
    "z103_range_m": z103_range,
    "capture_dir": str(out_dir),
}
print(json.dumps(summary, separators=(",", ":")))
PY

echo "fieldmesh_two_board_gnss_topology_app=pass"
echo "Capture directory: $out_dir"
