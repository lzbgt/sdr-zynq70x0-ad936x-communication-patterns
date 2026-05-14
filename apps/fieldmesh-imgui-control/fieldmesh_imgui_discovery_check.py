#!/usr/bin/env python3
import json
import socket
import subprocess
import sys
import tempfile
import threading
import os
from pathlib import Path


def serve_until_closed(sock: socket.socket, payload: dict) -> None:
    sock.settimeout(0.2)
    while True:
        try:
            data, addr = sock.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            break
        if b"FIELDMESH_HELLO" in data:
            sock.sendto((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"), addr)
        elif b"FIELDMESH_ROUTE_METRICS" in data:
            route = {
                "event": "sdk_daemon_route_metrics",
                "ok": True,
                "metrics_api": "fieldmesh_query_route_metrics",
                "dst_device_eui": "02aabb000002",
                "relay_device_eui": "02aabb000001",
                "current_route": 2,
                "recommended_route": 2,
                "selected_mode": 2,
                "stream_id": 500,
                "rssi_dbm": -68,
                "snr_db": 11,
                "evm_db": -13,
                "per_mille": 140,
                "ack_latency_ms": 160,
                "jitter_ms": 110,
                "queue_age_ms": 210,
                "delivered_kbps": 760,
                "estimated_kbps": 900,
                "cfo_hz": 1450,
                "doppler_hz": 16,
                "timing_residual_ns": 380,
                "measured_age_ms": 120,
                "direct_reachable": 0,
                "relay_available": 1,
                "uses_iio": 0,
                "uses_inter_board_ip_routing": 0,
            }
            sock.sendto((json.dumps(route, separators=(",", ":")) + "\n").encode("utf-8"), addr)
        elif b"FIELDMESH_RTLS_POSITION" in data:
            text = data.decode("utf-8", errors="ignore")
            dst = payload["device_eui"]
            for part in text.split():
                if part.startswith("dst="):
                    dst = part.split("=", 1)[1]
                    break
            positions = {
                "02aabb000001": {
                    "source": "gps_pps_fused",
                    "x_cm": 0,
                    "y_cm": 0,
                    "error_radius_cm": 120,
                    "confidence": 95,
                },
                "02aabb000002": {
                    "source": "packet_timing_tdoa",
                    "x_cm": 160,
                    "y_cm": 80,
                    "error_radius_cm": 420,
                    "confidence": 76,
                },
            }
            position = positions.get(dst)
            if position is None:
                rtls = {
                    "event": "sdk_daemon_rtls_position",
                    "ok": False,
                    "dst_device_eui": dst,
                    "error": "position_unavailable",
                }
            else:
                rtls = {
                    "event": "sdk_daemon_rtls_position",
                    "ok": True,
                    "dst_device_eui": dst,
                    "position_source": position["source"],
                    "x_cm": position["x_cm"],
                    "y_cm": position["y_cm"],
                    "error_radius_cm": position["error_radius_cm"],
                    "confidence": position["confidence"],
                    "usable_for_ap_election": 1,
                    "usable_for_routing": 1,
                    "measured_age_ms": 60,
                    "radio_topology_only": 1,
                    "host_eth_topology": 0,
                }
            sock.sendto((json.dumps(rtls, separators=(",", ":")) + "\n").encode("utf-8"), addr)
        elif b"FIELDMESH_RADIO_CONFIG_PLAN" in data:
            radio = {
                "event": "sdk_daemon_radio_config_plan",
                "ok": True,
                "config_source": "app_sdk_daemon",
                "frequency_mhz": 2400,
                "channel": 1,
                "bandwidth_khz": 5000,
                "sample_rate_ksps": 7680,
                "modulation": "BPSK",
                "fec": "LDPC",
                "adaptive_mcs": 1,
                "direct_p2p": 1,
                "ap_relay_fallback": 1,
                "requires_guarded_apply": 1,
                "writes_hardware": 0,
                "commands_executed": 0,
                "starts_rf_tx": 0,
            }
            sock.sendto((json.dumps(radio, separators=(",", ":")) + "\n").encode("utf-8"), addr)


def bind_server(payload: dict) -> tuple[socket.socket, int, threading.Thread]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    thread = threading.Thread(target=serve_until_closed, args=(sock, payload), daemon=True)
    thread.start()
    return sock, port, thread


def hello(device_eui: str, hostname: str, device_type: str) -> dict:
    return {
        "event": "sdk_daemon_hello",
        "ok": True,
        "protocol": "fieldmesh-eth-sdk",
        "protocol_version": 1,
        "daemon": "fieldmesh-state-daemon-demo",
        "sdk_abi": "pure_c",
        "network_id": "fieldmesh-lab",
        "device_eui": device_eui,
        "hostname": hostname,
        "device_type": device_type,
        "auth_model": "root_ca_derived_certs",
        "requires_mutual_auth_for_production": 1,
        "supports_app_control_camera": 1,
        "supports_camera_session_plan": 1,
        "supports_route_metrics": 1,
        "supports_rtls_position": 1,
        "supports_camera_stream_chunk": 1,
        "supports_tun_gateway": 1,
        "supports_rf_packet_engine": 1,
        "uses_iio_data_path": 0,
        "uses_inter_board_ip_routing": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
    }


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} HEADLESS_APP")
    app = Path(sys.argv[1])
    server_a = bind_server(hello("02aabb000001", "fieldmesh-a", "z203-2r2t"))
    server_b = bind_server(hello("02aabb000002", "fieldmesh-b", "z103-1r1t"))
    sockets = [server_a[0], server_b[0]]
    threads = [server_a[2], server_b[2]]
    candidates = f"127.0.0.1:{server_a[1]},127.0.0.1:{server_b[1]}"
    try:
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env["FIELDMESH_IM_BUS_DIR"] = str(Path(tmp) / "im-bus")
            default_snapshot = Path(tmp) / "default.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--snapshot-output",
                    str(default_snapshot),
                ],
                check=True,
                env=env,
            )
            default_data = json.loads(default_snapshot.read_text(encoding="utf-8"))
            if default_data["profile_source"] != "runtime_discovery":
                raise SystemExit("GUI did not use runtime discovery without profile")
            if default_data["detected_board_count"] != 2:
                raise SystemExit("GUI did not discover both board daemons")
            if default_data["connected_to_board"]:
                raise SystemExit("runtime discovery must not auto-connect to the first board")
            if default_data["selected_board_eui"] != "":
                raise SystemExit("runtime discovery must wait for explicit board selection")
            if default_data["topology_position_model_peers"] != 0:
                raise SystemExit("runtime discovery must not fabricate topology coordinates")
            if default_data["topology_max_peer_range_m"] >= 0:
                raise SystemExit("runtime discovery must not report a synthetic peer range")

            snapshot = Path(tmp) / "selected.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--api-run-python",
                    "--snapshot-output",
                    str(snapshot),
                ],
                check=True,
                env=env,
            )
            data = json.loads(snapshot.read_text(encoding="utf-8"))
            if data["profile_source"] != "runtime_discovery":
                raise SystemExit("GUI did not use runtime discovery without profile")
            if data["detected_board_count"] != 2:
                raise SystemExit("GUI did not discover both board daemons")
            if data["selected_board_eui"] != "02aabb000002":
                raise SystemExit("explicit discovered-board selection failed")
            if data["selected_board_host"] != "127.0.0.1":
                raise SystemExit("discovered daemon host not preserved")
            if data["local_board_eui"] != "02aabb000002":
                raise SystemExit("connected local board identity is not explicit")
            if data["active_remote_peer_eui"] != "02aabb000001":
                raise SystemExit("remote peer should be distinct from the local board")
            if data["python_automation_runs"] != 1:
                raise SystemExit("embedded Python automation action was not surfaced")

            topology_snapshot = Path(tmp) / "topology_refresh.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--api-refresh-topology",
                    "--snapshot-output",
                    str(topology_snapshot),
                ],
                check=True,
                env=env,
            )
            topology = json.loads(topology_snapshot.read_text(encoding="utf-8"))
            if topology["topology_metrics_live"] is not True:
                raise SystemExit("topology metrics refresh did not run")
            if topology["topology_route_metrics_overwrite_position"] is not False:
                raise SystemExit("route metrics must not overwrite topology coordinates")
            if topology["topology_position_model_peers"] != 2:
                raise SystemExit("RTLS refresh did not populate both peer positions")
            if topology["topology_gnss_position_peers"] < 1:
                raise SystemExit("GNSS/BDS position source was not surfaced")
            if topology["topology_timing_position_peers"] < 1:
                raise SystemExit("TOF/TDOA timing source was not surfaced")
            if not (1.0 <= topology["topology_max_peer_range_m"] <= 2.5):
                raise SystemExit("RTLS refresh did not produce the expected live peer range")

            radio_snapshot = Path(tmp) / "radio_config.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--api-apply-radio-config",
                    "--snapshot-output",
                    str(radio_snapshot),
                ],
                check=True,
                env=env,
            )
            radio = json.loads(radio_snapshot.read_text(encoding="utf-8"))
            if radio["radio_config_daemon_sent"] is not True:
                raise SystemExit("radio config was not sent through app->SDK->daemon")
            if radio["radio_config_daemon_ok"] is not True:
                raise SystemExit("radio config daemon plan failed")
            if radio["radio_config_daemon_writes_hardware"] is not False:
                raise SystemExit("radio config plan must not write hardware")

            send_snapshot = Path(tmp) / "send.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--api-open-chat",
                    "02aabb000002",
                    "--api-send-message",
                    "hello fieldmesh peer",
                    "--snapshot-output",
                    str(send_snapshot),
                ],
                check=True,
                env=env,
            )
            recv_snapshot = Path(tmp) / "recv.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--snapshot-output",
                    str(recv_snapshot),
                ],
                check=True,
                env=env,
            )
            recv = json.loads(recv_snapshot.read_text(encoding="utf-8"))
            if recv["messages_received"] != 1:
                raise SystemExit("peer GUI instance did not receive IM message")
            if recv["last_received_text"] != "hello fieldmesh peer":
                raise SystemExit("received IM text changed")

            invite_snapshot = Path(tmp) / "video_invite.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--api-open-chat",
                    "02aabb000002",
                    "--api-publish-camera",
                    "02aabb000002",
                    "--snapshot-output",
                    str(invite_snapshot),
                ],
                check=True,
                env=env,
            )
            receiver_invite_snapshot = Path(tmp) / "video_receiver_invite.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--snapshot-output",
                    str(receiver_invite_snapshot),
                ],
                check=True,
                env=env,
            )
            receiver_invite = json.loads(receiver_invite_snapshot.read_text(encoding="utf-8"))
            if receiver_invite["incoming_video_invite"] is not True:
                raise SystemExit("peer GUI instance did not receive video invite")
            if receiver_invite["media_session_kind"] != "video":
                raise SystemExit("video invite did not preserve media kind")

            accept_snapshot = Path(tmp) / "video_accept.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--api-accept-video",
                    "--snapshot-output",
                    str(accept_snapshot),
                ],
                check=True,
                env=env,
            )
            sender_active_snapshot = Path(tmp) / "video_sender_active.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--snapshot-output",
                    str(sender_active_snapshot),
                ],
                check=True,
                env=env,
            )
            sender_active = json.loads(sender_active_snapshot.read_text(encoding="utf-8"))
            if sender_active["video_session_active"] is not True:
                raise SystemExit("video sender did not enter active session after accept")
            if sender_active["frames_tx"] < 1:
                raise SystemExit("video sender did not enqueue a camera frame")
            receiver_frame_snapshot = Path(tmp) / "video_receiver_frame.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--snapshot-output",
                    str(receiver_frame_snapshot),
                ],
                check=True,
                env=env,
            )
            receiver_frame = json.loads(receiver_frame_snapshot.read_text(encoding="utf-8"))
            if receiver_frame["frames_rx"] < 1:
                raise SystemExit("video receiver did not receive camera frame")

            screen_env = env.copy()
            screen_env["FIELDMESH_IM_BUS_DIR"] = str(Path(tmp) / "screen-im-bus")
            screen_invite_snapshot = Path(tmp) / "screen_invite.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000001",
                    "--api-open-chat",
                    "02aabb000002",
                    "--api-share-screen",
                    "02aabb000002",
                    "--snapshot-output",
                    str(screen_invite_snapshot),
                ],
                check=True,
                env=screen_env,
            )
            screen_receiver_snapshot = Path(tmp) / "screen_receiver.json"
            subprocess.run(
                [
                    str(app),
                    "--self-test",
                    "--discover-candidates",
                    candidates,
                    "--api-select-board",
                    "02aabb000002",
                    "--snapshot-output",
                    str(screen_receiver_snapshot),
                ],
                check=True,
                env=screen_env,
            )
            screen_receiver = json.loads(screen_receiver_snapshot.read_text(encoding="utf-8"))
            if screen_receiver["incoming_video_invite"] is not True:
                raise SystemExit("peer GUI instance did not receive screen-share invite")
            if screen_receiver["media_session_kind"] != "screen":
                raise SystemExit("screen-share invite did not preserve media kind")
    finally:
        for thread in threads:
            thread.join(timeout=1.0)
        for sock in sockets:
            sock.close()
    print("fieldmesh_imgui_runtime_discovery_check=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
