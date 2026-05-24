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
fw_dma_service_latency_max_cycles="${FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES:-1000000}"

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
remote_fw_dma_status_before="/tmp/fieldmesh_rf_phy_fw_dma_status_before.json"
remote_fw_dma_status_after="/tmp/fieldmesh_rf_phy_fw_dma_status_after.json"

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

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status > '$remote_fw_dma_status_before' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$remote:$remote_fw_dma_status_before" "$out_dir/fw_dma_status_before.json"

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

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status > '$remote_fw_dma_status_after' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$remote:$remote_fw_dma_status_after" "$out_dir/fw_dma_status_after.json"

python3 - "$out_dir" "$board_ip" "$variant" "$fw_dma_service_latency_max_cycles" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
try:
    service_latency_budget_cycles = int(sys.argv[4], 0)
except ValueError as exc:
    raise SystemExit("FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES must be an integer") from exc
if service_latency_budget_cycles < 1:
    raise SystemExit("FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES must be >= 1")

def load(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

def require_fw_dma_status(path: Path, label: str) -> dict:
    row = json.loads(path.read_text(encoding="utf-8"))
    if row.get("event") != "fieldmesh_fw_dma_status" or row.get("ok") is not True:
        raise SystemExit(f"{label} firmware-DMA status failed: {row}")
    if row.get("reads_hardware") is not True or row.get("writes_hardware") is not False:
        raise SystemExit(f"{label} firmware-DMA status must be read-only hardware evidence: {row}")
    if row.get("base") != "0x43c00000":
        raise SystemExit(f"{label} firmware-DMA status used unexpected control base: {row}")
    for key in (
        "tx_parser_packets", "tx_parser_bytes", "tx_parser_drops",
        "ingress_packets", "ingress_bytes", "ingress_desc_publishes",
        "ingress_drops", "egress_packets", "egress_bytes", "egress_drops",
        "mac_ticks", "mac_pump_starts", "mac_pump_dones",
        "service_latency_last_cycles", "service_latency_max_cycles",
        "service_latency_accum_cycles",
        "bram_crc_errors", "bram_bounds_errors", "bram_errors",
    ):
        if key not in row or not isinstance(row.get(key), int):
            raise SystemExit(f"{label} firmware-DMA status missing numeric counter {key}: {row}")
    for key in (
        "fault_free", "drop_counters_clear", "idle", "ready_for_arm",
        "config_allowed", "arm_allowed", "stop_write_needed",
    ):
        if not isinstance(row.get(key), bool):
            raise SystemExit(f"{label} firmware-DMA status missing decoded boolean {key}: {row}")
    return row

def counter_delta(before: dict, after: dict, key: str) -> int:
    before_value = before.get(key)
    after_value = after.get(key)
    if not isinstance(before_value, int) or not isinstance(after_value, int):
        raise SystemExit(f"firmware-DMA counter {key} is not numeric")
    if after_value < before_value:
        raise SystemExit(
            f"firmware-DMA counter {key} regressed: before={before_value} after={after_value}"
        )
    return after_value - before_value

binding = json.loads(
    (out_dir / "fieldmesh_rf_packet_engine_binding_assert.json").read_text(encoding="utf-8")
)
if binding.get("event") != "fieldmesh_rf_packet_engine_binding_assert" or binding.get("ok") is not True:
    raise SystemExit(f"RF packet-engine binding evidence failed: {binding}")
if binding.get("requires_c_modem_service_rate") is not True:
    raise SystemExit(f"RF packet-engine binding is missing C modem service-rate evidence: {binding}")
if binding.get("modem_benchmark_decode_frame_kbps", 0) < 100:
    raise SystemExit(f"RF packet-engine C modem decode service-rate evidence is too low: {binding}")
fw_dma_before = require_fw_dma_status(out_dir / "fw_dma_status_before.json", "before")
fw_dma_after = require_fw_dma_status(out_dir / "fw_dma_status_after.json", "after")
dma_smoke_rows = load(out_dir / "sidecar_dma_smoke" / "dma_smoke.ndjson")
dma_smoke_poll = [row for row in dma_smoke_rows if row.get("event") == "dma_smoke_poll"]
if len(dma_smoke_poll) != 1:
    raise SystemExit("sidecar DMA smoke must expose exactly one dma_smoke_poll event")
dma_smoke_poll = dma_smoke_poll[0]
if dma_smoke_poll.get("tx_done") is not True and dma_smoke_poll.get("tx_done_any") is not True:
    raise SystemExit(f"sidecar DMA smoke did not prove TX-submit completion: {dma_smoke_poll}")
for key in ("tx_polls", "rx_polls"):
    if not isinstance(dma_smoke_poll.get(key), int) or dma_smoke_poll.get(key) < 0:
        raise SystemExit(f"sidecar DMA smoke poll count {key} must be a non-negative integer")
if dma_smoke_poll.get("tx_polls") < 1:
    raise SystemExit(f"sidecar DMA smoke must poll at least once for TX completion: {dma_smoke_poll}")

fw_dma_counter_deltas = {
    key: counter_delta(fw_dma_before, fw_dma_after, key)
    for key in (
        "tx_parser_packets",
        "tx_parser_bytes",
        "tx_parser_drops",
        "ingress_packets",
        "ingress_bytes",
        "ingress_desc_publishes",
        "ingress_drops",
        "egress_packets",
        "egress_bytes",
        "egress_drops",
        "mac_ticks",
        "mac_pump_starts",
        "mac_pump_dones",
        "service_latency_accum_cycles",
        "bram_crc_errors",
        "bram_bounds_errors",
        "bram_errors",
    )
}
for key, minimum in (
    ("tx_parser_packets", 1),
    ("tx_parser_bytes", 1),
    ("ingress_packets", 1),
    ("ingress_bytes", 1),
    ("ingress_desc_publishes", 1),
    ("mac_ticks", 1),
):
    if fw_dma_counter_deltas[key] < minimum:
        raise SystemExit(
            f"firmware-DMA counter {key} did not advance by at least {minimum}: "
            f"delta={fw_dma_counter_deltas[key]}"
        )
for key in (
    "tx_parser_drops",
    "ingress_drops",
    "egress_drops",
    "bram_crc_errors",
    "bram_bounds_errors",
    "bram_errors",
):
    if fw_dma_counter_deltas[key] != 0:
        raise SystemExit(f"firmware-DMA error/drop counter {key} advanced: {fw_dma_counter_deltas[key]}")

service_latency_last = fw_dma_after.get("service_latency_last_cycles")
service_latency_max = fw_dma_after.get("service_latency_max_cycles")
service_latency_accum_delta = fw_dma_counter_deltas.get("service_latency_accum_cycles")
if not isinstance(service_latency_last, int) or service_latency_last < 1:
    raise SystemExit(
        "firmware-DMA service latency last-cycle counter did not capture a hardware service interval"
    )
if not isinstance(service_latency_max, int) or service_latency_max < service_latency_last:
    raise SystemExit(
        "firmware-DMA service latency max-cycle counter must be at least the last-cycle count"
    )
if service_latency_last > service_latency_budget_cycles:
    raise SystemExit(
        "firmware-DMA service latency last-cycle counter exceeded budget: "
        f"last={service_latency_last} budget={service_latency_budget_cycles}"
    )
if service_latency_max > service_latency_budget_cycles:
    raise SystemExit(
        "firmware-DMA service latency max-cycle counter exceeded budget: "
        f"max={service_latency_max} budget={service_latency_budget_cycles}"
    )
if not isinstance(service_latency_accum_delta, int) or service_latency_accum_delta < service_latency_last:
    raise SystemExit(
        "firmware-DMA service latency accumulated-cycle delta must cover the last service interval"
    )

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
    "requires_c_modem_service_rate": binding.get("requires_c_modem_service_rate"),
    "modem_benchmark_decode_frame_kbps": binding.get("modem_benchmark_decode_frame_kbps"),
    "dma_smoke_tx_polls": dma_smoke_poll.get("tx_polls"),
    "dma_smoke_rx_polls": dma_smoke_poll.get("rx_polls"),
    "fw_dma_counter_progression_ok": True,
    "fw_dma_required_counter_deltas": {
        "tx_parser_packets": 1,
        "tx_parser_bytes": 1,
        "ingress_packets": 1,
        "ingress_bytes": 1,
        "ingress_desc_publishes": 1,
        "mac_ticks": 1,
    },
    "fw_dma_status_reads_hardware": True,
    "fw_dma_status_writes_hardware": False,
    "fw_dma_fault_free_before": fw_dma_before.get("fault_free"),
    "fw_dma_fault_free_after": fw_dma_after.get("fault_free"),
    "fw_dma_tx_parser_packets_delta": fw_dma_counter_deltas.get("tx_parser_packets"),
    "fw_dma_tx_parser_bytes_delta": fw_dma_counter_deltas.get("tx_parser_bytes"),
    "fw_dma_ingress_desc_publishes_delta": fw_dma_counter_deltas.get("ingress_desc_publishes"),
    "fw_dma_mac_ticks_delta": fw_dma_counter_deltas.get("mac_ticks"),
    "fw_dma_mac_ticks_before": fw_dma_before.get("mac_ticks"),
    "fw_dma_mac_ticks_after": fw_dma_after.get("mac_ticks"),
    "fw_dma_service_latency_last_cycles_before": fw_dma_before.get("service_latency_last_cycles"),
    "fw_dma_service_latency_last_cycles_after": fw_dma_after.get("service_latency_last_cycles"),
    "fw_dma_service_latency_max_cycles_before": fw_dma_before.get("service_latency_max_cycles"),
    "fw_dma_service_latency_max_cycles_after": fw_dma_after.get("service_latency_max_cycles"),
    "fw_dma_service_latency_accum_cycles_before": fw_dma_before.get("service_latency_accum_cycles"),
    "fw_dma_service_latency_accum_cycles_after": fw_dma_after.get("service_latency_accum_cycles"),
    "fw_dma_service_latency_accum_cycles_delta": fw_dma_counter_deltas.get("service_latency_accum_cycles"),
    "fw_dma_service_latency_budget_cycles": service_latency_budget_cycles,
    "fw_dma_service_latency_within_budget": True,
    "fw_dma_ingress_packets_before": fw_dma_before.get("ingress_packets"),
    "fw_dma_ingress_packets_after": fw_dma_after.get("ingress_packets"),
    "fw_dma_ingress_packets_delta": fw_dma_counter_deltas.get("ingress_packets"),
    "fw_dma_ingress_bytes_delta": fw_dma_counter_deltas.get("ingress_bytes"),
    "fw_dma_egress_packets_before": fw_dma_before.get("egress_packets"),
    "fw_dma_egress_packets_after": fw_dma_after.get("egress_packets"),
    "fw_dma_egress_packets_delta": fw_dma_counter_deltas.get("egress_packets"),
    "fw_dma_egress_bytes_delta": fw_dma_counter_deltas.get("egress_bytes"),
    "fw_dma_drop_error_delta": (
        fw_dma_counter_deltas.get("tx_parser_drops", 0)
        + fw_dma_counter_deltas.get("ingress_drops", 0)
        + fw_dma_counter_deltas.get("egress_drops", 0)
        + fw_dma_counter_deltas.get("bram_crc_errors", 0)
        + fw_dma_counter_deltas.get("bram_bounds_errors", 0)
        + fw_dma_counter_deltas.get("bram_errors", 0)
    ),
    "fw_dma_bram_errors_before": fw_dma_before.get("bram_errors"),
    "fw_dma_bram_errors_after": fw_dma_after.get("bram_errors"),
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
