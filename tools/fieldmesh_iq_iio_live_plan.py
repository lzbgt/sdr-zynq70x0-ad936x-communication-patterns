#!/usr/bin/env python3
"""Plan a guarded over-air AD936x IIO IQ burst test without executing it."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


MIN_FIXTURE_ATTENUATION_DB = 30.0


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_guard(args: argparse.Namespace, iq_report: dict[str, Any]) -> None:
    if not args.authorized_rf_path and not args.conducted_or_shielded:
        raise SystemExit("--authorized-rf-path is required")
    if not args.legal_frequency_profile:
        raise SystemExit("--legal-frequency-profile is required")
    if not args.tx_enable_guard:
        raise SystemExit("--tx-enable-guard is required")
    if not args.rx_first:
        raise SystemExit("--rx-first is required")
    if args.conducted_or_shielded and args.fixture_attenuation_db < MIN_FIXTURE_ATTENUATION_DB:
        raise SystemExit(
            f"--fixture-attenuation-db must be >= {MIN_FIXTURE_ATTENUATION_DB:g} dB"
        )
    fixture = iq_report.get("rf_fixture", {})
    if fixture.get("authorized_rf_path") is not True and fixture.get("conducted_or_shielded") is not True:
        raise SystemExit("IQ burst smoke report is not marked for an authorized RF path")
    if fixture.get("conducted_or_shielded") is True and float(fixture.get("fixture_attenuation_db", 0.0)) < MIN_FIXTURE_ATTENUATION_DB:
        raise SystemExit("IQ burst smoke report lab attenuation is too low")


def require_rf_binding(binding: dict[str, Any]) -> None:
    if binding.get("event") != "fieldmesh_rf_binding_plan" or binding.get("ok") is not True:
        raise SystemExit("RF binding plan is not successful")
    management = binding.get("management_plane", {})
    radio = binding.get("radio_data_plane", {})
    if management.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("RF binding plan must not use inter-board IP routing")
    if radio.get("opens_iio_buffers") is not False or radio.get("starts_rf_tx") is not False:
        raise SystemExit("RF binding plan must be read-only")


def board_iio(binding: dict[str, Any], board: str) -> dict[str, Any]:
    try:
        selected = binding[board]["iio"]["selected_rf_iio"]
    except KeyError as exc:
        raise SystemExit(f"RF binding plan is missing {board} selected RF IIO data") from exc
    if selected.get("rx_name") != "cf-ad9361-lpc":
        raise SystemExit(f"{board}: expected RF RX cf-ad9361-lpc, got {selected}")
    if selected.get("tx_name") != "cf-ad9361-dds-core-lpc":
        raise SystemExit(f"{board}: expected RF TX cf-ad9361-dds-core-lpc, got {selected}")
    return selected


def command_plan(
    tx_board: str,
    rx_board: str,
    tx_iio: dict[str, Any],
    rx_iio: dict[str, Any],
    iq_report: dict[str, Any],
) -> list[dict[str, Any]]:
    fixture = iq_report["rf_fixture"]
    encoding = iq_report["encoding"]
    return [
        {
            "step": 1,
            "name": "configure_rx_phy",
            "board": rx_board,
            "device": "ad9361-phy",
            "center_frequency_hz": fixture["center_frequency_hz"],
            "sample_rate_hz": fixture["sample_rate_hz"],
            "rf_bandwidth_hz": fixture["rf_bandwidth_hz"],
        },
        {
            "step": 2,
            "name": "configure_tx_phy",
            "board": tx_board,
            "device": "ad9361-phy",
            "center_frequency_hz": fixture["center_frequency_hz"],
            "sample_rate_hz": fixture["sample_rate_hz"],
            "rf_bandwidth_hz": fixture["rf_bandwidth_hz"],
        },
        {
            "step": 3,
            "name": "arm_rx_buffer",
            "board": rx_board,
            "device": rx_iio["rx_name"],
            "iio_device": rx_iio["rx_device"],
            "iq_samples": encoding["iq_samples"],
            "sample_format": encoding["iq_sample_format"],
        },
        {
            "step": 4,
            "name": "load_tx_buffer",
            "board": tx_board,
            "device": tx_iio["tx_name"],
            "iio_device": tx_iio["tx_device"],
            "iq_file": encoding["iq_file"],
            "iq_samples": encoding["iq_samples"],
            "sample_format": encoding["iq_sample_format"],
        },
        {
            "step": 5,
            "name": "explicit_tx_enable_then_capture",
            "board": tx_board,
            "requires": [
                "authorized_rf_path_evidence",
                "legal_frequency_profile",
                "operator_tx_enable_guard",
                "rx_first",
            ],
        },
        {
            "step": 6,
            "name": "decode_rx_capture",
            "board": rx_board,
            "expected_frame_crc": iq_report["frame"]["frame_crc"],
            "expected_transport_seq": iq_report["frame"].get("transport_seq"),
        },
    ]


def build_plan(args: argparse.Namespace) -> dict[str, Any]:
    binding = load_json(args.rf_binding_plan)
    iq_report = load_json(args.iq_burst_report)
    require_rf_binding(binding)
    require_guard(args, iq_report)

    if args.tx_board == args.rx_board:
        raise SystemExit("--tx-board and --rx-board must be different")
    tx_iio = board_iio(binding, args.tx_board)
    rx_iio = board_iio(binding, args.rx_board)

    safety = {
        "authorized_rf_path": True,
        "conducted_or_shielded": bool(args.conducted_or_shielded),
        "fixture_attenuation_db": args.fixture_attenuation_db,
        "legal_frequency_profile": True,
        "tx_enable_guard": True,
        "rx_first": True,
        "executes_commands": False,
        "opens_iio_buffers": False,
        "starts_rf_tx": False,
        "writes_hardware": False,
        "live_rf_allowed_by_this_tool": False,
    }
    return {
        "event": "fieldmesh_iq_iio_live_plan",
        "ok": True,
        "tx_board": args.tx_board,
        "rx_board": args.rx_board,
        "management_plane": binding["management_plane"],
        "radio_data_plane": {
            "uses_inter_board_ip_routing": False,
            "path": "FieldMesh IQ burst -> TX AD936x IIO buffer -> authorized over-air RF path -> RX AD936x IIO buffer -> FieldMesh decoder",
            "tx_iio": tx_iio,
            "rx_iio": rx_iio,
        },
        "iq_burst": {
            "report": str(args.iq_burst_report),
            "iq_file": iq_report["encoding"]["iq_file"],
            "iq_samples": iq_report["encoding"]["iq_samples"],
            "encoding": iq_report["encoding"]["name"],
            "frame_crc": iq_report["frame"]["frame_crc"],
            "frame_format": iq_report["frame"].get("format"),
            "traffic_class": iq_report["frame"].get("traffic_class"),
            "mode": iq_report["frame"].get("mode"),
        },
        "safety": safety,
        "command_plan": command_plan(args.tx_board, args.rx_board, tx_iio, rx_iio, iq_report),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-binding-plan", type=Path, required=True)
    parser.add_argument("--iq-burst-report", type=Path, required=True)
    parser.add_argument("--tx-board", choices=("z203", "z103"), default="z203")
    parser.add_argument("--rx-board", choices=("z203", "z103"), default="z103")
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--authorized-rf-path", action="store_true")
    parser.add_argument("--conducted-or-shielded", action="store_true")
    parser.add_argument("--legal-frequency-profile", action="store_true")
    parser.add_argument("--tx-enable-guard", action="store_true")
    parser.add_argument("--rx-first", action="store_true")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = build_plan(args)
    text = (
        json.dumps(plan, indent=2, sort_keys=True)
        if args.pretty
        else json.dumps(plan, sort_keys=True, separators=(",", ":"))
    )
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
