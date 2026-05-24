#!/usr/bin/env python3
"""Bridge daemon RF-worker queue frames through the guarded AD936x IIO path.

Default mode is dry-run. It never starts RF TX unless --execute-live-rf is
present with the full live-run authorization set. In execute mode it ACKs the
leased source frame only after the recovered frame is accepted by the sink
daemon via FIELDMESH_RF_RX_INGEST.
"""

from __future__ import annotations

import argparse
import json
import socket
from pathlib import Path
from typing import Any

import fieldmesh_iq_burst_smoke as iq_smoke
import fieldmesh_iq_iio_live_plan as live_plan
import fieldmesh_iq_iio_live_run as live_run


LIVE_RF_CONFIRMATION = "I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH"
LEGACY_LIVE_RF_CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"
VALID_LIVE_RF_CONFIRMATIONS = {LIVE_RF_CONFIRMATION, LEGACY_LIVE_RF_CONFIRMATION}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def request_daemon(host: str, port: int, text: str, timeout_ms: int) -> dict[str, Any]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(text.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(8192)
    finally:
        sock.close()
    decoded = payload.decode("utf-8", errors="replace")
    data = json.loads(decoded)
    if not isinstance(data, dict):
        raise SystemExit(f"daemon response was not an object: {decoded}")
    return data


def load_or_lease_frame(args: argparse.Namespace) -> dict[str, Any]:
    if args.leased_frame_report:
        report = load_json(args.leased_frame_report)
    else:
        if not args.source_host:
            raise SystemExit("--source-host is required when --leased-frame-report is not provided")
        report = request_daemon(
            args.source_host,
            args.source_port,
            "FIELDMESH_RF_TX_LEASE v1",
            args.timeout_ms,
        )
    if report.get("event") != "sdk_daemon_rf_tx_lease":
        raise SystemExit(f"expected sdk_daemon_rf_tx_lease, got {report.get('event')!r}")
    if report.get("ok") is not True or report.get("frames") != 1:
        raise SystemExit(f"leased frame report does not contain one frame: {report}")
    frame_hex = report.get("frame0_hex")
    if not isinstance(frame_hex, str) or not frame_hex:
        raise SystemExit("leased frame report missing frame0_hex")
    try:
        frame = bytes.fromhex(frame_hex)
    except ValueError as exc:
        raise SystemExit("leased frame report contains invalid frame0_hex") from exc
    if report.get("non_destructive") != 1 or report.get("requires_ack") != 1:
        raise SystemExit("leased frame must be non-destructive and require ACK")
    if report.get("uses_inter_board_ip_routing") not in (0, False, None):
        raise SystemExit("leased frame path must not use inter-board host IP routing")
    if report.get("starts_rf_tx") not in (0, False, None) or report.get("writes_hardware") not in (0, False, None):
        raise SystemExit("lease operation must not start RF or write hardware")
    return {"report": report, "frame": frame, "frame_hex": frame_hex}


def write_iq_burst(args: argparse.Namespace, frame: bytes, frame_path: Path) -> dict[str, Any]:
    frame_path.write_bytes(frame)
    smoke_args = argparse.Namespace(
        frame=frame_path,
        out_dir=args.out_dir / "iq-burst",
        center_frequency_hz=args.center_frequency_hz,
        sample_rate_hz=args.sample_rate_hz,
        rf_bandwidth_hz=args.rf_bandwidth_hz,
        fixture_attenuation_db=args.fixture_attenuation_db,
        samples_per_symbol=args.samples_per_symbol,
        modulation=args.modulation,
        baseband_carrier_hz=args.baseband_carrier_hz,
        bfsk_space_hz=args.bfsk_space_hz,
        bfsk_mark_hz=args.bfsk_mark_hz,
        bit_repeat=args.bit_repeat,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        pretty=False,
    )
    return iq_smoke.run(smoke_args)


def write_live_plan(args: argparse.Namespace, iq_report_path: Path) -> dict[str, Any]:
    plan_args = argparse.Namespace(
        rf_binding_plan=args.rf_binding_plan,
        iq_burst_report=iq_report_path,
        tx_board=args.tx_board,
        rx_board=args.rx_board,
        fixture_attenuation_db=args.fixture_attenuation_db,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        legal_frequency_profile=True,
        tx_enable_guard=True,
        rx_first=True,
        out=args.out_dir / "iq-iio-live-plan.json",
        pretty=False,
    )
    plan = live_plan.build_plan(plan_args)
    plan_args.out.write_text(json.dumps(plan, sort_keys=True) + "\n", encoding="utf-8")
    return plan


def write_or_execute_live_run(args: argparse.Namespace, plan_path: Path) -> dict[str, Any]:
    run_args = argparse.Namespace(
        live_plan=plan_path,
        out_dir=args.out_dir / "iq-iio-live-run",
        tx_uri=args.tx_uri,
        rx_uri=args.rx_uri,
        buffer_size=args.buffer_size,
        timeout_ms=args.timeout_ms,
        rx_arm_delay_ms=live_run.DEFAULT_RX_ARM_DELAY_MS,
        rx_capture_margin_ms=live_run.DEFAULT_RX_CAPTURE_MARGIN_MS,
        fixture_attenuation_db=args.fixture_attenuation_db,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        legal_frequency_profile=True,
        tx_enable_guard=True,
        rx_first=True,
        execute_live_rf=args.execute_live_rf,
        allow_hardware_writes=args.allow_hardware_writes,
        allow_rf_tx=args.allow_rf_tx,
        fixture_id=args.fixture_id,
        fixture_evidence=args.fixture_evidence,
        operator_confirmation=args.operator_confirmation,
        max_tx_duration_ms=args.max_tx_duration_ms,
        cyclic_tx=args.cyclic_tx,
        cyclic_capture_periods=args.cyclic_capture_periods,
        rx_gain_control_mode=args.rx_gain_control_mode,
        rx_hardwaregain_db=args.rx_hardwaregain_db,
        tx_hardwaregain_db=args.tx_hardwaregain_db,
        skip_rf_config=getattr(args, "skip_rf_config", False),
        burst_helper=getattr(args, "burst_helper", None),
        pretty=False,
    )
    return live_run.build_report(run_args)


def ingest_and_ack(args: argparse.Namespace, frame_hex: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if not args.sink_host or not args.source_host:
        raise SystemExit("--source-host and --sink-host are required for execute mode ACK/ingest")
    if not args.allow_daemon_queue_mutation:
        raise SystemExit("--allow-daemon-queue-mutation is required for execute mode ACK/ingest")
    ingest = request_daemon(
        args.sink_host,
        args.sink_port,
        "FIELDMESH_RF_RX_INGEST v1 " + frame_hex,
        args.timeout_ms,
    )
    if ingest.get("ok") is not True:
        raise SystemExit(f"sink RF_RX_INGEST failed: {ingest}")
    ack = request_daemon(
        args.source_host,
        args.source_port,
        "FIELDMESH_RF_TX_ACK v1 " + frame_hex,
        args.timeout_ms,
    )
    if ack.get("ok") is not True:
        raise SystemExit(f"source RF_TX_ACK failed after successful ingest: {ack}")
    return ingest, ack


def require_execute_args(args: argparse.Namespace) -> None:
    if not args.execute_live_rf:
        return
    if not args.allow_hardware_writes:
        raise SystemExit("--execute-live-rf requires --allow-hardware-writes")
    if not args.allow_rf_tx:
        raise SystemExit("--execute-live-rf requires --allow-rf-tx")
    if args.operator_confirmation not in VALID_LIVE_RF_CONFIRMATIONS:
        raise SystemExit(f"--execute-live-rf requires --operator-confirmation {LIVE_RF_CONFIRMATION!r}")
    if not args.fixture_id:
        raise SystemExit("--execute-live-rf requires --fixture-id")
    if not args.fixture_evidence:
        raise SystemExit("--execute-live-rf requires --fixture-evidence")
    if not args.tx_uri or not args.rx_uri:
        raise SystemExit("--execute-live-rf requires --tx-uri and --rx-uri")


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_execute_args(args)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    lease = load_or_lease_frame(args)
    frame_path = args.out_dir / "leased_rf_frame.bin"
    iq_report = write_iq_burst(args, lease["frame"], frame_path)
    iq_report_path = args.out_dir / "iq-burst" / "fieldmesh_iq_burst_smoke.json"
    plan = write_live_plan(args, iq_report_path)
    plan_path = args.out_dir / "iq-iio-live-plan.json"
    run_report = write_or_execute_live_run(args, plan_path)

    recovered_frame_hex = None
    ingest: dict[str, Any] = {"attempted": False, "reason": "dry-run"}
    ack: dict[str, Any] = {"attempted": False, "reason": "dry-run"}
    if args.execute_live_rf:
        decode = run_report.get("decode", {})
        if decode.get("ok") is not True:
            raise SystemExit(f"live IQ decode failed: {decode}")
        recovered_frame_hex = decode.get("recovered_frame_hex")
        if recovered_frame_hex != lease["frame_hex"]:
            raise SystemExit("recovered RF frame does not match leased source frame")
        ingest, ack = ingest_and_ack(args, recovered_frame_hex)

    report = {
        "event": "fieldmesh_iio_rf_worker_bridge",
        "ok": True,
        "mode": "execute-live-rf" if args.execute_live_rf else "dry-run",
        "tx_board": args.tx_board,
        "rx_board": args.rx_board,
        "leased_frame_bytes": len(lease["frame"]),
        "leased_frame_hex": lease["frame_hex"],
        "iq_burst_report": str(iq_report_path),
        "iq_iio_live_plan": str(plan_path),
        "iq_iio_live_run": str(args.out_dir / "iq-iio-live-run" / "fieldmesh_iq_iio_live_run.json"),
        "native_iio_burst_worker_required": run_report.get("native_iio_burst_worker_required") is True,
        "native_iio_burst_worker_proven": run_report.get("native_iio_burst_worker_proven") is True,
        "native_iio_burst_worker_lifecycle_proven": run_report.get("native_iio_burst_worker_lifecycle_proven") is True,
        "native_iio_burst_transport_worker_proven": run_report.get("native_iio_burst_transport_worker_proven") is True,
        "native_iio_burst_transport_session_proven": run_report.get("native_iio_burst_transport_session_proven") is True,
        "native_iio_burst_transport_service_loop_proven": (
            run_report.get("native_iio_burst_transport_service_loop_proven") is True
        ),
        "native_iio_burst_transport_scheduler_proven": (
            run_report.get("native_iio_burst_transport_scheduler_proven") is True
        ),
        "native_iio_burst_transport_autonomous_loop_proven": (
            run_report.get("native_iio_burst_transport_autonomous_loop_proven") is True
        ),
        "iq_recovered_frame_match": recovered_frame_hex == lease["frame_hex"] if args.execute_live_rf else False,
        "sink_ingest": ingest,
        "source_ack": ack,
        "ack_after_successful_ingest_only": True,
        "uses_inter_board_ip_routing": False,
        "transport": "real_rf_phy" if args.execute_live_rf else "guarded_iio_rf_dry_run",
        "rf_phy_tx_rx_verified": bool(args.execute_live_rf),
        "app_verified_real_rf": False,
        "production_ready": False,
        "production_blocker": "app_real_rf_verification_missing" if args.execute_live_rf else "measured_rf_phy_tx_rx_not_verified",
        "safety": {
            "authorized_rf_path": True,
            "conducted_or_shielded": False,
            "legal_frequency_profile": True,
            "tx_enable_guard": True,
            "rx_first": True,
            "allow_hardware_writes": bool(args.allow_hardware_writes),
            "allow_rf_tx": bool(args.allow_rf_tx),
            "allow_daemon_queue_mutation": bool(args.allow_daemon_queue_mutation),
            "python_modem_decode_allowed": False,
            "decode_policy": "compiled_c_modem_required",
            "starts_rf_tx": bool(args.execute_live_rf),
            "writes_hardware": bool(args.execute_live_rf),
        },
        "iq_frame_crc": iq_report["frame"]["frame_crc"],
        "plan_command_steps": len(plan["command_plan"]),
    }
    out_path = args.out_dir / "fieldmesh_iio_rf_worker_bridge.json"
    out_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-binding-plan", type=Path, required=True)
    parser.add_argument("--leased-frame-report", type=Path)
    parser.add_argument("--source-host")
    parser.add_argument("--source-port", type=int, default=55441)
    parser.add_argument("--sink-host")
    parser.add_argument("--sink-port", type=int, default=55441)
    parser.add_argument("--tx-board", choices=("z203", "z103"), default="z203")
    parser.add_argument("--rx-board", choices=("z203", "z103"), default="z103")
    parser.add_argument("--tx-uri")
    parser.add_argument("--rx-uri")
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/iio-rf-worker-bridge"))
    parser.add_argument("--center-frequency-hz", type=int, default=2400000000)
    parser.add_argument("--sample-rate-hz", type=int, default=3072000)
    parser.add_argument("--rf-bandwidth-hz", type=int, default=300000)
    parser.add_argument("--fixture-attenuation-db", type=float, default=60.0)
    parser.add_argument("--samples-per-symbol", type=int, default=64)
    parser.add_argument("--modulation", choices=["bpsk", "bfsk"], default="bfsk")
    parser.add_argument("--baseband-carrier-hz", type=int, default=100000)
    parser.add_argument("--bfsk-space-hz", type=int, default=50000)
    parser.add_argument("--bfsk-mark-hz", type=int, default=150000)
    parser.add_argument("--bit-repeat", type=int, default=4)
    parser.add_argument("--buffer-size", type=int)
    parser.add_argument("--timeout-ms", type=int, default=5000)
    parser.add_argument("--execute-live-rf", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--allow-daemon-queue-mutation", action="store_true")
    parser.add_argument("--fixture-id")
    parser.add_argument("--fixture-evidence", type=Path)
    parser.add_argument("--rf-path-id", dest="fixture_id")
    parser.add_argument("--rf-path-evidence", type=Path, dest="fixture_evidence")
    parser.add_argument("--operator-confirmation")
    parser.add_argument("--max-tx-duration-ms", type=int, default=250)
    parser.add_argument("--cyclic-tx", dest="cyclic_tx", action="store_true", default=True)
    parser.add_argument("--no-cyclic-tx", dest="cyclic_tx", action="store_false")
    parser.add_argument("--cyclic-capture-periods", type=int, default=1)
    parser.add_argument("--rx-gain-control-mode", default="slow_attack")
    parser.add_argument("--rx-hardwaregain-db", type=float)
    parser.add_argument("--tx-hardwaregain-db", type=float, default=0.0)
    parser.add_argument("--skip-rf-config", action="store_true")
    parser.add_argument("--burst-helper", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
