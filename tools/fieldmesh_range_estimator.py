#!/usr/bin/env python3
"""Estimate FieldMesh sea-surface reliable range from horizon and link budget."""

from __future__ import annotations

import argparse
import json
import math
from typing import Any


def radio_horizon_km(tx_height_m: float, rx_height_m: float) -> float:
    return 4.12 * (math.sqrt(max(tx_height_m, 0.0)) + math.sqrt(max(rx_height_m, 0.0)))


def fspl_db(freq_mhz: float, distance_km: float) -> float:
    return 32.44 + 20.0 * math.log10(freq_mhz) + 20.0 * math.log10(distance_km)


def receiver_sensitivity_dbm(
    bandwidth_hz: float,
    noise_figure_db: float,
    required_snr_db: float,
    implementation_loss_db: float,
) -> float:
    return (
        -174.0
        + 10.0 * math.log10(bandwidth_hz)
        + noise_figure_db
        + required_snr_db
        + implementation_loss_db
    )


def budget_limited_range_km(
    freq_mhz: float,
    tx_power_dbm: float,
    tx_gain_dbi: float,
    rx_gain_dbi: float,
    losses_db: float,
    sensitivity_dbm: float,
    fade_margin_db: float,
) -> float:
    allowed_fspl = (
        tx_power_dbm
        + tx_gain_dbi
        + rx_gain_dbi
        - losses_db
        - fade_margin_db
        - sensitivity_dbm
    )
    exponent = (allowed_fspl - 32.44 - 20.0 * math.log10(freq_mhz)) / 20.0
    return 10.0**exponent


def estimate(args: argparse.Namespace) -> dict[str, Any]:
    sensitivity = receiver_sensitivity_dbm(
        args.bandwidth_hz,
        args.rx_nf_db,
        args.required_snr_db,
        args.implementation_loss_db,
    )
    budget_range = budget_limited_range_km(
        args.freq_mhz,
        args.tx_power_dbm,
        args.tx_gain_dbi,
        args.rx_gain_dbi,
        args.losses_db,
        sensitivity,
        args.fade_margin_db,
    )
    horizon = radio_horizon_km(args.tx_height_m, args.rx_height_m)
    reliable = min(budget_range, horizon)
    limiting = "radio_horizon" if horizon <= budget_range else "link_budget"
    margin_at_horizon = (
        args.tx_power_dbm
        + args.tx_gain_dbi
        + args.rx_gain_dbi
        - args.losses_db
        - fspl_db(args.freq_mhz, max(horizon, 0.001))
        - sensitivity
    )
    return {
        "event": "fieldmesh_maritime_range_estimate",
        "freq_mhz": args.freq_mhz,
        "bandwidth_hz": args.bandwidth_hz,
        "tx_height_m": args.tx_height_m,
        "rx_height_m": args.rx_height_m,
        "tx_power_dbm": args.tx_power_dbm,
        "tx_gain_dbi": args.tx_gain_dbi,
        "rx_gain_dbi": args.rx_gain_dbi,
        "losses_db": args.losses_db,
        "rx_nf_db": args.rx_nf_db,
        "required_snr_db": args.required_snr_db,
        "implementation_loss_db": args.implementation_loss_db,
        "fade_margin_db": args.fade_margin_db,
        "sensitivity_dbm": round(sensitivity, 2),
        "radio_horizon_km": round(horizon, 2),
        "budget_limited_range_km": round(budget_range, 2),
        "max_reliable_range_km": round(reliable, 2),
        "margin_at_horizon_db": round(margin_at_horizon - args.fade_margin_db, 2),
        "limiting_factor": limiting,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Estimate FieldMesh ship-to-ship reliable range over sea."
    )
    parser.add_argument("--freq-mhz", type=float, default=2400.0)
    parser.add_argument("--bandwidth-hz", type=float, default=1_000_000.0)
    parser.add_argument("--tx-power-dbm", type=float, default=30.0)
    parser.add_argument("--tx-gain-dbi", type=float, default=14.0)
    parser.add_argument("--rx-gain-dbi", type=float, default=14.0)
    parser.add_argument("--losses-db", type=float, default=4.0)
    parser.add_argument("--rx-nf-db", type=float, default=6.0)
    parser.add_argument("--required-snr-db", type=float, default=8.0)
    parser.add_argument("--implementation-loss-db", type=float, default=3.0)
    parser.add_argument("--fade-margin-db", type=float, default=18.0)
    parser.add_argument("--tx-height-m", type=float, default=10.0)
    parser.add_argument("--rx-height-m", type=float, default=10.0)
    parser.add_argument("--json", action="store_true", help="emit JSON only")
    args = parser.parse_args()

    result = estimate(args)
    if args.json:
        print(json.dumps(result, sort_keys=True))
        return 0

    print(json.dumps(result, indent=2, sort_keys=True))
    print(
        "\nReliable planning range is the lower of radio horizon and "
        "link-budget range after fade margin."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
