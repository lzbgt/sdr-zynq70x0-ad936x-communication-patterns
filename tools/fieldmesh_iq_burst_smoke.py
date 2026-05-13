#!/usr/bin/env python3
"""Encode and decode a FieldMesh frame as a guarded AD936x IQ burst smoke."""

from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path
from typing import Any

import fieldmesh_trace_harness as harness


SYNC = b"FM-IQ1"
PREAMBLE = b"\x55" * 16
IQ_AMPLITUDE = 12000


def bytes_to_bits(data: bytes) -> list[int]:
    bits: list[int] = []
    for byte in data:
        for shift in range(7, -1, -1):
            bits.append((byte >> shift) & 1)
    return bits


def bits_to_bytes(bits: list[int]) -> bytes:
    out = bytearray()
    for index in range(0, len(bits) - 7, 8):
        byte = 0
        for bit in bits[index : index + 8]:
            byte = (byte << 1) | (bit & 1)
        out.append(byte)
    return bytes(out)


def burst_payload(frame: bytes) -> bytes:
    return PREAMBLE + SYNC + struct.pack(">H", len(frame)) + frame + struct.pack(">I", zlib.crc32(frame) & 0xFFFFFFFF)


def encode_bpsk_iq(payload: bytes, samples_per_symbol: int) -> bytes:
    samples = bytearray()
    for bit in bytes_to_bits(payload):
        i_value = IQ_AMPLITUDE if bit else -IQ_AMPLITUDE
        for _ in range(samples_per_symbol):
            samples.extend(struct.pack("<hh", i_value, 0))
    return bytes(samples)


def decode_bpsk_iq(iq: bytes, samples_per_symbol: int) -> bytes:
    if len(iq) % 4:
        raise ValueError("IQ data length is not an int16 I/Q multiple")
    total_samples = len(iq) // 4
    if total_samples < samples_per_symbol:
        raise ValueError("IQ data is shorter than one symbol")

    bits: list[int] = []
    usable_samples = total_samples - (total_samples % samples_per_symbol)
    for sample_index in range(0, usable_samples, samples_per_symbol):
        acc = 0
        for offset in range(samples_per_symbol):
            i_value, _q_value = struct.unpack_from("<hh", iq, (sample_index + offset) * 4)
            acc += i_value
        bits.append(1 if acc >= 0 else 0)
    return bits_to_bytes(bits)


def recover_frame(decoded: bytes) -> bytes:
    start = decoded.find(PREAMBLE + SYNC)
    if start < 0:
        raise ValueError("missing IQ burst preamble/sync")
    cursor = start + len(PREAMBLE) + len(SYNC)
    if len(decoded) < cursor + 2:
        raise ValueError("missing IQ burst length")
    frame_len = struct.unpack(">H", decoded[cursor : cursor + 2])[0]
    cursor += 2
    end = cursor + frame_len
    if len(decoded) < end + 4:
        raise ValueError("truncated IQ burst frame")
    frame = decoded[cursor:end]
    crc = struct.unpack(">I", decoded[end : end + 4])[0]
    expected_crc = zlib.crc32(frame) & 0xFFFFFFFF
    if crc != expected_crc:
        raise ValueError(f"bad IQ burst frame CRC 0x{crc:08x} expected 0x{expected_crc:08x}")
    return frame


def require_rf_guard(args: argparse.Namespace) -> None:
    if not args.conducted_or_shielded:
        raise SystemExit("--conducted-or-shielded is required before planning an RF burst")
    if args.fixture_attenuation_db < 30.0:
        raise SystemExit("--fixture-attenuation-db must be >= 30 dB for this smoke gate")
    if args.center_frequency_hz <= 0 or args.sample_rate_hz <= 0 or args.rf_bandwidth_hz <= 0:
        raise SystemExit("frequency, sample rate, and RF bandwidth must be positive")
    if args.samples_per_symbol < 2:
        raise SystemExit("--samples-per-symbol must be >= 2")


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_rf_guard(args)
    frame = args.frame.read_bytes()
    parsed = harness.unpack_memory_frame(frame)
    payload = burst_payload(frame)
    iq = encode_bpsk_iq(payload, args.samples_per_symbol)
    recovered = recover_frame(decode_bpsk_iq(iq, args.samples_per_symbol))
    recovered_parsed = harness.unpack_memory_frame(recovered)
    if recovered != frame:
        raise SystemExit("decoded IQ burst did not reproduce the input FieldMesh frame")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    iq_path = args.out_dir / "fieldmesh_bpsk_burst_i16le.iq"
    iq_path.write_bytes(iq)

    report = {
        "event": "fieldmesh_iq_burst_smoke",
        "ok": True,
        "frame": {
            "path": str(args.frame),
            "bytes": len(frame),
            "transport_seq": parsed.get("transport_seq"),
            "packet_len": parsed.get("frame_len"),
            "frame_crc": parsed.get("frame_crc"),
            "src_node": parsed.get("src_node"),
            "dst_node": parsed.get("dst_node"),
            "stream_id": parsed.get("stream_id"),
            "traffic_class": parsed.get("traffic_class"),
            "mode": parsed.get("mode"),
            "epoch": parsed.get("epoch"),
            "slot": parsed.get("slot"),
            "sequence": parsed.get("sequence"),
        },
        "encoding": {
            "name": "fieldmesh_bpsk_nrz_i16le_v1",
            "preamble_bytes": len(PREAMBLE),
            "sync": SYNC.decode("ascii"),
            "samples_per_symbol": args.samples_per_symbol,
            "iq_sample_format": "interleaved int16 little-endian IQ",
            "burst_payload_bytes": len(payload),
            "iq_samples": len(iq) // 4,
            "iq_file": str(iq_path),
        },
        "rf_fixture": {
            "center_frequency_hz": args.center_frequency_hz,
            "sample_rate_hz": args.sample_rate_hz,
            "rf_bandwidth_hz": args.rf_bandwidth_hz,
            "fixture_attenuation_db": args.fixture_attenuation_db,
            "conducted_or_shielded": True,
        },
        "safety": {
            "opens_iio_buffers": False,
            "starts_rf_tx": False,
            "writes_hardware": False,
            "live_rf_allowed": False,
            "next_live_guard": "explicit TX enable, legal frequency profile, conducted/shielded fixture, attenuation evidence",
        },
        "decode": {
            "recovered_frame_match": True,
            "recovered_transport_seq": recovered_parsed.get("transport_seq"),
            "recovered_frame_crc": recovered_parsed.get("frame_crc"),
        },
    }
    report_path = args.out_dir / "fieldmesh_iq_burst_smoke.json"
    report_path.write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frame", type=Path, default=Path("resources/fieldmesh/vectors/frame_000.bin"))
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/iq-burst-smoke"))
    parser.add_argument("--center-frequency-hz", type=int, required=True)
    parser.add_argument("--sample-rate-hz", type=int, required=True)
    parser.add_argument("--rf-bandwidth-hz", type=int, required=True)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--samples-per-symbol", type=int, default=8)
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
    raise SystemExit(main())
