#!/usr/bin/env python3
"""Summarize two-board FieldMesh live GNSS preflight captures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def latest_reporter_status(facts: dict[str, Any]) -> dict[str, Any] | None:
    latest = None
    for line in facts.get("gnss_log_tail") or []:
        if not isinstance(line, str) or not line.strip().startswith("{"):
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if row.get("event") == "fieldmesh_gnss_nmea_status":
            latest = row
    return latest if isinstance(latest, dict) else None


def split_csv(value: Any) -> list[str]:
    return [item for item in str(value or "").split(",") if item]


RECEIVER_HEALTH_BLOCKERS = {
    "gnss_receiver_io_overvoltage",
    "gnss_receiver_warning",
}


def classify(out_dir: Path, label: str, require_gnss_pps: bool) -> dict[str, Any]:
    facts = read_json(out_dir / f"{label}_facts.txt.json")
    rtls = read_json(out_dir / f"{label}_rtls_position.json")
    blockers: list[str] = []
    configured_device = str(facts.get("gnss_nmea_device") or "")
    configured_baud = str(facts.get("gnss_nmea_baud") or "")
    configured_pps_lock = str(facts.get("gnss_pps_lock") or "")
    reporter_status = latest_reporter_status(facts)
    serial_devices = split_csv(facts.get("serial_devices"))
    pps_devices = split_csv(facts.get("pps_devices"))
    pps_sysfs_devices = split_csv(facts.get("pps_sysfs_devices"))
    pps_device_present = bool(pps_devices or pps_sysfs_devices)
    pps_lock_configured = configured_pps_lock in ("1", "true", "yes", "on")

    if not configured_device:
        blockers.append("no_gnss_nmea_device_configured")
    elif facts.get("gnss_nmea_device_exists") != "1":
        blockers.append("gnss_nmea_device_missing")
    if not facts.get("daemon_pid"):
        blockers.append("fieldmesh_daemon_not_running")
    if configured_device and facts.get("gnss_nmea_device_exists") == "1" and not facts.get("gnss_pid"):
        blockers.append("gnss_reporter_not_running")

    daemon_gnss_position_present = (
        rtls.get("ok") is True
        and rtls.get("position_source") == "gps_pps_fused"
    )
    has_fix = (
        rtls.get("ok") is True
        and rtls.get("position_source") == "gps_pps_fused"
        and rtls.get("has_gnss_position") in (1, True)
        and rtls.get("live_gnss_reporter") in (1, True)
        and isinstance(rtls.get("measured_age_ms"), int)
        and rtls.get("measured_age_ms") <= 15000
    )
    if not has_fix:
        if configured_device and facts.get("gnss_nmea_device_exists") == "1" and facts.get("gnss_pid"):
            status_blockers = []
            if reporter_status is not None:
                status_blockers = [
                    str(item)
                    for item in reporter_status.get("blockers", [])
                    if isinstance(item, str) and item
                ]
            blockers.extend(status_blockers or ["gnss_receiver_no_fix"])
        else:
            blockers.append("no_live_gnss_position_in_daemon")

    service_backed = (
        has_fix
        and bool(configured_device)
        and facts.get("gnss_nmea_device_exists") == "1"
        and bool(facts.get("gnss_pid"))
    )
    if daemon_gnss_position_present and not service_backed:
        blockers.append("gnss_position_not_backed_by_live_init_service")

    if require_gnss_pps:
        if not pps_device_present:
            blockers.append("gnss_pps_device_missing")
        elif not pps_lock_configured:
            blockers.append("gnss_pps_lock_not_configured")

    blockers = sorted(set(blockers))
    receiver_health_blockers = [
        blocker for blocker in blockers if blocker in RECEIVER_HEALTH_BLOCKERS
    ]
    return {
        "label": label,
        "board_ip": facts.get("board_ip"),
        "hostname": facts.get("hostname"),
        "device_eui": facts.get("device_eui"),
        "gnss_nmea_device": configured_device,
        "gnss_nmea_baud": configured_baud,
        "gnss_pps_lock": configured_pps_lock,
        "gnss_nmea_device_exists": facts.get("gnss_nmea_device_exists") == "1",
        "gnss_pps_device_present": pps_device_present,
        "gnss_pps_ready": pps_device_present and pps_lock_configured,
        "gnss_reporter_running": bool(facts.get("gnss_pid")),
        "daemon_running": bool(facts.get("daemon_pid")),
        "serial_devices": serial_devices,
        "pps_devices": pps_devices,
        "pps_sysfs_devices": pps_sysfs_devices,
        "position_source": rtls.get("position_source"),
        "has_gnss_position": rtls.get("has_gnss_position"),
        "live_gnss_reporter": rtls.get("live_gnss_reporter"),
        "measured_age_ms": rtls.get("measured_age_ms"),
        "gnss_nmea_status": reporter_status,
        "daemon_gnss_position_present": daemon_gnss_position_present,
        "gnss_position_backed_by_live_init_service": service_backed,
        "gnss_receiver_health_ready": not receiver_health_blockers,
        "gnss_receiver_health_blockers": receiver_health_blockers,
        "gnss_live_ready": not blockers,
        "blockers": blockers,
        "facts_path": str(out_dir / f"{label}_facts.txt.json"),
        "rtls_position_path": str(out_dir / f"{label}_rtls_position.json"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--require-gnss-fix", action="store_true")
    parser.add_argument("--require-gnss-pps", action="store_true")
    parser.add_argument("--require-gnss-receiver-health", action="store_true")
    args = parser.parse_args()

    boards = [
        classify(args.out_dir, "z203", args.require_gnss_pps),
        classify(args.out_dir, "z103", args.require_gnss_pps),
    ]
    ready = all(board["gnss_live_ready"] for board in boards)
    pps_ready = all(board["gnss_pps_ready"] for board in boards)
    receiver_health_ready = all(
        board["gnss_receiver_health_ready"] for board in boards
    )
    ok = True
    if args.require_gnss_fix:
        ok = ok and ready
    if args.require_gnss_pps:
        ok = ok and pps_ready
    if args.require_gnss_receiver_health:
        ok = ok and receiver_health_ready
    summary: dict[str, Any] = {
        "event": "fieldmesh_two_board_gnss_live_preflight",
        "ok": ok,
        "gnss_live_ready": ready,
        "gnss_pps_ready": pps_ready,
        "gnss_receiver_health_ready": receiver_health_ready,
        "require_gnss_fix": args.require_gnss_fix,
        "require_gnss_pps": args.require_gnss_pps,
        "require_gnss_receiver_health": args.require_gnss_receiver_health,
        "boards": boards,
        "capture_dir": str(args.out_dir),
    }
    production_blockers: list[str] = []
    if not ready:
        production_blockers.append("gnss_live_fix_not_ready")
    if not pps_ready:
        production_blockers.append("gnss_pps_not_ready")
    if not receiver_health_ready:
        production_blockers.append("gnss_receiver_health_not_ready")
    if production_blockers:
        summary["production_blocker"] = ",".join(production_blockers)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
