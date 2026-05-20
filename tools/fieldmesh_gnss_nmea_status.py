#!/usr/bin/env python3
"""Summarize GNSS NMEA fix status from captured sentences."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable


def valid_nmea_checksum(sentence: str) -> bool:
    sentence = sentence.strip()
    if not sentence.startswith("$") or "*" not in sentence:
        return False
    body, checksum = sentence[1:].split("*", 1)
    checksum = checksum[:2]
    if len(checksum) != 2 or any(ch not in "0123456789abcdefABCDEF" for ch in checksum):
        return False
    value = 0
    for ch in body:
        value ^= ord(ch)
    return value == int(checksum, 16)


def sentence_kind(sentence: str) -> str:
    head = sentence.split(",", 1)[0].strip()
    return head[-3:] if len(head) >= 3 else ""


def _int_field(fields: list[str], index: int) -> int | None:
    if index >= len(fields) or fields[index] == "":
        return None
    try:
        return int(fields[index])
    except ValueError:
        return None


def _receiver_warning_blocker(message: str) -> str:
    lowered = message.lower()
    if "ovrvlt" in lowered or "overvoltage" in lowered or "over-voltage" in lowered:
        return "gnss_receiver_io_overvoltage"
    return "gnss_receiver_warning"


def summarize_sentences(sentences: Iterable[str]) -> dict[str, object]:
    valid: list[str] = []
    kinds: set[str] = set()
    latest_gga_quality: int | None = None
    latest_gga_satellites_used: int | None = None
    latest_rmc_status: str | None = None
    latest_gsa_fix_type: int | None = None
    max_gsv_satellites_visible = 0
    receiver_warnings: list[str] = []

    for raw in sentences:
        sentence = raw.strip()
        if not valid_nmea_checksum(sentence):
            continue
        valid.append(sentence)
        kind = sentence_kind(sentence)
        if kind:
            kinds.add(kind)
        fields = sentence.split("*", 1)[0].split(",")
        if kind == "GGA":
            quality = _int_field(fields, 6)
            satellites_used = _int_field(fields, 7)
            if quality is not None:
                latest_gga_quality = quality
            if satellites_used is not None:
                latest_gga_satellites_used = satellites_used
        elif kind == "RMC" and len(fields) > 2 and fields[2]:
            latest_rmc_status = fields[2]
        elif kind == "GSA":
            fix_type = _int_field(fields, 2)
            if fix_type is not None:
                latest_gsa_fix_type = fix_type
        elif kind == "GSV":
            satellites_visible = _int_field(fields, 3)
            if satellites_visible is not None:
                max_gsv_satellites_visible = max(
                    max_gsv_satellites_visible, satellites_visible
                )
        elif kind == "TXT" and len(fields) > 4 and fields[4]:
            receiver_warnings.append(fields[4])

    fix_detected = (
        (latest_gga_quality is not None and latest_gga_quality > 0)
        or latest_rmc_status == "A"
        or (latest_gsa_fix_type is not None and latest_gsa_fix_type >= 2)
    )
    blockers: list[str] = []
    if not valid:
        blockers.append("gnss_uart_no_valid_nmea")
    elif not fix_detected:
        if max_gsv_satellites_visible == 0:
            blockers.append("gnss_no_satellites_visible")
        if latest_gga_quality == 0:
            blockers.append("gnss_gga_quality_no_fix")
        if latest_rmc_status == "V":
            blockers.append("gnss_rmc_status_void")
        if latest_gsa_fix_type == 1:
            blockers.append("gnss_gsa_fix_type_no_fix")
        for warning in receiver_warnings:
            blocker = _receiver_warning_blocker(warning)
            if blocker not in blockers:
                blockers.append(blocker)
        if not blockers:
            blockers.append("gnss_receiver_no_fix")

    return {
        "event": "fieldmesh_gnss_nmea_status",
        "ok": bool(valid) and fix_detected,
        "nmea_detected": bool(valid),
        "nmea_sentence_count": len(valid),
        "sentence_kinds": sorted(kinds),
        "fix_detected": fix_detected,
        "latest_gga_quality": latest_gga_quality,
        "latest_gga_satellites_used": latest_gga_satellites_used,
        "latest_rmc_status": latest_rmc_status,
        "latest_gsa_fix_type": latest_gsa_fix_type,
        "max_gsv_satellites_visible": max_gsv_satellites_visible,
        "receiver_warnings": receiver_warnings,
        "blockers": blockers,
    }


def _read_lines(paths: list[str]) -> list[str]:
    if not paths:
        return sys.stdin.read().splitlines()
    lines: list[str] = []
    for name in paths:
        lines.extend(Path(name).read_text(encoding="utf-8", errors="replace").splitlines())
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args(argv)
    report = summarize_sentences(_read_lines(args.paths))
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
