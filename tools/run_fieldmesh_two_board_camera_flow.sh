#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_port="${Z203_PORT:-55431}"
z103_port="${Z103_PORT:-55432}"
z203_app_port="${Z203_APP_PORT:-55441}"
z103_app_port="${Z103_APP_PORT:-55441}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
timeout_ms="${TIMEOUT_MS:-3000}"
force_upload="${FORCE_UPLOAD:-0}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
run_radio_gate="${RUN_RADIO_GATE:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-camera-flow-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
  FORCE_UPLOAD="$force_upload" UPLOAD_IF_MISSING="$upload_if_missing" \
  VARIANT=z203 PORT="$z203_port" TIMEOUT_MS="$timeout_ms" \
  OUT_DIR="$out_dir/z203_source_daemon" \
  "$repo_root/tools/run_fieldmesh_board_sdk_daemon.sh" "$z203_ip"

SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
  FORCE_UPLOAD="$force_upload" UPLOAD_IF_MISSING="$upload_if_missing" \
  VARIANT=z103 PORT="$z103_port" TIMEOUT_MS="$timeout_ms" \
  OUT_DIR="$out_dir/z103_sink_daemon" \
  "$repo_root/tools/run_fieldmesh_board_sdk_daemon.sh" "$z103_ip"

SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
  FORCE_UPLOAD="$force_upload" UPLOAD_IF_MISSING="$upload_if_missing" \
  USE_INSTALLED_DAEMON=1 \
  VARIANT=z203 PORT="$z203_app_port" TIMEOUT_MS="$timeout_ms" \
  PREFERRED_AP_EUI=020000000103 DST_EUI=020000000203 \
  OUT_DIR="$out_dir/z203_source_app_daemon_client" \
  "$repo_root/tools/run_fieldmesh_board_app_daemon_client.sh" "$z203_ip"

SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
  FORCE_UPLOAD="$force_upload" UPLOAD_IF_MISSING="$upload_if_missing" \
  USE_INSTALLED_DAEMON=1 \
  VARIANT=z103 PORT="$z103_app_port" TIMEOUT_MS="$timeout_ms" \
  PREFERRED_AP_EUI=020000000103 DST_EUI=020000000203 \
  OUT_DIR="$out_dir/z103_sink_app_daemon_client" \
  "$repo_root/tools/run_fieldmesh_board_app_daemon_client.sh" "$z103_ip"

if [ "$run_radio_gate" = "1" ]; then
  SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
    Z203_IP="$z203_ip" Z103_IP="$z103_ip" \
    OUT_DIR="$out_dir/two_board_radio_gate" \
    "$repo_root/tools/run_fieldmesh_two_board_radio_gate.sh" >/dev/null
fi

python3 - "$out_dir" "$z203_ip" "$z103_ip" "$z203_port" "$z103_port" "$z203_app_port" "$z103_app_port" "$run_radio_gate" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
z203_ip = sys.argv[2]
z103_ip = sys.argv[3]
z203_port = int(sys.argv[4])
z103_port = int(sys.argv[5])
z203_app_port = int(sys.argv[6])
z103_app_port = int(sys.argv[7])
run_radio_gate = sys.argv[8] == "1"


def load_rows(path):
    rows = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        line = line.strip()
        if line.startswith("{"):
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                if index == len(lines) - 1:
                    continue
                raise
    return rows


def one(rows, event):
    hits = [row for row in rows if row.get("event") == event]
    if not hits:
        raise SystemExit(f"missing event {event}")
    return hits[-1]


def daemon_summary(label, path):
    query = load_rows(path / "host_query.ndjson")
    serve = load_rows(path / "board_daemon.ndjson")
    end = [row for row in serve if row.get("event") == "sdk_daemon_end"]
    if not end or end[-1].get("handled") != 24:
        raise SystemExit(f"{label} daemon did not handle all requests")

    hello = one(query, "sdk_daemon_hello")
    ap_browse = one(query, "sdk_daemon_ap_browse")
    ap_election = one(query, "sdk_daemon_ap_election")
    join_state = one(query, "sdk_daemon_join_state")
    rtls_report = one(query, "sdk_daemon_rtls_report")
    rtls = one(query, "sdk_daemon_rtls_state")
    rtls_position = one(query, "sdk_daemon_rtls_position")
    route_metrics = one(query, "sdk_daemon_route_metrics")
    camera_session = one(query, "sdk_daemon_camera_session_plan")
    camera_adaptation = one(query, "sdk_daemon_camera_adaptation")
    camera_chunk = one(query, "sdk_daemon_camera_stream_chunk")
    app_cameras = [row for row in query if row.get("event") == "sdk_daemon_app_control_camera"]
    if not app_cameras:
        raise SystemExit(f"{label} missing app camera response")
    app_camera = app_cameras[0]
    app_camera_explicit = [
        row for row in app_cameras
        if row.get("selection_mode") == "user_explicit"
    ]
    rf_engine = one(query, "sdk_daemon_rf_packet_engine")

    if hello.get("protocol") != "fieldmesh-eth-sdk" or hello.get("sdk_abi") != "pure_c":
        raise SystemExit(f"{label} HELLO protocol/ABI failed")
    if hello.get("auth_model") != "root_ca_derived_certs":
        raise SystemExit(f"{label} HELLO auth model failed")
    if hello.get("supports_app_control_camera") != 1 or hello.get("supports_camera_stream_chunk") != 1:
        raise SystemExit(f"{label} HELLO app/camera capabilities failed")
    if hello.get("uses_inter_board_ip_routing") != 0 or hello.get("starts_rf_tx") != 0:
        raise SystemExit(f"{label} HELLO safety invariants failed")
    if ap_browse.get("aps", 0) < 1 or ap_election.get("elected_node_id") != "020000000203":
        raise SystemExit(f"{label} AP browse/election failed")
    if join_state.get("joined") is not True or join_state.get("selected_mode") != 4:
        raise SystemExit(f"{label} join/scheduled-mode state failed")
    if rtls.get("positions") != 2 or rtls.get("packet_timing_tdoa") != 1:
        raise SystemExit(f"{label} RTLS state failed")
    if rtls_report.get("ok") is not True:
        raise SystemExit(f"{label} RTLS report failed")
    if rtls_report.get("measurement_api") != "fieldmesh_report_rtls_measurement":
        raise SystemExit(f"{label} RTLS report did not use SDK measurement API")
    if rtls_report.get("updates_peer_registry") != 1:
        raise SystemExit(f"{label} RTLS report did not update peer registry")
    if rtls_report.get("x_cm") != 200 or rtls_report.get("y_cm") != 120:
        raise SystemExit(f"{label} RTLS report did not publish updated position")
    if rtls_position.get("ok") is not True:
        raise SystemExit(f"{label} RTLS position failed")
    if rtls_position.get("x_cm") != rtls_report.get("x_cm") or rtls_position.get("y_cm") != rtls_report.get("y_cm"):
        raise SystemExit(f"{label} RTLS position did not reflect latest report")
    if rtls_position.get("position_source") not in ("gps_pps_fused", "packet_timing_tdoa"):
        raise SystemExit(f"{label} RTLS position source is not usable")
    if rtls_position.get("radio_topology_only") != 1 or rtls_position.get("host_eth_topology") != 0:
        raise SystemExit(f"{label} RTLS position confused host Ethernet with radio topology")
    if route_metrics.get("ok") is not True or route_metrics.get("metrics_api") != "fieldmesh_query_route_metrics":
        raise SystemExit(f"{label} route metrics failed")
    if route_metrics.get("current_route") != 1 or route_metrics.get("recommended_route") != 2:
        raise SystemExit(f"{label} route metrics did not recommend relay fallback")
    if route_metrics.get("uses_iio") != 0 or route_metrics.get("uses_inter_board_ip_routing") != 0:
        raise SystemExit(f"{label} route metrics must not use IIO or inter-board IP routing")
    if camera_session.get("ok") is not True or camera_session.get("session_api") != "fieldmesh_plan_camera_stream_session":
        raise SystemExit(f"{label} camera session plan failed")
    if camera_adaptation.get("ok") is not True or camera_adaptation.get("adapt_api") != "fieldmesh_adapt_camera_stream_session":
        raise SystemExit(f"{label} camera adaptation failed")
    if camera_adaptation.get("metrics_api") != "fieldmesh_query_route_metrics":
        raise SystemExit(f"{label} camera adaptation did not consume route metrics")
    if camera_adaptation.get("recommended_route") != 2 or camera_adaptation.get("selected_route") != 2:
        raise SystemExit(f"{label} camera adaptation did not switch to AP relay")
    if camera_chunk.get("ok") is not True or camera_chunk.get("preview_match") != 1:
        raise SystemExit(f"{label} camera chunk preview failed")
    if app_camera.get("control_plane_ok") is not True or app_camera.get("data_plane_ok") is not True:
        raise SystemExit(f"{label} app camera plane status failed")
    if app_camera.get("selection_mode") != "auto_election" or app_camera.get("dst_device_eui") != "020000000103":
        raise SystemExit(f"{label} default app camera operation fields failed")
    if not app_camera_explicit:
        raise SystemExit(f"{label} explicit app camera operation missing")
    if app_camera_explicit[0].get("elected_device_eui") != "020000000103":
        raise SystemExit(f"{label} explicit app camera AP selection failed")
    if app_camera_explicit[0].get("dst_device_eui") != "020000000203":
        raise SystemExit(f"{label} explicit app camera destination failed")
    if app_camera_explicit[0].get("control_plane_ok") is not True or app_camera_explicit[0].get("data_plane_ok") is not True:
        raise SystemExit(f"{label} explicit app camera plane status failed")
    if rf_engine.get("queued_to_sidecar") != 1 or rf_engine.get("queued_to_rf_engine") != 1:
        raise SystemExit(f"{label} RF packet-engine handoff failed")

    for row_name, row in (
        ("camera_session", camera_session),
        ("camera_adaptation", camera_adaptation),
        ("camera_chunk", camera_chunk),
        ("app_camera", app_camera),
        ("rf_engine", rf_engine),
    ):
        for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
            if row.get(key) not in (0, False, None):
                raise SystemExit(f"{label} {row_name} key {key} must stay false")

    return {
        "label": label,
        "hello_protocol": hello.get("protocol"),
        "hello_auth_model": hello.get("auth_model"),
        "ap_count": ap_browse.get("aps"),
        "elected_ap": ap_election.get("elected_node_id"),
        "joined": join_state.get("joined"),
        "selected_mode": join_state.get("selected_mode"),
        "rtls_positions": rtls.get("positions"),
        "rtls_report_source": rtls_report.get("position_source"),
        "rtls_report_x_cm": rtls_report.get("x_cm"),
        "rtls_report_y_cm": rtls_report.get("y_cm"),
        "rtls_position_source": rtls_position.get("position_source"),
        "rtls_position_error_radius_cm": rtls_position.get("error_radius_cm"),
        "packet_timing_tdoa": rtls.get("packet_timing_tdoa"),
        "route_metrics_api": route_metrics.get("metrics_api"),
        "route_recommended_route": route_metrics.get("recommended_route"),
        "route_snr_db": route_metrics.get("snr_db"),
        "route_per_mille": route_metrics.get("per_mille"),
        "route_queue_age_ms": route_metrics.get("queue_age_ms"),
        "camera_session_api": camera_session.get("session_api"),
        "camera_adaptation_api": camera_adaptation.get("adapt_api"),
        "camera_adaptation_action": camera_adaptation.get("action"),
        "camera_selected_route": camera_adaptation.get("selected_route"),
        "camera_target_fps": camera_adaptation.get("target_fps"),
        "camera_target_bitrate_kbps": camera_adaptation.get("target_bitrate_kbps"),
        "camera_chunk_bytes": camera_chunk.get("input_bytes"),
        "camera_chunk_preview_match": camera_chunk.get("preview_match"),
        "app_frames_tx": app_camera.get("frames_tx"),
        "app_frames_rx": app_camera.get("frames_rx"),
        "app_preview_matches": app_camera.get("preview_matches"),
        "rf_queued": app_camera.get("rf_queued"),
        "rf_engine": rf_engine.get("rf_engine"),
        "queued_to_sidecar": rf_engine.get("queued_to_sidecar"),
        "queued_to_rf_engine": rf_engine.get("queued_to_rf_engine"),
    }


source = daemon_summary("logical_host_a_z203_source", out_dir / "z203_source_daemon")
sink = daemon_summary("logical_host_b_z103_sink", out_dir / "z103_sink_daemon")
source_app = json.loads(
    (out_dir / "z203_source_app_daemon_client" / "app_daemon_client.json").read_text(
        encoding="utf-8"
    )
)
sink_app = json.loads(
    (out_dir / "z103_sink_app_daemon_client" / "app_daemon_client.json").read_text(
        encoding="utf-8"
    )
)
for label, app_summary, expected_ip, expected_port in (
    ("source_app", source_app, z203_ip, z203_app_port),
    ("sink_app", sink_app, z103_ip, z103_app_port),
):
    if app_summary.get("ok") is not True:
        raise SystemExit(f"{label} failed")
    if app_summary.get("board_ip") != expected_ip:
        raise SystemExit(f"{label} board IP mismatch")
    if app_summary.get("daemon_port") != expected_port:
        raise SystemExit(f"{label} daemon port mismatch")
    if app_summary.get("daemon_control_events") != 1:
        raise SystemExit(f"{label} app-control event count changed")
    if app_summary.get("daemon_hello_events") != 1:
        raise SystemExit(f"{label} daemon HELLO event count changed")
    if app_summary.get("daemon_camera_chunk_events") != 3:
        raise SystemExit(f"{label} camera chunk event count changed")
    if app_summary.get("preview_matches_input") is not True:
        raise SystemExit(f"{label} preview did not match input")
    if app_summary.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit(f"{label} used inter-board IP routing")

radio_summary = None
if run_radio_gate:
    radio_path = out_dir / "two_board_radio_gate" / "two_board_radio_gate.json"
    radio_summary = json.loads(radio_path.read_text(encoding="utf-8"))
    if radio_summary.get("ok") is not True:
        raise SystemExit("two-board radio gate failed")
    radio = radio_summary.get("radio_data_plane", {})
    if radio.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("radio gate used inter-board IP routing")
    if radio.get("starts_rf_tx") is not False or radio.get("opens_iio_buffers") is not False:
        raise SystemExit("radio gate must remain non-transmitting/read-only")

result = {
    "event": "fieldmesh_two_board_camera_flow",
    "ok": True,
    "logical_hosts": {
        "host_a": {
            "role": "camera_source",
            "board": "z203",
            "host_facing_transport": "physical_ethernet",
            "board_ip": z203_ip,
            "daemon_port": z203_port,
            "app_daemon_port": z203_app_port,
        },
        "host_b": {
            "role": "camera_preview",
            "board": "z103",
            "host_facing_transport": "usb_ethernet",
            "board_ip": z103_ip,
            "daemon_port": z103_port,
            "app_daemon_port": z103_app_port,
        },
        "same_physical_pc_allowed": True,
    },
    "control_plane": {
        "peer_discovery": True,
        "ap_election": True,
        "join": True,
        "radio_topology": True,
        "rtls_colocation": True,
        "camera_session_planning": True,
        "camera_route_adaptation": True,
    },
    "data_plane": {
        "camera_chunk_ingress": True,
        "camera_preview_status": True,
        "camera_stream_api": "fieldmesh_camera_stream_frame",
        "rf_packet_engine_handoff": True,
        "expected_inter_board_path": "FieldMesh_RF_sidecar",
        "uses_inter_board_ip_routing": False,
        "uses_iio": False,
        "starts_rf_tx": False,
        "writes_hardware": False,
        "current_gate": "daemon SDK socket plus per-board RF packet-engine handoff readiness",
        "remaining_live_gap": "conducted_or_shielded_over_air_RF_TX_RX",
    },
    "source": source,
    "sink": sink,
    "source_app_daemon_client": source_app,
    "sink_app_daemon_client": sink_app,
    "radio_gate": radio_summary,
}

(out_dir / "two_board_camera_flow.json").write_text(
    json.dumps(result, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps(result, sort_keys=True))
PY

echo "Capture directory: $out_dir"
