#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
variant="${VARIANT:-${2:-z103}}"
port="${PORT:-55441}"
timeout_ms="${TIMEOUT_MS:-5000}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
frame="${FRAME:-$repo_root/resources/fieldmesh/vectors/frame_000.bin}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-rf-phy-bind-${variant}-$(date +%Y%m%d-%H%M%S)}"
center_frequency_hz="${CENTER_FREQUENCY_HZ:-2400000000}"
sample_rate_hz="${SAMPLE_RATE_HZ:-1000000}"
rf_bandwidth_hz="${RF_BANDWIDTH_HZ:-1000000}"
fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-60}"

case "$variant" in
    z203)
        dst_eui="${DST_EUI:-020000000103}"
        local_mesh_ip="10.77.1.1"
        peer_subnet="10.77.2.0/24"
        ;;
    z103)
        dst_eui="${DST_EUI:-020000000203}"
        local_mesh_ip="10.77.2.20"
        peer_subnet="10.77.1.0/24"
        ;;
    *)
        echo "Unsupported VARIANT: $variant" >&2
        exit 1
        ;;
esac

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! [[ "$dst_eui" =~ ^[0-9A-Fa-f]{12}$ ]]; then
    echo "DST_EUI must be 12 hex characters" >&2
    exit 1
fi
if [[ ! -f "$frame" ]]; then
    echo "Missing FieldMesh frame vector: $frame" >&2
    exit 1
fi

mkdir -p "$out_dir"

ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote="${ssh_user}@${board_ip}"

cleanup() {
    set +e
    python3 - "$board_ip" "$port" "$timeout_ms" >"$out_dir/cleanup_daemon.ndjson" 2>/dev/null <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
timeout_ms = int(sys.argv[3])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(timeout_ms / 1000.0)
for text in ("FIELDMESH_RF_WORKER_STOP v1", "FIELDMESH_TUN_SERVICE_STOP v1"):
    try:
        sock.sendto(text.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(8192)
        sys.stdout.write(payload.decode("utf-8", errors="replace"))
    except OSError:
        pass
sock.close()
PY
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "ip link delete swarm0 2>/dev/null || true" >/dev/null 2>&1 || true
}
trap cleanup EXIT

REQUIRE_RX_LOOPBACK=0 \
    "$repo_root/tools/run_fieldmesh_board_dma_smoke.sh" "$board_ip" "$frame" \
    "$out_dir/sidecar_dma_smoke"

host_demo="$out_dir/fieldmesh_state_daemon_demo-host"
cc="${CC:-cc}"
"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -o "$host_demo"
"$host_demo" query "$board_ip" "$port" "$timeout_ms" \
    "$dst_eui" "$dst_eui" "$dst_eui" >"$out_dir/daemon_rf_evidence.ndjson"

"$repo_root/tools/fieldmesh_rf_packet_engine_transport.py" \
    --frame "$frame" \
    --out-dir "$out_dir/rf_packet_engine_transport" \
    --center-frequency-hz "$center_frequency_hz" \
    --sample-rate-hz "$sample_rate_hz" \
    --rf-bandwidth-hz "$rf_bandwidth_hz" \
    --fixture-attenuation-db "$fixture_attenuation_db" \
    --conducted-or-shielded \
    >"$out_dir/rf_packet_engine_transport.ndjson"

"$repo_root/tools/fieldmesh_rf_packet_engine_binding_assert.py" \
    --handoff "$out_dir/daemon_rf_evidence.ndjson" \
    --dma-smoke "$out_dir/sidecar_dma_smoke/dma_smoke.ndjson" \
    --transport-report "$out_dir/rf_packet_engine_transport/fieldmesh_rf_packet_engine_transport.json" \
    --out "$out_dir/fieldmesh_rf_packet_engine_binding_assert.json" \
    --allow-tx-only-dma \
    --pretty >"$out_dir/fieldmesh_rf_packet_engine_binding_assert.stdout.json"

"$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
    --daemon-query "$out_dir/daemon_rf_evidence.ndjson" \
    --out-dir "$out_dir/rf_tx_guard_plan" \
    --conducted-or-shielded \
    --legal-frequency-profile \
    --rx-first \
    --tx-enable-guard \
    --sidecar-preflight-passed \
    --rf-engine-ready \
    >"$out_dir/rf_tx_guard_plan_stdout.json"

VARIANT="$variant" \
BOARD_IP="$board_ip" \
PORT="$port" \
TIMEOUT_MS="$timeout_ms" \
UPLOAD_IF_MISSING=0 \
APPLY_SOURCE=1 \
ALLOW_RF_SOURCE_SELECT=1 \
OUT_DIR="$out_dir/rf_source_apply" \
    "$repo_root/tools/run_fieldmesh_board_rf_source_apply.sh" \
        >"$out_dir/rf_source_apply_stdout.log"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "{ \
       ip link delete swarm0 2>/dev/null || true; \
       mkdir -p /dev/net; \
       [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; \
       ip tuntap add dev swarm0 mode tun; \
       ip addr add '$local_mesh_ip'/16 dev swarm0; \
       ip link set dev swarm0 mtu 1200 up; \
       ip route replace '$peer_subnet' dev swarm0; \
       ip -json addr show dev swarm0; \
       ip route show '$peer_subnet'; \
     }" >"$out_dir/swarm0_setup.log" 2>&1

python3 - "$board_ip" "$port" "$timeout_ms" "$dst_eui" >"$out_dir/daemon_bind.ndjson" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
timeout_ms = int(sys.argv[3])
dst_eui = sys.argv[4]
requests = (
    "FIELDMESH_TUN_SERVICE_START v1 "
    f"dst={dst_eui} max=3 rf_transport=driver_queue "
    "ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE",
    "FIELDMESH_RF_WORKER_START v1",
    "FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE v1 "
    "sidecar_preflight=1 sidecar_dma=1 rf_packet_engine=1 "
    "rf_tx_guard=1 rf_dac_source_select=1 conducted_or_shielded=1 "
    "legal_frequency_profile=1 rx_first=1 measured_link=0",
    "FIELDMESH_RF_PHY_DRIVER_BIND_APPLY v1 rf_dac_source_select=1",
    "FIELDMESH_RF_WORKER_STOP v1",
    "FIELDMESH_TUN_SERVICE_STOP v1",
)
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(timeout_ms / 1000.0)
for text in requests:
    sock.sendto(text.encode("ascii"), (host, port))
    payload, _ = sock.recvfrom(8192)
    sys.stdout.write(payload.decode("utf-8", errors="replace"))
sock.close()
PY

python3 - "$out_dir" "$board_ip" "$variant" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]

def load(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

binding = json.loads(
    (out_dir / "fieldmesh_rf_packet_engine_binding_assert.json").read_text(encoding="utf-8")
)
if binding.get("event") != "fieldmesh_rf_packet_engine_binding_assert" or binding.get("ok") is not True:
    raise SystemExit(f"RF packet-engine binding evidence failed: {binding}")

guard = json.loads(
    (out_dir / "rf_tx_guard_plan" / "fieldmesh_rf_tx_guard_run.json").read_text(encoding="utf-8")
)
if guard.get("event") != "fieldmesh_rf_tx_guard_run" or guard.get("ok") is not True:
    raise SystemExit(f"RF TX guard evidence failed: {guard}")

source = json.loads(
    (out_dir / "rf_source_apply" / "fieldmesh_board_rf_source_apply_assert.json").read_text(
        encoding="utf-8"
    )
)
if source.get("event") != "fieldmesh_board_rf_source_apply_assert" or source.get("ok") is not True:
    raise SystemExit(f"RF DAC source-select evidence failed: {source}")
for key in ("rf_page_addressable", "readback_ok", "rolled_back"):
    if source.get(key) is not True:
        raise SystemExit(f"RF DAC source-select evidence key {key} must be true: {source}")
for key in ("starts_rf_tx", "opens_iio_buffers", "uses_inter_board_ip_routing",
            "commands_executed"):
    if source.get(key) not in (False, 0, None):
        raise SystemExit(f"RF DAC source-select evidence key {key} must be false: {source}")

rows = load(out_dir / "daemon_bind.ndjson")
validate = [row for row in rows if row.get("event") == "sdk_daemon_rf_phy_driver_bind_validate"]
apply = [row for row in rows if row.get("event") == "sdk_daemon_rf_phy_driver_bind_apply"]
if len(validate) != 1:
    raise SystemExit("missing RF PHY driver bind validate response")
if len(apply) != 1:
    raise SystemExit("missing RF PHY driver bind apply response")
validate = validate[0]
apply = apply[0]

for key in ("tun_service_running", "rf_worker_running", "driver_queue_ready"):
    if validate.get(key) != 1:
        raise SystemExit(f"bind validate key {key} must be 1")
for key in ("sidecar_preflight_passed", "sidecar_dma_passed",
            "rf_packet_engine_passed", "rf_tx_guard_passed",
            "rf_dac_source_select_passed", "conducted_or_shielded",
            "legal_frequency_profile", "rx_first",
            "driver_prerequisites_ready", "binding_ready"):
    if validate.get(key) != 1:
        raise SystemExit(f"bind evidence key {key} must be 1")
for key in ("measured_link", "live_rf_prerequisites_ready",
            "prerequisites_ready", "live_rf_allowed", "rf_phy_tx_rx",
            "rf_phy_tx_rx_verified", "app_verified_real_rf",
            "production_ready", "opens_iio_buffers", "starts_rf_tx",
            "writes_hardware", "commands_executed",
            "uses_inter_board_ip_routing", "uses_json_on_air"):
    if validate.get(key) != 0:
        raise SystemExit(f"bind validate key {key} must be 0")
if validate.get("requires_rf_dac_source_select") != 1:
    raise SystemExit("bind validate must require DAC source-select evidence")
if validate.get("production_blocker") != "real_rf_phy_tx_rx_not_verified":
    raise SystemExit("bind validate must now block on measured RF PHY TX/RX")
if apply.get("ok") is not False or apply.get("error") != "live_rf_phy_not_authorized":
    raise SystemExit(f"bind apply must remain refused: {apply}")
if apply.get("rf_dac_source_select_passed") != 1:
    raise SystemExit("bind apply must preserve DAC source-select evidence")
if apply.get("production_blocker") != "real_rf_phy_tx_rx_not_verified":
    raise SystemExit("bind apply must now block on measured RF PHY TX/RX")
for key in ("live_rf_allowed", "rf_phy_tx_rx", "rf_phy_tx_rx_verified",
            "app_verified_real_rf", "production_ready", "opens_iio_buffers",
            "starts_rf_tx", "writes_hardware", "commands_executed",
            "uses_inter_board_ip_routing", "uses_json_on_air"):
    if apply.get(key) != 0:
        raise SystemExit(f"bind apply key {key} must be 0")

summary = {
    "event": "fieldmesh_board_rf_phy_bind_gate",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "driver": validate.get("driver"),
    "adapter_name": validate.get("adapter_name"),
    "driver_queue_ready": validate.get("driver_queue_ready"),
    "driver_prerequisites_ready": validate.get("driver_prerequisites_ready"),
    "rf_dac_source_select_passed": validate.get("rf_dac_source_select_passed"),
    "binding_ready": validate.get("binding_ready"),
    "live_rf_prerequisites_ready": validate.get("live_rf_prerequisites_ready"),
    "rf_phy_tx_rx": validate.get("rf_phy_tx_rx"),
    "production_ready": validate.get("production_ready"),
    "production_blocker": validate.get("production_blocker"),
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "fieldmesh_board_rf_phy_bind_gate.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Capture directory: $out_dir"
