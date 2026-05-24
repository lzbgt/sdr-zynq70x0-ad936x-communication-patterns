#!/usr/bin/env python3
"""Convert FieldMesh production-readiness blockers into next actions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_report(path: Path) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: expected JSON object")
    if report.get("event") != "fieldmesh_system_production_readiness":
        raise SystemExit(
            f"{path}: expected fieldmesh_system_production_readiness, "
            f"got {report.get('event')!r}"
        )
    return report


ACTION_RULES: tuple[tuple[tuple[str, ...], dict[str, Any]], ...] = (
    (
        ("gnss_receiver_health_not_ready", "gnss_receiver_io_overvoltage"),
        {
            "action_id": "fix_gnss_receiver_io_overvoltage",
            "domain": "gnss_receiver_health",
            "priority": 10,
            "requires_physical_access": True,
            "requires_rf_tx": False,
            "requires_receiver_config_write": False,
            "summary": "Investigate GNSS receiver V_IO overvoltage before using GNSS evidence.",
            "verification": "Rerun GNSS live preflight with REQUIRE_GNSS_RECEIVER_HEALTH=1 and confirm receiver-health blockers clear.",
        },
    ),
    (
        (
            "gnss_no_satellites_visible",
            "gnss_gga_quality_no_fix",
            "gnss_rmc_status_void",
            "gnss_gsa_fix_type_no_fix",
            "gnss_receiver_no_fix",
            "gnss_live_fix_not_ready",
        ),
        {
            "action_id": "obtain_live_gnss_fix",
            "domain": "gnss_position",
            "priority": 20,
            "requires_physical_access": True,
            "requires_rf_tx": False,
            "requires_receiver_config_write": False,
            "summary": "Move both boards to sky view or a known GNSS signal source until live GNSS fixes reach the daemon.",
            "verification": "Rerun GNSS live preflight with REQUIRE_GNSS_FIX=1 and confirm both boards report fresh reporter-origin positions.",
        },
    ),
    (
        (
            "gnss_pps_no_assert_activity",
            "gnss_pps_gpio_low_no_activity",
            "gnss_pps_gpio_high_no_activity",
            "gnss_timepulse_unlocked_pulse_length_zero",
            "gnss_pps_not_ready",
        ),
        {
            "action_id": "prove_gnss_pps_activity",
            "domain": "gnss_timing",
            "priority": 30,
            "requires_physical_access": True,
            "requires_rf_tx": False,
            "requires_receiver_config_write": False,
            "summary": "Prove PPS activity after GNSS time lock; use the RAM-only TIMEPULSE diagnostic only as an explicit service action.",
            "verification": "Rerun system readiness or GNSS preflight with REQUIRE_GNSS_PPS=1 and confirm PPS assert sequence increments.",
        },
    ),
    (
        (
            "native_ip_iperf_not_production_ready",
            "board_to_board_preflight_failed",
            "host_pc_preflight_failed",
            "real_rf_phy_tx_rx_not_verified",
        ),
        {
            "action_id": "collect_paired_real_rf_iperf",
            "domain": "native_ip",
            "priority": 40,
            "requires_physical_access": True,
            "requires_rf_tx": True,
            "requires_receiver_config_write": False,
            "summary": "Run paired board-to-board and host-PC-transparent iperf over verified real over-air RF.",
            "verification": "Run the native-IP iperf production sequence and confirm paired real-RF TCP/UDP metrics are production_ready=true.",
        },
    ),
    (
        (
            "real_rf_production_gate_missing",
            "real_rf_production_sequence_missing",
            "real_rf_tx_backend_readback_not_proven",
            "real_rf_evidence_manifest_not_verified",
            "real_rf_not_production_ready",
            "measured_rf_phy_tx_rx_not_verified",
        ),
        {
            "action_id": "collect_real_rf_production_gate",
            "domain": "rf_phy",
            "priority": 50,
            "requires_physical_access": True,
            "requires_rf_tx": True,
            "requires_receiver_config_write": False,
            "summary": "Collect authorized over-air RF production evidence with exact frame recovery and correlated app evidence.",
            "verification": "Run the over-air RF production sequence with production RF path evidence and confirm the real-RF gate is production_ready=true.",
        },
    ),
)


def blocker_texts(report: dict[str, Any]) -> list[str]:
    blockers = report.get("blockers", [])
    if not isinstance(blockers, list):
        return []
    return [item for item in blockers if isinstance(item, str) and item]


def action_matches(blockers: list[str], tokens: tuple[str, ...]) -> list[str]:
    matches: list[str] = []
    for blocker in blockers:
        blocker_tail = blocker.rsplit(":", 1)[-1]
        for token in tokens:
            if blocker_tail == token or token in blocker:
                matches.append(blocker)
                break
    return sorted(set(matches))


def summarize(report: dict[str, Any]) -> dict[str, Any]:
    blockers = blocker_texts(report)
    actions: list[dict[str, Any]] = []
    for tokens, action in ACTION_RULES:
        matched = action_matches(blockers, tokens)
        if not matched:
            continue
        row = dict(action)
        row["matched_blockers"] = matched
        actions.append(row)

    known = {
        blocker
        for action in actions
        for blocker in action.get("matched_blockers", [])
        if isinstance(blocker, str)
    }
    unknown = sorted(set(blockers) - known)
    if unknown:
        actions.append(
            {
                "action_id": "inspect_unclassified_readiness_blockers",
                "domain": "readiness",
                "priority": 90,
                "requires_physical_access": False,
                "requires_rf_tx": False,
                "requires_receiver_config_write": False,
                "summary": "Inspect readiness blockers that do not yet have a specific action rule.",
                "verification": "Add or update the readiness action rule after root cause is understood.",
                "matched_blockers": unknown,
            }
        )

    actions.sort(key=lambda item: (int(item["priority"]), str(item["action_id"])))
    return {
        "event": "fieldmesh_system_readiness_actions",
        "ok": True,
        "production_ready": report.get("production_ready") is True,
        "action_required": bool(actions),
        "action_count": len(actions),
        "actions": actions,
        "source_report": str(report.get("source_report") or ""),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("readiness_report", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = load_report(args.readiness_report)
    report["source_report"] = str(args.readiness_report)
    summary = summarize(report)
    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
