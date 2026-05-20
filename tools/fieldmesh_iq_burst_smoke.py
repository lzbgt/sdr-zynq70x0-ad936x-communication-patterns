#!/usr/bin/env python3
"""Encode and decode a FieldMesh frame as a guarded AD936x IQ burst smoke."""

from __future__ import annotations

import argparse
import json
import math
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


def encode_bpsk_iq(
    payload: bytes,
    samples_per_symbol: int,
    *,
    sample_rate_hz: int | float = 1.0,
    baseband_carrier_hz: int | float = 0.0,
) -> bytes:
    samples = bytearray()
    sample_index = 0
    for bit in bytes_to_bits(payload):
        symbol = IQ_AMPLITUDE if bit else -IQ_AMPLITUDE
        for _ in range(samples_per_symbol):
            if baseband_carrier_hz:
                angle = 2.0 * math.pi * float(baseband_carrier_hz) * sample_index / float(sample_rate_hz)
                i_value = int(round(symbol * math.cos(angle)))
                q_value = int(round(symbol * math.sin(angle)))
            else:
                i_value = symbol
                q_value = 0
            samples.extend(struct.pack("<hh", i_value, 0))
            if baseband_carrier_hz:
                samples[-2:] = struct.pack("<h", q_value)
            sample_index += 1
    return bytes(samples)


def mix_iq(iq: bytes, sample_rate_hz: int | float, frequency_hz: int | float) -> bytes:
    if len(iq) % 4:
        raise ValueError("IQ data length is not an int16 I/Q multiple")
    out = bytearray()
    total_samples = len(iq) // 4
    for sample_index in range(total_samples):
        i_value, q_value = struct.unpack_from("<hh", iq, sample_index * 4)
        sample = complex(i_value, q_value)
        angle = -2.0 * math.pi * float(frequency_hz) * sample_index / float(sample_rate_hz)
        mixed = sample * complex(math.cos(angle), math.sin(angle))
        out.extend(
            struct.pack(
                "<hh",
                max(-32768, min(32767, int(round(mixed.real)))),
                max(-32768, min(32767, int(round(mixed.imag)))),
            )
        )
    return bytes(out)


def decode_bpsk_iq_bits(iq: bytes, samples_per_symbol: int, sample_offset: int = 0) -> list[int]:
    if len(iq) % 4:
        raise ValueError("IQ data length is not an int16 I/Q multiple")
    total_samples = len(iq) // 4
    if total_samples < samples_per_symbol:
        raise ValueError("IQ data is shorter than one symbol")
    if sample_offset < 0 or sample_offset >= samples_per_symbol:
        raise ValueError("sample offset must be within one symbol")

    bits: list[int] = []
    usable_samples = total_samples - ((total_samples - sample_offset) % samples_per_symbol)
    for sample_index in range(sample_offset, usable_samples, samples_per_symbol):
        acc = 0
        for offset in range(samples_per_symbol):
            i_value, _q_value = struct.unpack_from("<hh", iq, (sample_index + offset) * 4)
            acc += i_value
        bits.append(1 if acc >= 0 else 0)
    return bits


def decode_bpsk_iq(iq: bytes, samples_per_symbol: int) -> bytes:
    bits = decode_bpsk_iq_bits(iq, samples_per_symbol)
    return bits_to_bytes(bits)


def complex_symbol_averages(iq: bytes, samples_per_symbol: int, sample_offset: int = 0) -> list[complex]:
    if len(iq) % 4:
        raise ValueError("IQ data length is not an int16 I/Q multiple")
    if sample_offset < 0 or sample_offset >= samples_per_symbol:
        raise ValueError("sample offset must be within one symbol")
    total_samples = len(iq) // 4
    usable_samples = total_samples - ((total_samples - sample_offset) % samples_per_symbol)
    symbols: list[complex] = []
    for sample_index in range(sample_offset, usable_samples, samples_per_symbol):
        acc_i = 0.0
        acc_q = 0.0
        for offset in range(samples_per_symbol):
            i_value, q_value = struct.unpack_from("<hh", iq, (sample_index + offset) * 4)
            acc_i += i_value
            acc_q += q_value
        symbols.append(complex(acc_i / samples_per_symbol, acc_q / samples_per_symbol))
    return symbols


def decode_bpsk_iq_coherent(iq: bytes, samples_per_symbol: int) -> dict[str, Any]:
    """Recover a burst with symbol timing and arbitrary I/Q phase search."""
    sync_bits = bytes_to_bits(PREAMBLE + SYNC)
    expected = [1.0 if bit else -1.0 for bit in sync_bits]
    candidates: list[dict[str, Any]] = []
    last_error = "missing IQ burst preamble/sync"

    for sample_offset in range(samples_per_symbol):
        symbols = complex_symbol_averages(iq, samples_per_symbol, sample_offset)
        if len(symbols) < len(expected):
            continue
        for symbol_start in range(0, len(symbols) - len(expected) + 1):
            window = symbols[symbol_start : symbol_start + len(expected)]
            corr = sum(sample * sign for sample, sign in zip(window, expected, strict=True))
            score = abs(corr) / len(expected)
            if score <= 0.0:
                continue
            phase = corr / abs(corr)
            candidate = {
                "score": score,
                "sample_offset": sample_offset,
                "symbol_start": symbol_start,
                "phase_i": phase.real,
                "phase_q": phase.imag,
                "symbols": symbols,
                "phase": phase,
            }
            candidates.append(candidate)
            if len(candidates) > 64:
                candidates.sort(key=lambda row: row["score"], reverse=True)
                del candidates[64:]

    for candidate in sorted(candidates, key=lambda row: row["score"], reverse=True):
        phase = candidate["phase"]
        symbols = candidate["symbols"][candidate["symbol_start"] :]
        bits = [1 if ((sample * phase.conjugate()).real >= 0.0) else 0 for sample in symbols]
        decoded = bits_to_bytes(bits)
        try:
            recovered = recover_frame(decoded)
        except Exception as exc:  # noqa: BLE001 - keep searching candidate alignments.
            last_error = str(exc)
            candidate["error"] = last_error
            continue
        return {
            "ok": True,
            "recovered": recovered,
            "score": candidate["score"],
            "sample_offset": candidate["sample_offset"],
            "symbol_start": candidate["symbol_start"],
            "phase_i": candidate["phase_i"],
            "phase_q": candidate["phase_q"],
        }
    if candidates:
        best = max(candidates, key=lambda row: row["score"])
        return {
            "ok": False,
            "score": best["score"],
            "sample_offset": best["sample_offset"],
            "symbol_start": best["symbol_start"],
            "phase_i": best["phase_i"],
            "phase_q": best["phase_q"],
            "error": last_error,
        }
    return {"ok": False, "error": last_error, "score": 0.0}


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
    if not args.authorized_rf_path and not args.conducted_or_shielded:
        raise SystemExit("--authorized-rf-path is required before planning an RF burst")
    if args.conducted_or_shielded and args.fixture_attenuation_db < 30.0:
        raise SystemExit("--fixture-attenuation-db must be >= 30 dB for lab-contained smoke gates")
    if args.center_frequency_hz <= 0 or args.sample_rate_hz <= 0 or args.rf_bandwidth_hz <= 0:
        raise SystemExit("frequency, sample rate, and RF bandwidth must be positive")
    if args.samples_per_symbol < 2:
        raise SystemExit("--samples-per-symbol must be >= 2")


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_rf_guard(args)
    frame = args.frame.read_bytes()
    parsed = harness.unpack_memory_frame(frame)
    payload = burst_payload(frame)
    iq = encode_bpsk_iq(
        payload,
        args.samples_per_symbol,
        sample_rate_hz=args.sample_rate_hz,
        baseband_carrier_hz=args.baseband_carrier_hz,
    )
    decode_iq = mix_iq(iq, args.sample_rate_hz, args.baseband_carrier_hz) if args.baseband_carrier_hz else iq
    recovered = recover_frame(decode_bpsk_iq(decode_iq, args.samples_per_symbol))
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
            "baseband_carrier_hz": args.baseband_carrier_hz,
            "burst_payload_bytes": len(payload),
            "iq_samples": len(iq) // 4,
            "iq_file": str(iq_path),
        },
        "rf_fixture": {
            "center_frequency_hz": args.center_frequency_hz,
            "sample_rate_hz": args.sample_rate_hz,
            "rf_bandwidth_hz": args.rf_bandwidth_hz,
            "fixture_attenuation_db": args.fixture_attenuation_db,
            "authorized_rf_path": bool(args.authorized_rf_path or args.conducted_or_shielded),
            "conducted_or_shielded": bool(args.conducted_or_shielded),
        },
        "safety": {
            "opens_iio_buffers": False,
            "starts_rf_tx": False,
            "writes_hardware": False,
            "live_rf_allowed": False,
            "next_live_guard": "explicit TX enable, legal frequency profile, authorized over-air RF path evidence",
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
    parser.add_argument("--baseband-carrier-hz", type=int, default=0)
    parser.add_argument("--authorized-rf-path", action="store_true")
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
