#!/usr/bin/env python3
"""Build and inspect u-blox M10 TIMEPULSE UBX configuration frames."""

from __future__ import annotations

import argparse
import binascii
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SYNC = b"\xb5\x62"
UBX_CFG = 0x06
UBX_CFG_VALSET = 0x8A
UBX_CFG_VALGET = 0x8B
UBX_ACK = 0x05
UBX_ACK_NAK = 0x00
UBX_ACK_ACK = 0x01


@dataclass(frozen=True)
class ConfigKey:
    name: str
    key_id: int
    value_type: str
    unit: str = ""
    description: str = ""


TP_KEYS: dict[str, ConfigKey] = {
    "CFG-TP-PULSE_DEF": ConfigKey(
        "CFG-TP-PULSE_DEF", 0x20050023, "E1", description="0=period, 1=frequency"
    ),
    "CFG-TP-PULSE_LENGTH_DEF": ConfigKey(
        "CFG-TP-PULSE_LENGTH_DEF",
        0x20050030,
        "E1",
        description="1=length in microseconds",
    ),
    "CFG-TP-PERIOD_TP1": ConfigKey(
        "CFG-TP-PERIOD_TP1", 0x40050002, "U4", "us"
    ),
    "CFG-TP-PERIOD_LOCK_TP1": ConfigKey(
        "CFG-TP-PERIOD_LOCK_TP1", 0x40050003, "U4", "us"
    ),
    "CFG-TP-LEN_TP1": ConfigKey("CFG-TP-LEN_TP1", 0x40050004, "U4", "us"),
    "CFG-TP-LEN_LOCK_TP1": ConfigKey(
        "CFG-TP-LEN_LOCK_TP1", 0x40050005, "U4", "us"
    ),
    "CFG-TP-TP1_ENA": ConfigKey(
        "CFG-TP-TP1_ENA", 0x10050007, "L", description="Enable TIMEPULSE"
    ),
    "CFG-TP-SYNC_GNSS_TP1": ConfigKey(
        "CFG-TP-SYNC_GNSS_TP1",
        0x10050008,
        "L",
        description="GNSS time when valid, local clock otherwise",
    ),
    "CFG-TP-USE_LOCKED_TP1": ConfigKey(
        "CFG-TP-USE_LOCKED_TP1", 0x10050009, "L"
    ),
    "CFG-TP-ALIGN_TO_TOW_TP1": ConfigKey(
        "CFG-TP-ALIGN_TO_TOW_TP1", 0x1005000A, "L"
    ),
    "CFG-TP-POL_TP1": ConfigKey(
        "CFG-TP-POL_TP1", 0x1005000B, "L", description="1=rising edge"
    ),
    "CFG-TP-TIMEGRID_TP1": ConfigKey(
        "CFG-TP-TIMEGRID_TP1", 0x2005000C, "E1"
    ),
}

KEYS_BY_ID = {key.key_id: key for key in TP_KEYS.values()}
TIMEGRID_VALUES = {
    "utc": 0,
    "gps": 1,
    "glonass": 2,
    "beidou": 3,
    "galileo": 4,
    "navic": 5,
}
VALGET_LAYERS = {"ram": 0, "bbr": 1, "flash": 2, "default": 7}
VALSET_LAYER_BITS = {"ram": 0x01, "bbr": 0x02, "flash": 0x04}


def ubx_checksum(body: bytes) -> bytes:
    ck_a = 0
    ck_b = 0
    for byte in body:
        ck_a = (ck_a + byte) & 0xFF
        ck_b = (ck_b + ck_a) & 0xFF
    return bytes((ck_a, ck_b))


def ubx_frame(message_class: int, message_id: int, payload: bytes) -> bytes:
    body = bytes((message_class, message_id)) + struct.pack("<H", len(payload)) + payload
    return SYNC + body + ubx_checksum(body)


def validate_frame(frame: bytes) -> bool:
    if len(frame) < 8 or not frame.startswith(SYNC):
        return False
    length = struct.unpack_from("<H", frame, 4)[0]
    end = 6 + length
    if len(frame) != end + 2:
        return False
    return frame[end : end + 2] == ubx_checksum(frame[2:end])


def encode_value(key: ConfigKey, value: int | bool) -> bytes:
    if key.value_type == "L":
        return bytes((1 if bool(value) else 0,))
    if key.value_type == "E1":
        if not 0 <= int(value) <= 0xFF:
            raise ValueError(f"{key.name}: E1 value out of range: {value}")
        return bytes((int(value),))
    if key.value_type == "U4":
        if not 0 <= int(value) <= 0xFFFFFFFF:
            raise ValueError(f"{key.name}: U4 value out of range: {value}")
        return struct.pack("<I", int(value))
    raise ValueError(f"{key.name}: unsupported type {key.value_type}")


def storage_size_from_key_id(key_id: int) -> int:
    size_id = (key_id >> 28) & 0xF
    if size_id in (0x1, 0x2):
        return 1
    if size_id == 0x3:
        return 2
    if size_id == 0x4:
        return 4
    if size_id == 0x5:
        return 8
    raise ValueError(f"unsupported key storage size in 0x{key_id:08x}")


def decode_value(key_id: int, raw: bytes) -> int | bool | str:
    key = KEYS_BY_ID.get(key_id)
    if key and key.value_type == "L":
        return raw[0] != 0
    if len(raw) == 1:
        return raw[0]
    if len(raw) == 2:
        return struct.unpack("<H", raw)[0]
    if len(raw) == 4:
        return struct.unpack("<I", raw)[0]
    return raw.hex()


def valget_request(keys: list[ConfigKey], layer: str) -> bytes:
    payload = struct.pack("<BBH", 0, VALGET_LAYERS[layer], 0)
    payload += b"".join(struct.pack("<I", key.key_id) for key in keys)
    return ubx_frame(UBX_CFG, UBX_CFG_VALGET, payload)


def valset_request(settings: list[tuple[ConfigKey, int | bool]], layers: list[str]) -> bytes:
    layer_bits = 0
    for layer in layers:
        layer_bits |= VALSET_LAYER_BITS[layer]
    payload = struct.pack("<BBH", 0, layer_bits, 0)
    for key, value in settings:
        payload += struct.pack("<I", key.key_id)
        payload += encode_value(key, value)
    return ubx_frame(UBX_CFG, UBX_CFG_VALSET, payload)


def timepulse_settings(
    period_us: int,
    length_us: int,
    timegrid: str,
    enable: bool,
    sync_gnss: bool,
    use_locked: bool,
    align_to_tow: bool,
    rising_edge: bool,
) -> list[tuple[ConfigKey, int | bool]]:
    if period_us <= 0:
        raise ValueError("--period-us must be positive")
    if length_us <= 0 or length_us >= period_us:
        raise ValueError("--length-us must be positive and less than --period-us")
    return [
        (TP_KEYS["CFG-TP-PULSE_DEF"], 0),
        (TP_KEYS["CFG-TP-PULSE_LENGTH_DEF"], 1),
        (TP_KEYS["CFG-TP-PERIOD_TP1"], period_us),
        (TP_KEYS["CFG-TP-PERIOD_LOCK_TP1"], period_us),
        (TP_KEYS["CFG-TP-LEN_TP1"], length_us),
        (TP_KEYS["CFG-TP-LEN_LOCK_TP1"], length_us),
        (TP_KEYS["CFG-TP-TP1_ENA"], enable),
        (TP_KEYS["CFG-TP-SYNC_GNSS_TP1"], sync_gnss),
        (TP_KEYS["CFG-TP-USE_LOCKED_TP1"], use_locked),
        (TP_KEYS["CFG-TP-ALIGN_TO_TOW_TP1"], align_to_tow),
        (TP_KEYS["CFG-TP-POL_TP1"], rising_edge),
        (TP_KEYS["CFG-TP-TIMEGRID_TP1"], TIMEGRID_VALUES[timegrid]),
    ]


def extract_ubx_frames(data: bytes) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    idx = 0
    while True:
        start = data.find(SYNC, idx)
        if start < 0 or start + 8 > len(data):
            return frames
        if start + 6 > len(data):
            return frames
        length = struct.unpack_from("<H", data, start + 4)[0]
        end = start + 6 + length + 2
        if end > len(data):
            return frames
        raw = data[start:end]
        valid = validate_frame(raw)
        message_class = raw[2]
        message_id = raw[3]
        payload = raw[6:-2]
        frames.append(
            {
                "offset": start,
                "class": message_class,
                "id": message_id,
                "length": length,
                "checksum_valid": valid,
                "frame_hex": raw.hex(),
                "payload": payload,
            }
        )
        idx = end


def parse_frame(frame: dict[str, Any]) -> dict[str, Any]:
    payload = frame.pop("payload")
    row = dict(frame)
    if row["class"] == UBX_ACK and row["id"] in (UBX_ACK_ACK, UBX_ACK_NAK):
        row["message"] = "UBX-ACK-ACK" if row["id"] == UBX_ACK_ACK else "UBX-ACK-NAK"
        if len(payload) >= 2:
            row["ack_class"] = payload[0]
            row["ack_id"] = payload[1]
        return row
    if row["class"] != UBX_CFG or row["id"] != UBX_CFG_VALGET:
        row["message"] = f"UBX-0x{row['class']:02x}-0x{row['id']:02x}"
        return row
    row["message"] = "UBX-CFG-VALGET"
    if len(payload) < 4:
        row["parse_error"] = "payload_too_short"
        return row
    row["version"] = payload[0]
    row["layer"] = payload[1]
    row["position"] = struct.unpack_from("<H", payload, 2)[0]
    items: list[dict[str, Any]] = []
    offset = 4
    while offset < len(payload):
        if offset + 4 > len(payload):
            row["parse_error"] = "truncated_key"
            break
        key_id = struct.unpack_from("<I", payload, offset)[0]
        offset += 4
        try:
            size = storage_size_from_key_id(key_id)
        except ValueError as exc:
            row["parse_error"] = str(exc)
            break
        if offset + size > len(payload):
            row["parse_error"] = "truncated_value"
            break
        raw_value = payload[offset : offset + size]
        offset += size
        key = KEYS_BY_ID.get(key_id)
        items.append(
            {
                "name": key.name if key else f"0x{key_id:08x}",
                "key_id": f"0x{key_id:08x}",
                "type": key.value_type if key else f"size{size}",
                "value": decode_value(key_id, raw_value),
                "raw_value_hex": raw_value.hex(),
            }
        )
    row["items"] = items
    return row


def analyze_timepulse_items(items: list[dict[str, Any]]) -> dict[str, Any]:
    values = {
        str(item.get("name")): item.get("value")
        for item in items
        if isinstance(item, dict)
    }
    blockers: list[str] = []
    tp1_enabled = values.get("CFG-TP-TP1_ENA") is True
    unlocked_len_us = values.get("CFG-TP-LEN_TP1")
    locked_len_us = values.get("CFG-TP-LEN_LOCK_TP1")
    use_locked = values.get("CFG-TP-USE_LOCKED_TP1") is True
    if not tp1_enabled:
        blockers.append("gnss_timepulse_tp1_disabled")
    if unlocked_len_us == 0 and use_locked:
        blockers.append("gnss_timepulse_unlocked_pulse_length_zero")
    return {
        "tp1_enabled": tp1_enabled,
        "period_us": values.get("CFG-TP-PERIOD_TP1"),
        "period_lock_us": values.get("CFG-TP-PERIOD_LOCK_TP1"),
        "length_us": unlocked_len_us,
        "length_lock_us": locked_len_us,
        "use_locked_parameters_when_valid": use_locked,
        "sync_to_gnss_when_valid": values.get("CFG-TP-SYNC_GNSS_TP1") is True,
        "align_to_tow": values.get("CFG-TP-ALIGN_TO_TOW_TP1") is True,
        "rising_edge": values.get("CFG-TP-POL_TP1") is True,
        "timegrid": values.get("CFG-TP-TIMEGRID_TP1"),
        "pps_possible_without_gnss_lock": (
            tp1_enabled
            and isinstance(unlocked_len_us, int)
            and isinstance(values.get("CFG-TP-PERIOD_TP1"), int)
            and 0 < unlocked_len_us < values["CFG-TP-PERIOD_TP1"]
        ),
        "pps_possible_with_gnss_lock": (
            tp1_enabled
            and isinstance(locked_len_us, int)
            and isinstance(values.get("CFG-TP-PERIOD_LOCK_TP1"), int)
            and 0 < locked_len_us < values["CFG-TP-PERIOD_LOCK_TP1"]
        ),
        "blockers": blockers,
    }


def json_setting(key: ConfigKey, value: int | bool) -> dict[str, Any]:
    return {
        "name": key.name,
        "key_id": f"0x{key.key_id:08x}",
        "type": key.value_type,
        "value": value,
        "unit": key.unit,
        "description": key.description,
    }


def plan(args: argparse.Namespace) -> dict[str, Any]:
    keys = list(TP_KEYS.values())
    settings = timepulse_settings(
        period_us=args.period_us,
        length_us=args.length_us,
        timegrid=args.timegrid,
        enable=not args.disable_tp1,
        sync_gnss=not args.disable_sync_gnss,
        use_locked=not args.disable_use_locked,
        align_to_tow=not args.disable_align_to_tow,
        rising_edge=not args.falling_edge,
    )
    valget = valget_request(keys, args.layer)
    valset = valset_request(settings, args.set_layers.split(","))
    return {
        "event": "fieldmesh_gnss_timepulse_plan",
        "ok": True,
        "receiver_family": "u-blox M10 / MAX-M10S",
        "writes_hardware": False,
        "live_apply_authorization_required": True,
        "valget_layer": args.layer,
        "valset_layers": args.set_layers.split(","),
        "timepulse_goal": {
            "tp1_enabled": not args.disable_tp1,
            "period_us": args.period_us,
            "length_us": args.length_us,
            "frequency_hz": 1_000_000.0 / args.period_us,
            "duty_percent": (args.length_us / args.period_us) * 100.0,
            "timegrid": args.timegrid,
            "rising_edge": not args.falling_edge,
            "sync_to_gnss_when_valid": not args.disable_sync_gnss,
            "use_locked_parameters_when_valid": not args.disable_use_locked,
            "align_to_tow": not args.disable_align_to_tow,
        },
        "settings": [json_setting(key, value) for key, value in settings],
        "valget_frame_hex": valget.hex(),
        "valset_frame_hex": valset.hex(),
        "valget_checksum_valid": validate_frame(valget),
        "valset_checksum_valid": validate_frame(valset),
        "safety": {
            "default_set_layers": "ram",
            "persistent_layers": [
                layer for layer in args.set_layers.split(",") if layer in ("bbr", "flash")
            ],
            "live_write_policy": (
                "Do not write valset_frame_hex to a receiver unless a separate "
                "operator-approved live runner is invoked."
            ),
        },
        "source_notes": [
            "MAX-M10S TIMEPULSE is controlled by CFG-TP-* configuration items.",
            "UBX-CFG-VALGET polls key IDs; UBX-CFG-VALSET writes key-value pairs.",
        ],
    }


def parse_capture(args: argparse.Namespace) -> dict[str, Any]:
    data = Path(args.capture).read_bytes()
    frames = [parse_frame(frame) for frame in extract_ubx_frames(data)]
    tp_items = [
        item
        for frame in frames
        for item in frame.get("items", [])
        if isinstance(item, dict) and item.get("name", "").startswith("CFG-TP-")
    ]
    return {
        "event": "fieldmesh_gnss_timepulse_parse",
        "ok": bool(frames),
        "capture": str(args.capture),
        "frame_count": len(frames),
        "tp_item_count": len(tp_items),
        "tp_items": tp_items,
        "timepulse_analysis": analyze_timepulse_items(tp_items),
        "frames": frames,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    plan_parser = sub.add_parser("plan", help="Emit non-live UBX TIMEPULSE frames")
    plan_parser.add_argument("--period-us", type=int, default=1_000_000)
    plan_parser.add_argument("--length-us", type=int, default=100_000)
    plan_parser.add_argument("--timegrid", choices=sorted(TIMEGRID_VALUES), default="gps")
    plan_parser.add_argument("--layer", choices=sorted(VALGET_LAYERS), default="ram")
    plan_parser.add_argument("--set-layers", default="ram")
    plan_parser.add_argument("--disable-tp1", action="store_true")
    plan_parser.add_argument("--disable-sync-gnss", action="store_true")
    plan_parser.add_argument("--disable-use-locked", action="store_true")
    plan_parser.add_argument("--disable-align-to-tow", action="store_true")
    plan_parser.add_argument("--falling-edge", action="store_true")

    parse_parser = sub.add_parser("parse", help="Parse UBX frames captured from a receiver")
    parse_parser.add_argument("--capture", required=True, type=Path)

    args = parser.parse_args()
    if getattr(args, "set_layers", None):
        layers = args.set_layers.split(",")
        unknown = [layer for layer in layers if layer not in VALSET_LAYER_BITS]
        if unknown:
            parser.error(f"--set-layers contains unsupported layers: {','.join(unknown)}")
    return args


def main() -> int:
    args = parse_args()
    try:
        if args.command == "plan":
            result = plan(args)
        else:
            result = parse_capture(args)
    except (ValueError, OSError, binascii.Error) as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
