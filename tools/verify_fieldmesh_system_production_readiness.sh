#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/system-production-readiness-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/gnss-blocked.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_live_preflight",
  "ok": true,
  "gnss_live_ready": false,
  "boards": [
    {
      "label": "z203",
      "gnss_pps_ready": false,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": ["gnss_no_satellites_visible"]
    },
    {
      "label": "z103",
      "gnss_pps_ready": false,
      "gnss_receiver_health_ready": false,
      "gnss_receiver_health_blockers": ["gnss_receiver_io_overvoltage"],
      "blockers": ["gnss_receiver_io_overvoltage"]
    }
  ]
}
JSON

cat >"$work_dir/native-ip-preflight.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": false,
  "preflight_only": true,
  "production_ready": false,
  "production_blocker": "board_to_board_preflight_failed,host_pc_preflight_failed"
}
JSON

cat >"$work_dir/timepulse-blocked.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_timepulse_poll",
  "ok": true,
  "writes_hardware_config": false,
  "boards": [
    {
      "label": "z203",
      "timepulse_readiness_blockers": ["gnss_timepulse_unlocked_pulse_length_zero"]
    },
    {
      "label": "z103",
      "timepulse_readiness_blockers": ["gnss_timepulse_unlocked_pulse_length_zero"]
    }
  ]
}
JSON

cat >"$work_dir/rf-blocked.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": false,
  "production_blocker": "measured_rf_phy_tx_rx_not_verified"
}
JSON

cat >"$work_dir/rf-sequence-blocked.json" <<'JSON'
{
  "event": "fieldmesh_over_air_rf_production_sequence",
  "ok": true,
  "production_ready": false,
  "production_blocker": "measured_rf_phy_tx_rx_not_verified"
}
JSON

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-blocked.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-blocked.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-preflight.json" \
  --real-rf-production-gate "$work_dir/rf-blocked.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-blocked.json" \
  --output "$work_dir/blocked-summary.json" \
  >"$work_dir/blocked-summary.stdout"; then
  echo "system readiness accepted blocked production evidence" >&2
  exit 1
fi

python3 - "$work_dir/blocked-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not False:
    raise SystemExit(f"blocked report claimed production ready: {report}")
for blocker in (
    "gnss_live_fix_not_ready",
    "gnss_pps_not_ready",
    "gnss_receiver_health_not_ready",
    "native_ip_iperf_not_production_ready",
    "real_rf_not_production_ready",
):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"missing blocker {blocker}: {report}")
if "z203:gnss_no_satellites_visible" not in report.get("blockers", []):
    raise SystemExit(f"GNSS board blocker not propagated: {report}")
if "z103:gnss_receiver_io_overvoltage" not in report.get("blockers", []):
    raise SystemExit(f"GNSS receiver health blocker not propagated: {report}")
if "z203:gnss_timepulse_unlocked_pulse_length_zero" not in report.get("blockers", []):
    raise SystemExit(f"GNSS TIMEPULSE blocker not propagated: {report}")
PY

cat >"$work_dir/gnss-ready.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_live_preflight",
  "ok": true,
  "gnss_live_ready": true,
  "boards": [
    {
      "label": "z203",
      "gnss_pps_ready": true,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": []
    },
    {
      "label": "z103",
      "gnss_pps_ready": true,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": []
    }
  ]
}
JSON

cat >"$work_dir/native-ip-ready.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": true,
  "preflight_only": false,
  "production_ready": true,
  "requires_iio_rf_burst_batch_evidence": true,
  "requires_iio_direction_fair_service_evidence": true,
  "requires_iio_same_priority_batch_evidence": true,
  "requires_iio_hybrid_lease_priority": true,
  "requires_iio_persistent_burst_helper": true,
  "requires_iio_rf_sub_burst_evidence": true,
  "board_iio_rf_burst_batch_exercised": true,
  "host_iio_rf_burst_batch_exercised": true,
  "board_iio_bridge_rf_burst_batch_high_water": 2,
  "host_iio_bridge_rf_burst_batch_high_water": 2,
  "board_iio_direction_fair_service_within_budget": true,
  "host_iio_direction_fair_service_within_budget": true,
  "board_iio_same_priority_batch_enabled": true,
  "host_iio_same_priority_batch_enabled": true,
  "board_iio_same_priority_batch_preemption_exercised": true,
  "host_iio_same_priority_batch_preemption_exercised": true,
  "board_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "host_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "board_iio_bridge_persistent_burst_helper": true,
  "host_iio_bridge_persistent_burst_helper": true,
  "board_iio_rf_sub_burst_exercised": true,
  "host_iio_rf_sub_burst_exercised": true,
  "board_iio_bridge_max_consecutive_direction_batches_seen": 1,
  "host_iio_bridge_max_consecutive_direction_batches_seen": 1,
  "requires_tcp_final_exchange_evidence": true,
  "board_tcp_final_exchange_ok": true,
  "host_tcp_final_exchange_ok": true,
  "board_tcp_control_drain_elapsed_s": 0,
  "host_tcp_control_drain_elapsed_s": 30,
  "production_blocker": ""
}
JSON

cat >"$work_dir/timepulse-ready.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_timepulse_poll",
  "ok": true,
  "writes_hardware_config": false,
  "boards": [
    {
      "label": "z203",
      "timepulse_readiness_blockers": []
    },
    {
      "label": "z103",
      "timepulse_readiness_blockers": []
    }
  ]
}
JSON

cat >"$work_dir/rf-ready.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": true,
  "production_blocker": null
}
JSON

cat >"$work_dir/tx-backend-readback-ready.json" <<'JSON'
{
  "event": "fieldmesh_rf_tx_backend_readback_evidence",
  "ok": true,
  "native_rf_control": true,
  "native_tune": true,
  "native_iio_attr_control": true,
  "starts_rf_tx_when_executed": true,
  "writes_hardware_when_executed": true,
  "prewrite_policy_ok": true,
  "source_select_readback_ok": true,
  "guard_arm_readback_ok": true,
  "source_control_asserted": true,
  "source_status_fieldmesh": true,
  "guard_control_armed": true,
  "guard_status_fault_free": true,
  "bounded_sleep_proven": true,
  "rollback_proven": true,
  "ctrl_phases": [
    "prewrite_policy",
    "source_select_readback",
    "guard_arm_readback",
    "rollback"
  ],
  "iio_phases": [
    "tune_center_frequency",
    "tune_sample_rate",
    "tune_rf_bandwidth",
    "enable",
    "rollback"
  ],
  "backend_request": "mock-request.json",
  "backend_event_count": 18
}
JSON

python3 - "$work_dir" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])
evidence_dir = work_dir / "evidence"
evidence_dir.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, data: dict) -> Path:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def evidence_file(label: str, data: dict) -> dict:
    path = write_json(evidence_dir / f"{label}.json", data)
    raw = path.read_bytes()
    return {
        "label": label,
        "path": str(path),
        "source_path": str(path),
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


preflight = {
    "event": "fieldmesh_over_air_rf_preflight",
    "ok": True,
    "live_rf_allowed": True,
}
iq_live_run = {
    "event": "fieldmesh_iq_iio_live_run",
    "ok": True,
}
bridge = {
    "event": "fieldmesh_iio_rf_worker_bridge",
    "ok": True,
    "iq_iio_live_run": str(evidence_dir / "iq_live_run.json"),
}
production_gate = {
    "event": "fieldmesh_real_rf_production_gate",
    "ok": True,
    "production_ready": True,
    "production_blocker": "",
}
rf_bind_gate = {
    "event": "fieldmesh_board_rf_phy_bind_gate",
    "ok": True,
    "fw_dma_counter_progression_ok": True,
    "fw_dma_drop_error_delta": 0,
    "fw_dma_service_latency_last_cycles_after": 21,
    "fw_dma_service_latency_max_cycles_after": 21,
    "fw_dma_service_latency_accum_cycles_delta": 21,
    "fw_dma_service_latency_budget_cycles": 1000,
    "fw_dma_service_latency_within_budget": True,
    "fw_dma_service_latency_hardware_budget_programmed": True,
    "fw_dma_service_latency_budget_ok_after": True,
    "fw_dma_service_latency_over_budget_before": False,
    "fw_dma_service_latency_over_budget_after": False,
    "fw_dma_service_latency_over_budget_count_delta": 0,
    "rf_phy_tx_rx": 0,
    "production_ready": 0,
    "fw_dma_tx_parser_packets_delta": 1,
    "fw_dma_tx_parser_bytes_delta": 64,
    "fw_dma_ingress_packets_delta": 1,
    "fw_dma_ingress_bytes_delta": 64,
    "fw_dma_ingress_desc_publishes_delta": 1,
    "fw_dma_mac_ticks_delta": 3,
}
hardware_progression = {
    "event": "fieldmesh_rf_hardware_progression_evidence",
    "ok": True,
    "reads_hardware": True,
    "writes_hardware": False,
    "c_fpga_native_counter_progression": True,
    "counter_progression_ok": True,
    "drop_error_delta": 0,
    "no_rf_phy_tx_rx_claim": True,
    "no_production_ready_claim": True,
    "required_counter_deltas": {
        "fw_dma_tx_parser_packets_delta": 1,
        "fw_dma_tx_parser_bytes_delta": 64,
        "fw_dma_ingress_packets_delta": 1,
        "fw_dma_ingress_bytes_delta": 64,
        "fw_dma_ingress_desc_publishes_delta": 1,
        "fw_dma_mac_ticks_delta": 3,
    },
    "counter_snapshots": {
        "mac_ticks": {"before": 10, "after": 13, "delta": 3},
        "ingress_packets": {"before": 4, "after": 5, "delta": 1},
        "egress_packets": {"before": 1, "after": 1, "delta": 0},
        "bram_errors": {"before": 0, "after": 0, "delta": 0},
    },
    "submit_latency_evidence": {
        "dma_smoke_tx_polls": 2,
        "dma_smoke_rx_polls": 0,
    },
    "service_latency_evidence": {
        "source": "firmware_dma_endpoint",
        "last_cycles": 21,
        "max_cycles": 21,
        "budget_cycles": 1000,
        "within_budget": True,
        "hardware_budget_programmed": True,
        "hardware_budget_ok": True,
        "over_budget_before": False,
        "over_budget_after": False,
        "over_budget_count_delta": 0,
        "accum_cycles": {"before": 0, "after": 21, "delta": 21},
    },
    "c_modem_service_rate": {
        "required": True,
        "decode_frame_kbps": 14000,
    },
    "source_report": str(evidence_dir / "rf_bind_gate.json"),
}
tx_backend = json.loads((work_dir / "tx-backend-readback-ready.json").read_text(encoding="utf-8"))
app_reports = {
    "messaging_app_report": {
        "event": "fieldmesh_app_real_rf_report",
        "feature": "messaging",
        "transport": "real_rf_phy",
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
    },
    "topology_app_report": {
        "event": "fieldmesh_app_real_rf_report",
        "feature": "topology",
        "transport": "real_rf_phy",
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
    },
    "native_ip_app_report": {
        "event": "fieldmesh_app_real_rf_report",
        "feature": "native_ip",
        "transport": "real_rf_phy",
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
        "requires_tcp_final_exchange_evidence": True,
        "board_tcp_final_exchange_ok": True,
        "host_tcp_final_exchange_ok": True,
    },
}
files = [
    evidence_file("preflight", preflight),
    evidence_file("rf_bind_gate", rf_bind_gate),
    evidence_file("hardware_progression", hardware_progression),
    evidence_file("tx_backend_readback", tx_backend),
    evidence_file("bridge", bridge),
    evidence_file("iq_live_run", iq_live_run),
    evidence_file("messaging_app_report", app_reports["messaging_app_report"]),
    evidence_file("topology_app_report", app_reports["topology_app_report"]),
    evidence_file("native_ip_app_report", app_reports["native_ip_app_report"]),
    evidence_file("production_gate", production_gate),
]
manifest = {
    "event": "fieldmesh_over_air_rf_evidence_manifest",
    "ok": True,
    "production_ready": True,
    "expected_production_ready": True,
    "files": files,
}
manifest_path = write_json(work_dir / "fieldmesh_over_air_rf_evidence_manifest.json", manifest)
manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
sequence = {
    "event": "fieldmesh_over_air_rf_production_sequence",
    "ok": True,
    "production_ready": True,
    "production_blocker": None,
    "bridge_report": str(evidence_dir / "bridge.json"),
    "iq_live_run": str(evidence_dir / "iq_live_run.json"),
    "production_gate": str(evidence_dir / "production_gate.json"),
    "rf_bind_gate_report": str(evidence_dir / "rf_bind_gate.json"),
    "hardware_progression_report": str(evidence_dir / "hardware_progression.json"),
    "tx_backend_readback_report": str(evidence_dir / "tx_backend_readback.json"),
    "evidence_manifest": str(manifest_path),
    "evidence_manifest_sha256": manifest_hash,
}
(work_dir / "rf-sequence-ready.json").write_text(
    json.dumps(sequence, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

missing_readback = dict(sequence)
missing_readback.pop("tx_backend_readback_report")
(work_dir / "rf-sequence-missing-tx-readback.json").write_text(
    json.dumps(missing_readback, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

missing_manifest = dict(sequence)
missing_manifest.pop("evidence_manifest")
missing_manifest.pop("evidence_manifest_sha256")
(work_dir / "rf-sequence-missing-manifest.json").write_text(
    json.dumps(missing_manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

"$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-gate "$work_dir/rf-ready.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-ready.json" \
  --output "$work_dir/ready-summary.json" \
  >"$work_dir/ready-summary.stdout"

python3 - "$work_dir/ready-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("blockers") != []:
    raise SystemExit(f"ready report did not pass: {report}")
PY

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --output "$work_dir/missing-rf-summary.json" \
  >"$work_dir/missing-rf-summary.stdout"; then
  echo "system readiness accepted missing real-RF gate" >&2
  exit 1
fi

python3 - "$work_dir/missing-rf-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "real_rf_production_sequence_missing" not in report.get("blockers", []):
    raise SystemExit(f"missing real-RF sequence blocker not propagated: {report}")
PY

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-missing-tx-readback.json" \
  --output "$work_dir/missing-tx-readback-summary.json" \
  >"$work_dir/missing-tx-readback-summary.stdout"; then
  echo "system readiness accepted real-RF sequence without TX backend readback" >&2
  exit 1
fi

python3 - "$work_dir/missing-tx-readback-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "real_rf_tx_backend_readback_not_proven" not in report.get("blockers", []):
    raise SystemExit(f"missing TX backend readback blocker not propagated: {report}")
if report.get("detail", {}).get("real_rf_tx_backend_readback_ok") is not False:
    raise SystemExit(f"missing TX backend readback detail not recorded: {report}")
PY

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-missing-manifest.json" \
  --output "$work_dir/missing-manifest-summary.json" \
  >"$work_dir/missing-manifest-summary.stdout"; then
  echo "system readiness accepted real-RF sequence without hash-verified evidence manifest" >&2
  exit 1
fi

python3 - "$work_dir/missing-manifest-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "real_rf_evidence_manifest_not_verified" not in report.get("blockers", []):
    raise SystemExit(f"missing RF evidence manifest blocker not propagated: {report}")
if report.get("detail", {}).get("real_rf_evidence_manifest_ok") is not False:
    raise SystemExit(f"missing RF evidence manifest detail not recorded: {report}")
PY

cat >"$work_dir/fake-gnss-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
printf 'REQUIRE_GNSS_FIX=%s\n' "${REQUIRE_GNSS_FIX:-}" >"$out_dir/required_env.txt"
printf 'REQUIRE_GNSS_PPS=%s\n' "${REQUIRE_GNSS_PPS:-}" >>"$out_dir/required_env.txt"
printf 'REQUIRE_GNSS_RECEIVER_HEALTH=%s\n' "${REQUIRE_GNSS_RECEIVER_HEALTH:-}" >>"$out_dir/required_env.txt"
cp "$(dirname "$0")/gnss-blocked.json" "$out_dir/summary.json"
echo "fake_gnss_preflight=pass"
SH
chmod +x "$work_dir/fake-gnss-runner.sh"

cat >"$work_dir/fake-native-ip-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cp "$(dirname "$0")/native-ip-preflight.json" "$out_dir/native_ip_iperf_production_sequence.json"
exit 1
SH
chmod +x "$work_dir/fake-native-ip-runner.sh"

cat >"$work_dir/fake-timepulse-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cp "$(dirname "$0")/timepulse-blocked.json" "$out_dir/summary.json"
echo "fake_timepulse_poll=pass"
SH
chmod +x "$work_dir/fake-timepulse-runner.sh"

if FIELDMESH_GNSS_PREFLIGHT_RUNNER="$work_dir/fake-gnss-runner.sh" \
   FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER="$work_dir/fake-timepulse-runner.sh" \
   FIELDMESH_NATIVE_IP_PREFLIGHT_RUNNER="$work_dir/fake-native-ip-runner.sh" \
   OUT_DIR="$work_dir/current-wrapper" \
   "$repo_root/tools/run_fieldmesh_system_production_readiness.sh" \
   >"$work_dir/current-wrapper.stdout" \
   2>"$work_dir/current-wrapper.stderr"; then
  echo "system readiness wrapper accepted blocked current preflights" >&2
  exit 1
fi

python3 - "$work_dir/current-wrapper/system_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not False:
    raise SystemExit(f"wrapper report claimed production ready: {report}")
for blocker in ("gnss_live_fix_not_ready", "gnss_receiver_health_not_ready", "native_ip_iperf_not_production_ready", "real_rf_production_sequence_missing"):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"wrapper report missing blocker {blocker}: {report}")
if "z103:gnss_timepulse_unlocked_pulse_length_zero" not in report.get("blockers", []):
    raise SystemExit(f"wrapper report missing TIMEPULSE blocker: {report}")
PY

python3 - "$work_dir/current-wrapper/system_readiness_actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_system_readiness_actions":
    raise SystemExit(f"wrapper did not emit action plan: {report}")
actions = {row.get("action_id") for row in report.get("actions", [])}
for action_id in (
    "fix_gnss_receiver_io_overvoltage",
    "obtain_live_gnss_fix",
    "prove_gnss_pps_activity",
    "collect_paired_real_rf_iperf",
    "collect_real_rf_production_sequence",
):
    if action_id not in actions:
        raise SystemExit(f"wrapper action plan missing {action_id}: {report}")
PY

python3 - "$work_dir/current-wrapper/gnss_preflight/required_env.txt" <<'PY'
import sys
from pathlib import Path

env = dict(
    line.split("=", 1)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if "=" in line
)
expected = {
    "REQUIRE_GNSS_FIX": "1",
    "REQUIRE_GNSS_PPS": "1",
    "REQUIRE_GNSS_RECEIVER_HEALTH": "1",
}
if env != expected:
    raise SystemExit(f"system readiness wrapper did not forward GNSS requirements: {env!r}")
PY

GNSS_PREFLIGHT_REPORT="$work_dir/gnss-ready.json" \
GNSS_TIMEPULSE_POLL_REPORT="$work_dir/timepulse-ready.json" \
NATIVE_IP_IPERF_SEQUENCE_REPORT="$work_dir/native-ip-ready.json" \
REAL_RF_PRODUCTION_GATE_REPORT="$work_dir/rf-ready.json" \
REAL_RF_PRODUCTION_SEQUENCE_REPORT="$work_dir/rf-sequence-ready.json" \
RUN_GNSS_PREFLIGHT=0 \
RUN_GNSS_TIMEPULSE_POLL=0 \
RUN_NATIVE_IP_PREFLIGHT=0 \
OUT_DIR="$work_dir/ready-wrapper" \
"$repo_root/tools/run_fieldmesh_system_production_readiness.sh" \
  >"$work_dir/ready-wrapper.stdout" \
  2>"$work_dir/ready-wrapper.stderr"

python3 - "$work_dir/ready-wrapper/system_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("blockers") != []:
    raise SystemExit(f"ready wrapper report did not pass: {report}")
PY

python3 - "$work_dir/ready-wrapper/system_readiness_actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("action_required") is not False or report.get("actions") != []:
    raise SystemExit(f"ready wrapper should emit an empty action plan: {report}")
PY

echo "fieldmesh_system_production_readiness=pass"
