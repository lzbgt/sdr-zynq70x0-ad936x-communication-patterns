#!/usr/bin/env python3
"""Normalize FieldMesh RF hardware counter progression evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REQUIRED_DELTAS = {
    "fw_dma_tx_parser_packets_delta": 1,
    "fw_dma_tx_parser_bytes_delta": 1,
    "fw_dma_ingress_packets_delta": 1,
    "fw_dma_ingress_bytes_delta": 1,
    "fw_dma_ingress_desc_publishes_delta": 1,
    "fw_dma_mac_ticks_delta": 1,
}
SNAPSHOT_COUNTERS = {
    "mac_ticks": "fw_dma_mac_ticks",
    "ingress_packets": "fw_dma_ingress_packets",
    "egress_packets": "fw_dma_egress_packets",
    "bram_errors": "fw_dma_bram_errors",
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_int(report: dict[str, Any], key: str, minimum: int | None = None) -> int:
    value = report.get(key)
    if not isinstance(value, int):
        raise SystemExit(f"RF hardware progression report missing integer {key}")
    if minimum is not None and value < minimum:
        raise SystemExit(f"RF hardware progression {key} must be >= {minimum}")
    return value


def require_bool(report: dict[str, Any], key: str, expected: bool) -> None:
    if report.get(key) is not expected:
        raise SystemExit(f"RF hardware progression {key} must be {str(expected).lower()}")


def snapshot(report: dict[str, Any], name: str, prefix: str) -> dict[str, int]:
    before = require_int(report, f"{prefix}_before")
    after = require_int(report, f"{prefix}_after")
    delta_key = f"{prefix}_delta"
    delta = require_int(report, delta_key) if delta_key in report else after - before
    if after < before:
        raise SystemExit(f"RF hardware progression {name} counter regressed")
    if delta != after - before:
        raise SystemExit(f"RF hardware progression {name} delta does not match before/after")
    return {
        "before": before,
        "after": after,
        "delta": delta,
    }


def build(report_path: Path) -> dict[str, Any]:
    report = load_json(report_path)
    if report.get("event") != "fieldmesh_board_rf_phy_bind_gate" or report.get("ok") is not True:
        raise SystemExit("RF hardware progression source must be a successful bind-gate report")
    require_bool(report, "fw_dma_status_reads_hardware", True)
    require_bool(report, "fw_dma_status_writes_hardware", False)
    require_bool(report, "fw_dma_counter_progression_ok", True)
    require_bool(report, "requires_c_modem_service_rate", True)
    if report.get("rf_phy_tx_rx") not in (0, False):
        raise SystemExit("RF hardware progression source must not claim RF PHY TX/RX")
    if report.get("production_ready") not in (0, False):
        raise SystemExit("RF hardware progression source must not claim production readiness")
    if report.get("production_blocker") != "real_rf_phy_tx_rx_not_verified":
        raise SystemExit("RF hardware progression source must still block on measured RF PHY TX/RX")

    deltas = {
        key: require_int(report, key, minimum)
        for key, minimum in REQUIRED_DELTAS.items()
    }
    drop_error_delta = require_int(report, "fw_dma_drop_error_delta")
    if drop_error_delta != 0:
        raise SystemExit("RF hardware progression drop/error delta must be zero")

    snapshots = {
        name: snapshot(report, name, prefix)
        for name, prefix in SNAPSHOT_COUNTERS.items()
    }
    if snapshots["mac_ticks"]["delta"] != deltas["fw_dma_mac_ticks_delta"]:
        raise SystemExit("RF hardware progression MAC tick snapshot does not match required delta")
    if snapshots["ingress_packets"]["delta"] != deltas["fw_dma_ingress_packets_delta"]:
        raise SystemExit("RF hardware progression ingress snapshot does not match required delta")

    service_latency_last = require_int(report, "fw_dma_service_latency_last_cycles_after", 1)
    service_latency_max = require_int(report, "fw_dma_service_latency_max_cycles_after", service_latency_last)
    service_latency_budget = require_int(report, "fw_dma_service_latency_budget_cycles", 1)
    require_bool(report, "fw_dma_service_latency_within_budget", True)
    require_bool(report, "fw_dma_service_latency_hardware_budget_programmed", True)
    require_bool(report, "fw_dma_service_latency_budget_ok_after", True)
    require_bool(report, "fw_dma_service_latency_over_budget_before", False)
    require_bool(report, "fw_dma_service_latency_over_budget_after", False)
    over_budget_delta = require_int(report, "fw_dma_service_latency_over_budget_count_delta", 0)
    if over_budget_delta != 0:
        raise SystemExit("RF hardware progression service-latency over-budget counter advanced")
    if service_latency_last > service_latency_budget:
        raise SystemExit("RF hardware progression service-latency last_cycles exceeded budget")
    if service_latency_max > service_latency_budget:
        raise SystemExit("RF hardware progression service-latency max_cycles exceeded budget")
    service_latency_accum = snapshot(
        report,
        "service_latency_accum_cycles",
        "fw_dma_service_latency_accum_cycles",
    )
    if service_latency_accum["delta"] < service_latency_last:
        raise SystemExit(
            "RF hardware progression service-latency accumulator did not cover the last service interval"
        )

    tx_polls = require_int(report, "dma_smoke_tx_polls", 1)
    rx_polls = require_int(report, "dma_smoke_rx_polls", 0)
    modem_rate = report.get("modem_benchmark_decode_frame_kbps")
    if not isinstance(modem_rate, (int, float)) or modem_rate < 100:
        raise SystemExit("RF hardware progression C modem decode service rate is below threshold")

    return {
        "event": "fieldmesh_rf_hardware_progression_evidence",
        "ok": True,
        "source_report": str(report_path.resolve(strict=False)),
        "source_event": report.get("event"),
        "reads_hardware": True,
        "writes_hardware": False,
        "c_fpga_native_counter_progression": True,
        "counter_progression_ok": True,
        "required_counter_deltas": deltas,
        "counter_snapshots": snapshots,
        "drop_error_delta": drop_error_delta,
        "submit_latency_evidence": {
            "dma_smoke_tx_polls": tx_polls,
            "dma_smoke_rx_polls": rx_polls,
        },
        "service_latency_evidence": {
            "source": "firmware_dma_endpoint",
            "last_cycles": service_latency_last,
            "max_cycles": service_latency_max,
            "budget_cycles": service_latency_budget,
            "within_budget": True,
            "hardware_budget_programmed": True,
            "hardware_budget_ok": True,
            "over_budget_before": False,
            "over_budget_after": False,
            "over_budget_count_delta": over_budget_delta,
            "accum_cycles": service_latency_accum,
        },
        "c_modem_service_rate": {
            "required": True,
            "decode_frame_kbps": modem_rate,
        },
        "no_rf_phy_tx_rx_claim": True,
        "no_production_ready_claim": True,
        "production_blocker": report.get("production_blocker"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-bind-gate-report", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    evidence = build(args.rf_bind_gate_report)
    text = json.dumps(
        evidence,
        indent=2 if args.pretty else None,
        sort_keys=True,
        separators=None if args.pretty else (",", ":"),
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
