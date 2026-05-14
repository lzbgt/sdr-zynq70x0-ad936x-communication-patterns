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
    finally:
        for thread in threads:
            thread.join(timeout=1.0)
        for sock in sockets:
            sock.close()
    print("fieldmesh_imgui_runtime_discovery_check=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
