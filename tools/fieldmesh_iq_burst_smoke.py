#!/usr/bin/env python3
"""Encode and decode a FieldMesh frame as a guarded AD936x IQ burst smoke."""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import subprocess
import zlib
from pathlib import Path
from typing import Any

import fieldmesh_trace_harness as harness


SYNC = b"FM-IQ1"
PREAMBLE = b"\x55" * 16
IQ_AMPLITUDE = 12000
DEFAULT_BFSK_SPACE_HZ = 50000
DEFAULT_BFSK_MARK_HZ = 150000


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


def repeat_bits(bits: list[int], bit_repeat: int) -> list[int]:
    if bit_repeat < 1:
        raise ValueError("bit_repeat must be >= 1")
    if bit_repeat == 1:
        return list(bits)
    out: list[int] = []
    for bit in bits:
        out.extend([bit] * bit_repeat)
    return out


def collapse_repeated_bits(bits: list[int], bit_repeat: int) -> list[int]:
    if bit_repeat < 1:
        raise ValueError("bit_repeat must be >= 1")
    if bit_repeat == 1:
        return list(bits)
    out: list[int] = []
    for index in range(0, len(bits) - bit_repeat + 1, bit_repeat):
        chunk = bits[index : index + bit_repeat]
        out.append(1 if sum(chunk) * 2 >= bit_repeat else 0)
    return out


def bits_to_text(bits: list[int]) -> str:
    return "".join("1" if bit else "0" for bit in bits)


def burst_payload(frame: bytes) -> bytes:
    return PREAMBLE + SYNC + struct.pack(">H", len(frame)) + frame + struct.pack(">I", zlib.crc32(frame) & 0xFFFFFFFF)


def frame_crc32(frame: bytes) -> int:
    return zlib.crc32(frame) & 0xFFFFFFFF


def frame_metadata(frame: bytes) -> dict[str, Any]:
    try:
        parsed = harness.unpack_memory_frame(frame)
    except Exception:
        return {
            "format": "raw_binary_rf_frame",
            "bytes": len(frame),
            "packet_len": len(frame),
            "frame_crc": frame_crc32(frame),
            "transport_seq": None,
            "src_node": None,
            "dst_node": None,
            "stream_id": None,
            "traffic_class": None,
            "mode": None,
            "epoch": None,
            "slot": None,
            "sequence": None,
        }
    return {
        "format": "fieldmesh_memory_frame",
        "bytes": len(frame),
        "packet_len": parsed.get("frame_len"),
        "frame_crc": parsed.get("frame_crc"),
        "transport_seq": parsed.get("transport_seq"),
        "src_node": parsed.get("src_node"),
        "dst_node": parsed.get("dst_node"),
        "stream_id": parsed.get("stream_id"),
        "traffic_class": parsed.get("traffic_class"),
        "mode": parsed.get("mode"),
        "epoch": parsed.get("epoch"),
        "slot": parsed.get("slot"),
        "sequence": parsed.get("sequence"),
    }


def encode_bpsk_iq(
    payload: bytes,
    samples_per_symbol: int,
    *,
    sample_rate_hz: int | float = 1.0,
    baseband_carrier_hz: int | float = 0.0,
    bit_repeat: int = 1,
) -> bytes:
    samples = bytearray()
    sample_index = 0
    for bit in repeat_bits(bytes_to_bits(payload), bit_repeat):
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


def encode_bfsk_iq(
    payload: bytes,
    samples_per_symbol: int,
    *,
    sample_rate_hz: int | float,
    space_hz: int | float,
    mark_hz: int | float,
    bit_repeat: int = 1,
) -> bytes:
    samples = bytearray()
    phase = 0.0
    for bit in repeat_bits(bytes_to_bits(payload), bit_repeat):
        frequency = float(mark_hz if bit else space_hz)
        phase_step = 2.0 * math.pi * frequency / float(sample_rate_hz)
        for _ in range(samples_per_symbol):
            i_value = int(round(IQ_AMPLITUDE * math.cos(phase)))
            q_value = int(round(IQ_AMPLITUDE * math.sin(phase)))
            samples.extend(struct.pack("<hh", i_value, q_value))
            phase = (phase + phase_step) % (2.0 * math.pi)
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


def decode_bfsk_iq_bits(
    iq: bytes,
    samples_per_symbol: int,
    *,
    sample_rate_hz: int | float,
    space_hz: int | float,
    mark_hz: int | float,
    sample_offset: int = 0,
) -> list[int]:
    space_prefix, mark_prefix = bfsk_tone_prefixes(
        iq,
        sample_rate_hz=sample_rate_hz,
        space_hz=space_hz,
        mark_hz=mark_hz,
    )
    return decode_bfsk_iq_bits_from_prefixes(
        space_prefix,
        mark_prefix,
        samples_per_symbol,
        sample_offset=sample_offset,
    )


def bfsk_tone_prefixes(
    iq: bytes,
    *,
    sample_rate_hz: int | float,
    space_hz: int | float,
    mark_hz: int | float,
) -> tuple[list[complex], list[complex]]:
    if len(iq) % 4:
        raise ValueError("IQ data length is not an int16 I/Q multiple")
    total_samples = len(iq) // 4
    sample_rate = float(sample_rate_hz)
    if sample_rate <= 0.0:
        raise ValueError("sample rate must be positive")

    space_step = complex(
        math.cos(-2.0 * math.pi * float(space_hz) / sample_rate),
        math.sin(-2.0 * math.pi * float(space_hz) / sample_rate),
    )
    mark_step = complex(
        math.cos(-2.0 * math.pi * float(mark_hz) / sample_rate),
        math.sin(-2.0 * math.pi * float(mark_hz) / sample_rate),
    )
    space_phase = 1.0 + 0.0j
    mark_phase = 1.0 + 0.0j
    space_prefix: list[complex] = [0j]
    mark_prefix: list[complex] = [0j]
    space_acc = 0j
    mark_acc = 0j
    for sample_index in range(total_samples):
        i_value, q_value = struct.unpack_from("<hh", iq, sample_index * 4)
        sample = complex(i_value, q_value)
        space_acc += sample * space_phase
        mark_acc += sample * mark_phase
        space_prefix.append(space_acc)
        mark_prefix.append(mark_acc)
        space_phase *= space_step
        mark_phase *= mark_step
    return space_prefix, mark_prefix


def decode_bfsk_iq_bits_from_prefixes(
    space_prefix: list[complex],
    mark_prefix: list[complex],
    samples_per_symbol: int,
    *,
    sample_offset: int = 0,
) -> list[int]:
    if len(space_prefix) != len(mark_prefix):
        raise ValueError("BFSK prefix lengths differ")
    total_samples = len(space_prefix) - 1
    if total_samples < samples_per_symbol:
        raise ValueError("IQ data is shorter than one symbol")
    if sample_offset < 0 or sample_offset >= samples_per_symbol:
        raise ValueError("sample offset must be within one symbol")

    bits: list[int] = []
    usable_samples = total_samples - ((total_samples - sample_offset) % samples_per_symbol)
    for sample_index in range(sample_offset, usable_samples, samples_per_symbol):
        symbol_end = sample_index + samples_per_symbol
        space_acc = space_prefix[symbol_end] - space_prefix[sample_index]
        mark_acc = mark_prefix[symbol_end] - mark_prefix[sample_index]
        bits.append(1 if abs(mark_acc) >= abs(space_acc) else 0)
    return bits


def decode_bfsk_iq(
    iq: bytes,
    samples_per_symbol: int,
    *,
    sample_rate_hz: int | float,
    space_hz: int | float,
    mark_hz: int | float,
    expected_frame_len: int | None = None,
    expected_frame_crc: int | None = None,
    bit_repeat: int = 1,
) -> dict[str, Any]:
    sync_bits = bytes_to_bits(PREAMBLE + SYNC)
    required_bits = len(sync_bits) + 16 + 32
    if expected_frame_len is not None:
        required_bits += expected_frame_len * 8
    candidates: list[dict[str, Any]] = []
    last_error = "missing IQ burst preamble/sync"
    sync_text = bits_to_text(sync_bits)
    space_prefix, mark_prefix = bfsk_tone_prefixes(
        iq,
        sample_rate_hz=sample_rate_hz,
        space_hz=space_hz,
        mark_hz=mark_hz,
    )
    decoded_bit_sets: list[dict[str, Any]] = []
    for sample_offset in range(samples_per_symbol):
        chip_bits = decode_bfsk_iq_bits_from_prefixes(
            space_prefix,
            mark_prefix,
            samples_per_symbol,
            sample_offset=sample_offset,
        )
        for chip_phase in range(bit_repeat):
            bits = collapse_repeated_bits(chip_bits[chip_phase:], bit_repeat)
            if len(bits) < required_bits:
                continue
            # Cyclic TX captures can begin in the middle of a repeated frame.
            # Append one frame's worth of leading bits so a valid sync near the
            # end can still recover the wrapped length/frame/CRC tail.
            decode_bits = bits + bits[:required_bits]
            decode_text = bits_to_text(decode_bits)
            bit_start = decode_text.find(sync_text)
            while bit_start >= 0 and bit_start < len(bits):
                candidates.append(
                    {
                        "sync_errors": 0,
                        "sample_offset": sample_offset,
                        "chip_phase": chip_phase,
                        "bit_start": bit_start,
                        "bits": decode_bits,
                        "wrapped": bit_start + required_bits > len(bits),
                    }
                )
                bit_start = decode_text.find(sync_text, bit_start + 1)
            decoded_bit_sets.append(
                {
                    "sample_offset": sample_offset,
                    "chip_phase": chip_phase,
                    "bits": bits,
                    "decode_bits": decode_bits,
                }
            )

    if not candidates:
        for decoded in decoded_bit_sets:
            bits = decoded["bits"]
            decode_bits = decoded["decode_bits"]
            for bit_start in range(0, len(bits)):
                sync_errors = sum(
                    expected_bit != hard_bit
                    for expected_bit, hard_bit in zip(
                        sync_bits,
                        decode_bits[bit_start : bit_start + len(sync_bits)],
                        strict=True,
                    )
                )
                if sync_errors <= min(8, len(sync_bits) // 16):
                    candidates.append(
                        {
                            "sync_errors": sync_errors,
                            "sample_offset": decoded["sample_offset"],
                            "chip_phase": decoded["chip_phase"],
                            "bit_start": bit_start,
                            "bits": decode_bits,
                            "wrapped": bit_start + required_bits > len(bits),
                        }
                    )

    crc_mismatches: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=lambda row: (row["sync_errors"], row["wrapped"], row["bit_start"])):
        try:
            recovered = recover_frame_after_sync_bits(
                candidate["bits"][candidate["bit_start"] :],
                len(sync_bits),
                expected_frame_len=expected_frame_len,
            )
        except Exception as exc:  # noqa: BLE001 - keep searching candidate alignments.
            last_error = str(exc)
            candidate["error"] = last_error
            continue
        recovered_crc = frame_crc32(recovered)
        if expected_frame_crc is not None and recovered_crc != expected_frame_crc:
            crc_mismatch = dict(candidate)
            crc_mismatch["recovered_frame_crc"] = recovered_crc
            crc_mismatch["expected_frame_crc"] = expected_frame_crc
            crc_mismatch.pop("bits", None)
            crc_mismatches.append(crc_mismatch)
            last_error = (
                f"bad IQ burst frame CRC 0x{recovered_crc:08x} "
                f"expected 0x{expected_frame_crc:08x}"
            )
            continue
        return {
            "ok": True,
            "recovered": recovered,
            "sync_errors": candidate["sync_errors"],
            "sample_offset": candidate["sample_offset"],
            "chip_phase": candidate["chip_phase"],
            "bit_start": candidate["bit_start"],
            "wrapped": candidate["wrapped"],
        }
    if candidates:
        best = min(candidates, key=lambda row: (row["sync_errors"], row["wrapped"], row["bit_start"]))
        if crc_mismatches:
            best_crc = min(crc_mismatches, key=lambda row: (row["sync_errors"], row["wrapped"], row["bit_start"]))
            return {
                "ok": False,
                "sync_errors": best_crc["sync_errors"],
                "sample_offset": best_crc["sample_offset"],
                "chip_phase": best_crc["chip_phase"],
                "bit_start": best_crc["bit_start"],
                "wrapped": best_crc["wrapped"],
                "recovered_frame_crc": best_crc["recovered_frame_crc"],
                "expected_frame_crc": best_crc["expected_frame_crc"],
                "crc_mismatch_candidates": len(crc_mismatches),
                "error": last_error,
            }
        return {
            "ok": False,
            "sync_errors": best["sync_errors"],
            "sample_offset": best["sample_offset"],
            "chip_phase": best["chip_phase"],
            "bit_start": best["bit_start"],
            "wrapped": best["wrapped"],
            "error": last_error,
        }
    return {"ok": False, "error": last_error, "sync_errors": None}


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


def average_repeated_symbols(symbols: list[complex], bit_repeat: int, chip_phase: int) -> list[complex]:
    if bit_repeat < 1:
        raise ValueError("bit_repeat must be >= 1")
    if chip_phase < 0 or chip_phase >= bit_repeat:
        raise ValueError("chip_phase must be within one repeated bit group")
    if bit_repeat == 1:
        return list(symbols)
    averaged: list[complex] = []
    for index in range(chip_phase, len(symbols) - bit_repeat + 1, bit_repeat):
        acc = 0j
        for symbol in symbols[index : index + bit_repeat]:
            acc += symbol
        averaged.append(acc / bit_repeat)
    return averaged


def decode_bpsk_iq_coherent(
    iq: bytes,
    samples_per_symbol: int,
    *,
    expected_frame_len: int | None = None,
    bit_repeat: int = 1,
) -> dict[str, Any]:
    """Recover a burst with symbol timing and arbitrary I/Q phase search."""
    sync_bits = bytes_to_bits(PREAMBLE + SYNC)
    preamble_bits = bytes_to_bits(PREAMBLE)
    expected = [1.0 if bit else -1.0 for bit in sync_bits]
    required_bits = len(expected) + 16 + 32
    if expected_frame_len is not None:
        required_bits += expected_frame_len * 8
    candidates: list[dict[str, Any]] = []
    last_error = "missing IQ burst preamble/sync"

    for sample_offset in range(samples_per_symbol):
        symbols = complex_symbol_averages(iq, samples_per_symbol, sample_offset)
        for chip_phase in range(bit_repeat):
            averaged_symbols = average_repeated_symbols(symbols, bit_repeat, chip_phase)
            if len(averaged_symbols) < required_bits:
                continue
            latest_bit_start = len(averaged_symbols) - required_bits
            alternating_prefix = [0j]
            for index, symbol in enumerate(averaged_symbols):
                alternating_prefix.append(
                    alternating_prefix[-1] + symbol * (-1.0 if index % 2 == 0 else 1.0)
                )
            preamble_candidates: list[dict[str, Any]] = []
            for bit_start in range(0, latest_bit_start + 1):
                # PREAMBLE is 0x55, so this alternating-sum matched filter cheaply
                # finds likely bit-aligned starts before the full sync/CRC check.
                corr = alternating_prefix[bit_start + len(preamble_bits)] - alternating_prefix[bit_start]
                score = abs(corr) / len(preamble_bits)
                preamble_candidates.append({"bit_start": bit_start, "preamble_score": score})
            for preamble_candidate in sorted(
                preamble_candidates,
                key=lambda row: row["preamble_score"],
                reverse=True,
            )[:64]:
                bit_start = int(preamble_candidate["bit_start"])
                window = averaged_symbols[bit_start : bit_start + len(expected)]
                corr = sum(sample * sign for sample, sign in zip(window, expected, strict=True))
                score = abs(corr) / len(expected)
                if score <= 0.0:
                    continue
                phase = corr / abs(corr)
                sync_hard_bits = [
                    1 if ((sample * phase.conjugate()).real >= 0.0) else 0 for sample in window
                ]
                sync_errors = sum(
                    expected_bit != hard_bit
                    for expected_bit, hard_bit in zip(sync_bits, sync_hard_bits, strict=True)
                )
                candidate = {
                    "score": score,
                    "sync_errors": sync_errors,
                    "sample_offset": sample_offset,
                    "chip_phase": chip_phase,
                    "bit_start": bit_start,
                    "symbol_start": chip_phase + bit_start * bit_repeat,
                    "phase_i": phase.real,
                    "phase_q": phase.imag,
                    "symbols": averaged_symbols,
                    "phase": phase,
                    "preamble_score": preamble_candidate["preamble_score"],
                }
                candidates.append(candidate)

    candidate_order = sorted(candidates, key=lambda row: (row["sync_errors"], -row["score"]))
    for candidate in candidate_order:
        phase = candidate["phase"]
        symbols = candidate["symbols"][candidate["bit_start"] :]
        bits = [1 if ((sample * phase.conjugate()).real >= 0.0) else 0 for sample in symbols]
        try:
            recovered = recover_frame_after_sync_bits(
                bits,
                len(sync_bits),
                expected_frame_len=expected_frame_len,
            )
        except Exception as exc:  # noqa: BLE001 - keep searching candidate alignments.
            last_error = str(exc)
            candidate["error"] = last_error
            continue
        return {
            "ok": True,
            "recovered": recovered,
            "score": candidate["score"],
            "sync_errors": candidate["sync_errors"],
            "sample_offset": candidate["sample_offset"],
            "chip_phase": candidate["chip_phase"],
            "bit_start": candidate["bit_start"],
            "symbol_start": candidate["symbol_start"],
            "phase_i": candidate["phase_i"],
            "phase_q": candidate["phase_q"],
        }
    if candidates:
        best = candidate_order[0]
        return {
            "ok": False,
            "score": best["score"],
            "sync_errors": best["sync_errors"],
            "sample_offset": best["sample_offset"],
            "chip_phase": best["chip_phase"],
            "bit_start": best["bit_start"],
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


def recover_frame_after_sync_bits(
    bits: list[int],
    sync_bits: int,
    *,
    expected_frame_len: int | None = None,
) -> bytes:
    cursor = sync_bits
    if expected_frame_len is None:
        if len(bits) < sync_bits + 16:
            raise ValueError("missing IQ burst length")
        length_bytes = bits_to_bytes(bits[cursor : cursor + 16])
        frame_len = struct.unpack(">H", length_bytes)[0]
    else:
        if expected_frame_len <= 0:
            raise ValueError("expected frame length must be positive")
        frame_len = expected_frame_len
    cursor += 16
    frame_bits = frame_len * 8
    crc_bits = 32
    if len(bits) < cursor + frame_bits + crc_bits:
        raise ValueError("truncated IQ burst frame")
    frame = bits_to_bytes(bits[cursor : cursor + frame_bits])
    cursor += frame_bits
    crc = struct.unpack(">I", bits_to_bytes(bits[cursor : cursor + crc_bits]))[0]
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
    if args.bit_repeat < 1:
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


def helper_supports_c_modem(helper: Path) -> bool:
    try:
        completed = subprocess.run(
            [str(helper), "--help"],
            check=True,
            text=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return False
    required = (
        "--bpsk-encode",
        "--bpsk-decode",
        "--bfsk-encode",
        "--bfsk-decode",
        "--baseband-carrier-hz",
    )
    if not all(token in completed.stdout for token in required):
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


def build_default_modem_helper(out_dir: Path) -> Path:
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
    if not helper_supports_c_modem(helper):
        raise SystemExit(f"built modem helper lacks C modem CLI contract: {helper}")
    return helper


def resolve_modem_helper(args: argparse.Namespace) -> Path:
    modem_helper = getattr(args, "modem_helper", None)
    if modem_helper is not None:
        helper = modem_helper
        if not helper.exists():
            raise SystemExit(f"missing --modem-helper: {helper}")
        if not helper_supports_c_modem(helper):
            raise SystemExit(f"--modem-helper lacks C modem CLI contract: {helper}")
        return helper
    configured = os.environ.get("FIELDMESH_IIO_BURST_HELPER")
    if configured:
        helper = Path(configured)
        if not helper.exists():
            raise SystemExit(f"missing FIELDMESH_IIO_BURST_HELPER: {helper}")
        if not helper_supports_c_modem(helper):
            raise SystemExit(f"FIELDMESH_IIO_BURST_HELPER lacks C modem CLI contract: {helper}")
        return helper
    cached = repo_root() / ".config" / "fieldmesh" / "bin" / "fieldmesh_iio_burst_xfer"
    if cached.exists() and helper_supports_c_modem(cached):
        return cached
    return build_default_modem_helper(args.out_dir)


def run_c_modem_roundtrip(args: argparse.Namespace, frame_crc: int) -> tuple[bytes, bytes, dict[str, Any], dict[str, Any], Path]:
    helper = resolve_modem_helper(args)
    iq_path = args.out_dir / "fieldmesh_bpsk_burst_i16le.iq"
    decoded_path = args.out_dir / "fieldmesh_iq_burst_decoded.bin"
    encode_cmd = [
        str(helper),
        f"--{args.modulation}-encode",
        "--frame-file",
        str(args.frame),
        "--iq-file",
        str(iq_path),
        "--sample-rate-hz",
        str(args.sample_rate_hz),
        "--samples-per-symbol",
        str(args.samples_per_symbol),
        "--bit-repeat",
        str(args.bit_repeat),
    ]
    decode_cmd = [
        str(helper),
        f"--{args.modulation}-decode",
        "--iq-file",
        str(iq_path),
        "--decoded-file",
        str(decoded_path),
        "--expected-frame-len",
        str(args.frame.stat().st_size),
        "--expected-frame-crc",
        f"0x{frame_crc:08x}",
        "--sample-rate-hz",
        str(args.sample_rate_hz),
        "--samples-per-symbol",
        str(args.samples_per_symbol),
        "--bit-repeat",
        str(args.bit_repeat),
    ]
    if args.modulation == "bfsk":
        tone_args = [
            "--space-hz",
            str(args.bfsk_space_hz),
            "--mark-hz",
            str(args.bfsk_mark_hz),
        ]
        encode_cmd.extend(tone_args)
        decode_cmd.extend(tone_args)
    elif args.baseband_carrier_hz:
        carrier_args = ["--baseband-carrier-hz", str(args.baseband_carrier_hz)]
        encode_cmd.extend(carrier_args)
        decode_cmd.extend(carrier_args)
    encode = run_json(encode_cmd)
    decode = run_json(decode_cmd)
    expected_encode = f"fieldmesh_{args.modulation}_modem_encode"
    expected_decode = f"fieldmesh_{args.modulation}_modem_decode"
    if encode.get("event") != expected_encode or encode.get("ok") is not True:
        raise SystemExit(f"C {args.modulation.upper()} encode failed: {encode}")
    if decode.get("event") != expected_decode or decode.get("ok") is not True:
        raise SystemExit(f"C {args.modulation.upper()} decode failed: {decode}")
    return iq_path.read_bytes(), decoded_path.read_bytes(), encode, decode, helper


def run_python_modem_roundtrip(args: argparse.Namespace, frame: bytes) -> tuple[bytes, bytes]:
    payload = burst_payload(frame)
    if args.modulation == "bfsk":
        iq = encode_bfsk_iq(
            payload,
            args.samples_per_symbol,
            sample_rate_hz=args.sample_rate_hz,
            space_hz=args.bfsk_space_hz,
            mark_hz=args.bfsk_mark_hz,
            bit_repeat=args.bit_repeat,
        )
        decoded = decode_bfsk_iq(
            iq,
            args.samples_per_symbol,
            sample_rate_hz=args.sample_rate_hz,
            space_hz=args.bfsk_space_hz,
            mark_hz=args.bfsk_mark_hz,
            expected_frame_len=len(frame),
            bit_repeat=args.bit_repeat,
        )
        if decoded.get("ok") is not True:
            raise SystemExit(f"local BFSK decode failed: {decoded}")
        recovered = decoded["recovered"]
    else:
        iq = encode_bpsk_iq(
            payload,
            args.samples_per_symbol,
            sample_rate_hz=args.sample_rate_hz,
            baseband_carrier_hz=args.baseband_carrier_hz,
            bit_repeat=args.bit_repeat,
        )
        decode_iq = mix_iq(iq, args.sample_rate_hz, args.baseband_carrier_hz) if args.baseband_carrier_hz else iq
        recovered = recover_frame(
            bits_to_bytes(
                collapse_repeated_bits(
                    decode_bpsk_iq_bits(decode_iq, args.samples_per_symbol),
                    args.bit_repeat,
                )
            )
        )
    return iq, recovered


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_rf_guard(args)
    frame = args.frame.read_bytes()
    parsed = frame_metadata(frame)
    payload_len = len(PREAMBLE) + len(SYNC) + 2 + len(frame) + 4
    frame_crc = frame_crc32(frame)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    c_encode: dict[str, Any] | None = None
    c_decode: dict[str, Any] | None = None
    modem_helper: Path | None = None
    if getattr(args, "python_modem", False):
        iq, recovered = run_python_modem_roundtrip(args, frame)
        uses_c_modem_helper = False
        uses_python_modem = True
    else:
        iq, recovered, c_encode, c_decode, modem_helper = run_c_modem_roundtrip(args, frame_crc)
        uses_c_modem_helper = True
        uses_python_modem = False
    encoding_name = "fieldmesh_bfsk_i16le_v1" if args.modulation == "bfsk" else "fieldmesh_bpsk_nrz_i16le_v1"
    recovered_parsed = frame_metadata(recovered)
    if recovered != frame:
        raise SystemExit("decoded IQ burst did not reproduce the input FieldMesh frame")

    iq_path = args.out_dir / "fieldmesh_bpsk_burst_i16le.iq"
    if uses_python_modem or not iq_path.exists():
        iq_path.write_bytes(iq)

    report = {
        "event": "fieldmesh_iq_burst_smoke",
        "ok": True,
        "frame": {
            "path": str(args.frame),
            "format": parsed.get("format"),
            "bytes": parsed.get("bytes"),
            "transport_seq": parsed.get("transport_seq"),
            "packet_len": parsed.get("packet_len"),
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
            "name": encoding_name,
            "modulation": args.modulation,
            "preamble_bytes": len(PREAMBLE),
            "sync": SYNC.decode("ascii"),
            "samples_per_symbol": args.samples_per_symbol,
            "iq_sample_format": "interleaved int16 little-endian IQ",
            "baseband_carrier_hz": args.baseband_carrier_hz,
            "bfsk_space_hz": args.bfsk_space_hz if args.modulation == "bfsk" else None,
            "bfsk_mark_hz": args.bfsk_mark_hz if args.modulation == "bfsk" else None,
            "bit_repeat": args.bit_repeat,
            "burst_payload_bytes": payload_len,
            "iq_samples": len(iq) // 4,
            "iq_file": str(iq_path),
            "uses_c_modem_helper": uses_c_modem_helper,
            "uses_python_modem": uses_python_modem,
            "modem_helper": None if modem_helper is None else str(modem_helper),
            "modem_helper_event_encode": None if c_encode is None else c_encode.get("event"),
            "modem_helper_event_decode": None if c_decode is None else c_decode.get("event"),
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
    parser.add_argument("--modulation", choices=["bpsk", "bfsk"], default="bpsk")
    parser.add_argument("--baseband-carrier-hz", type=int, default=0)
    parser.add_argument("--bfsk-space-hz", type=int, default=DEFAULT_BFSK_SPACE_HZ)
    parser.add_argument("--bfsk-mark-hz", type=int, default=DEFAULT_BFSK_MARK_HZ)
    parser.add_argument("--bit-repeat", type=int, default=1)
    parser.add_argument("--modem-helper", type=Path)
    parser.add_argument("--python-modem", action="store_true")
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
