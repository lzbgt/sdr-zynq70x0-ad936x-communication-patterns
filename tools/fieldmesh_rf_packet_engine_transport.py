#!/usr/bin/env python3
"""Run the guarded FieldMesh RF packet-engine transport model."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import zlib
from pathlib import Path
from typing import Any

import fieldmesh_trace_harness as harness


def load_handoff(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
        if row.get("event") == "sdk_daemon_rf_packet_engine":
            rows.append(row)
    if not rows:
        raise SystemExit(f"{path}: missing sdk_daemon_rf_packet_engine event")
    return rows[-1]


def require_handoff_consistency(handoff: dict[str, Any] | None, frame_len: int) -> None:
    if handoff is None:
        return
    required_ones = (
        "queued_to_sidecar",
        "queued_to_rf_engine",
        "requires_sidecar_preflight",
        "requires_rf_tx_guard",
        "uses_sidecar_dma",
        "uses_rf_packet_engine",
    )
    required_zeroes = (
        "uses_iio",
        "uses_inter_board_ip_routing",
        "opens_iio_buffers",
        "starts_rf_tx",
        "writes_hardware",
        "commands_executed",
    )
    if handoff.get("rf_engine") != "fieldmesh_rf_packet_engine":
        raise SystemExit("handoff did not target fieldmesh_rf_packet_engine")
    for key in required_ones:
        if handoff.get(key) != 1:
            raise SystemExit(f"handoff key {key} must be 1")
    for key in required_zeroes:
        if handoff.get(key) != 0:
            raise SystemExit(f"handoff key {key} must be 0")
    if int(handoff.get("frame_bytes", 0)) != frame_len:
        raise SystemExit(
            f"handoff frame_bytes {handoff.get('frame_bytes')} does not match frame length {frame_len}"
        )


def require_rf_guard(args: argparse.Namespace) -> None:
    if not args.conducted_or_shielded:
        raise SystemExit("--conducted-or-shielded is required before RF packet-engine planning")
    if args.fixture_attenuation_db < 30.0:
        raise SystemExit("--fixture-attenuation-db must be >= 30 dB")
    if args.center_frequency_hz <= 0 or args.sample_rate_hz <= 0 or args.rf_bandwidth_hz <= 0:
        raise SystemExit("frequency, sample rate, and RF bandwidth must be positive")
    if args.samples_per_symbol < 2:
        raise SystemExit("--samples-per-symbol must be >= 2")
    if args.bit_repeat == 0:
        raise SystemExit("--bit-repeat must be >= 1")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def run_json(cmd: list[str]) -> dict[str, Any]:
    try:
        completed = subprocess.run(cmd, check=True, text=True, capture_output=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            f"{cmd[0]} failed with rc={exc.returncode}: {exc.stderr.strip() or exc.stdout.strip()}"
        ) from exc
    last_json: dict[str, Any] | None = None
    for line in completed.stdout.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            last_json = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{cmd[0]} emitted invalid JSON: {line}") from exc
    if last_json is None:
        raise SystemExit(f"{cmd[0]} did not emit a JSON status line")
    return last_json


def helper_supports_c_bpsk(helper: Path) -> bool:
    try:
        completed = subprocess.run(
            [str(helper), "--help"],
            check=True,
            text=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    required_help = (
        "--bpsk-self-test",
        "--bpsk-benchmark",
        "--bpsk-encode",
        "--bpsk-decode",
        "--baseband-carrier-hz",
    )
    if not all(token in completed.stdout for token in required_help):
        return False
    try:
        self_test = subprocess.run(
            [str(helper), "--bpsk-self-test"],
            check=True,
            text=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    try:
        report = json.loads(self_test.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        return False
    return (
        report.get("event") == "fieldmesh_bpsk_modem_self_test"
        and report.get("ok") is True
        and report.get("phase_recovery_ok") is True
        and report.get("carrier_ok") is True
    )


def build_default_burst_helper(out_dir: Path) -> Path:
    root = repo_root()
    helper = out_dir / "fieldmesh_iio_burst_xfer"
    source = root / "tools" / "fieldmesh_iio_burst_xfer.c"
    cc = os.environ.get("CC", "cc")
    subprocess.run(
        [
            cc,
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-Werror",
            str(source),
            "-liio",
            "-lpthread",
            "-lm",
            "-o",
            str(helper),
        ],
        check=True,
    )
    if not helper_supports_c_bpsk(helper):
        raise SystemExit(f"built helper lacks C BPSK CLI contract: {helper}")
    return helper


def resolve_burst_helper(args: argparse.Namespace) -> Path:
    if args.burst_helper is not None:
        helper = args.burst_helper
        if not helper.exists():
            raise SystemExit(f"missing --burst-helper: {helper}")
        if not helper_supports_c_bpsk(helper):
            raise SystemExit(f"--burst-helper lacks C BPSK CLI contract: {helper}")
        return helper
    configured = os.environ.get("FIELDMESH_IIO_BURST_HELPER")
    if configured:
        helper = Path(configured)
        if not helper.exists():
            raise SystemExit(f"missing FIELDMESH_IIO_BURST_HELPER: {helper}")
        if not helper_supports_c_bpsk(helper):
            raise SystemExit(f"FIELDMESH_IIO_BURST_HELPER lacks C BPSK CLI contract: {helper}")
        return helper
    cached = repo_root() / ".config" / "fieldmesh" / "bin" / "fieldmesh_iio_burst_xfer"
    if cached.exists() and helper_supports_c_bpsk(cached):
        return cached
    return build_default_burst_helper(args.out_dir)


def run_c_bpsk_roundtrip(
    args: argparse.Namespace,
    frame_crc: int,
) -> tuple[bytes, bytes, dict[str, Any], dict[str, Any], dict[str, Any], Path]:
    helper = resolve_burst_helper(args)
    iq_path = args.out_dir / "fieldmesh_rf_packet_engine_i16le.iq"
    decoded_path = args.out_dir / "fieldmesh_rf_packet_engine_decoded.bin"
    encode = run_json(
        [
            str(helper),
            "--bpsk-encode",
            "--frame-file",
            str(args.frame),
            "--iq-file",
            str(iq_path),
            "--samples-per-symbol",
            str(args.samples_per_symbol),
            "--bit-repeat",
            str(args.bit_repeat),
        ]
    )
    decode = run_json(
        [
            str(helper),
            "--bpsk-decode",
            "--iq-file",
            str(iq_path),
            "--decoded-file",
            str(decoded_path),
            "--expected-frame-len",
            str(args.frame.stat().st_size),
            "--expected-frame-crc",
            f"0x{frame_crc:08x}",
            "--samples-per-symbol",
            str(args.samples_per_symbol),
            "--bit-repeat",
            str(args.bit_repeat),
        ]
    )
    benchmark = run_json(
        [
            str(helper),
            "--bpsk-benchmark",
            "--frame-file",
            str(args.frame),
            "--iterations",
            str(args.benchmark_iterations),
            "--samples-per-symbol",
            str(args.samples_per_symbol),
            "--bit-repeat",
            str(args.bit_repeat),
        ]
    )
    if encode.get("event") != "fieldmesh_bpsk_modem_encode" or encode.get("ok") is not True:
        raise SystemExit(f"C BPSK encode failed: {encode}")
    if decode.get("event") != "fieldmesh_bpsk_modem_decode" or decode.get("ok") is not True:
        raise SystemExit(f"C BPSK decode failed: {decode}")
    if benchmark.get("event") != "fieldmesh_bpsk_modem_benchmark" or benchmark.get("ok") is not True:
        raise SystemExit(f"C BPSK benchmark failed: {benchmark}")
    if benchmark.get("hot_path_language") != "c" or benchmark.get("uses_python_modem") is not False:
        raise SystemExit(f"C BPSK benchmark must stay native: {benchmark}")
    return iq_path.read_bytes(), decoded_path.read_bytes(), encode, decode, benchmark, helper


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_rf_guard(args)
    frame = args.frame.read_bytes()
    parsed = harness.unpack_memory_frame(frame)
    handoff = load_handoff(args.handoff_report)
    require_handoff_consistency(handoff, len(frame))

    frame_crc = zlib.crc32(frame) & 0xFFFFFFFF
    args.out_dir.mkdir(parents=True, exist_ok=True)
    iq, recovered, c_encode, c_decode, c_benchmark, burst_helper = run_c_bpsk_roundtrip(args, frame_crc)
    recovered_parsed = harness.unpack_memory_frame(recovered)
    recovered_ok = recovered == frame
    if not recovered_ok:
        raise SystemExit("RF packet engine recovered frame mismatch")

    iq_path = args.out_dir / "fieldmesh_rf_packet_engine_i16le.iq"

    report = {
        "event": "fieldmesh_rf_packet_engine_transport",
        "ok": True,
        "transport_path": "sdk_adapter_handoff -> sidecar_packet_dma -> fieldmesh_rf_packet_engine -> bpsk_iq_burst -> decoder -> fieldmesh_frame",
        "handoff": {
            "present": handoff is not None,
            "adapter_name": None if handoff is None else handoff.get("adapter_name"),
            "rf_engine": "fieldmesh_rf_packet_engine" if handoff is None else handoff.get("rf_engine"),
            "route_kind": None if handoff is None else handoff.get("route_kind"),
            "queued_to_sidecar": 1 if handoff is None else handoff.get("queued_to_sidecar"),
            "queued_to_rf_engine": 1 if handoff is None else handoff.get("queued_to_rf_engine"),
            "frame_bytes": len(frame),
        },
        "frame": {
            "path": str(args.frame),
            "bytes": len(frame),
            "packet_len": parsed["frame_len"],
            "frame_crc": parsed["frame_crc"],
            "transport_seq": parsed["transport_seq"],
            "src_node": parsed["src_node"],
            "dst_node": parsed["dst_node"],
            "stream_id": parsed["stream_id"],
            "traffic_class": parsed["traffic_class"],
            "mode": parsed["mode"],
            "epoch": parsed["epoch"],
            "slot": parsed["slot"],
            "sequence": parsed["sequence"],
        },
        "engine": {
            "name": "fieldmesh_rf_packet_engine",
            "phy_profile": "fieldmesh_bpsk_nrz_i16le_v1",
            "modem_helper": str(burst_helper),
            "modem_helper_event_encode": c_encode.get("event"),
            "modem_helper_event_decode": c_decode.get("event"),
            "modem_helper_event_benchmark": c_benchmark.get("event"),
            "uses_c_bpsk_helper": True,
            "uses_python_modem": False,
            "preamble_bytes": 16,
            "sync": "FM-IQ1",
            "samples_per_symbol": args.samples_per_symbol,
            "bit_repeat": args.bit_repeat,
            "iq_sample_format": "interleaved int16 little-endian IQ",
            "burst_payload_bytes": 16 + len("FM-IQ1") + 2 + len(frame) + 4,
            "burst_crc": frame_crc,
            "iq_samples": len(iq) // 4,
            "iq_file": str(iq_path),
            "recovered_frame_match": recovered_ok,
            "recovered_frame_crc": recovered_parsed["frame_crc"],
            "benchmark_iterations": c_benchmark.get("iterations"),
            "benchmark_encode_frame_kbps": c_benchmark.get("encode_frame_kbps"),
            "benchmark_decode_frame_kbps": c_benchmark.get("decode_frame_kbps"),
            "benchmark_encode_elapsed_us": c_benchmark.get("encode_elapsed_us"),
            "benchmark_decode_elapsed_us": c_benchmark.get("decode_elapsed_us"),
        },
        "rf_fixture": {
            "center_frequency_hz": args.center_frequency_hz,
            "sample_rate_hz": args.sample_rate_hz,
            "rf_bandwidth_hz": args.rf_bandwidth_hz,
            "fixture_attenuation_db": args.fixture_attenuation_db,
            "conducted_or_shielded": True,
        },
        "safety": {
            "uses_sidecar_dma": True,
            "uses_rf_packet_engine": True,
            "uses_iio": False,
            "uses_inter_board_ip_routing": False,
            "opens_iio_buffers": False,
            "starts_rf_tx": False,
            "writes_hardware": False,
            "commands_executed": False,
            "live_rf_allowed": False,
        },
    }
    report_path = args.out_dir / "fieldmesh_rf_packet_engine_transport.json"
    report_path.write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frame", type=Path, default=Path("resources/fieldmesh/vectors/frame_000.bin"))
    parser.add_argument("--handoff-report", type=Path)
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/rf-packet-engine"))
    parser.add_argument("--center-frequency-hz", type=int, required=True)
    parser.add_argument("--sample-rate-hz", type=int, required=True)
    parser.add_argument("--rf-bandwidth-hz", type=int, required=True)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--samples-per-symbol", type=int, default=8)
    parser.add_argument("--bit-repeat", type=int, default=1)
    parser.add_argument("--benchmark-iterations", type=int, default=50)
    parser.add_argument("--burst-helper", type=Path)
    parser.add_argument("--conducted-or-shielded", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run(args)
    if args.pretty:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
