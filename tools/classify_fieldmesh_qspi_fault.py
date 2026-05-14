#!/usr/bin/env python3
"""Classify the current FieldMesh QSPI fault evidence.

This is a no-hardware-write gate. It consumes captured probe summaries and
turns the current Z203/Z103 QSPI state into a machine-checkable install/repair
policy so future tooling does not accidentally treat the Z203 QSPI failure as
an ordinary stale-runtime issue.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
Z203_CAPTURES = REPO_ROOT / "resources/variants/sdr-z203-z7020-2r2t/live-captures"
Z103_CAPTURES = REPO_ROOT / "resources/variants/sdr-z103-z7010-1r1t/live-captures"


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def latest_summary(root: Path, pattern: str) -> Path:
    matches = sorted(root.glob(pattern))
    if not matches:
        raise SystemExit(f"no evidence matched {root / pattern}")
    summary = matches[-1] / "summary.json"
    if not summary.is_file():
        raise SystemExit(f"latest evidence has no summary.json: {summary}")
    return summary


def bool_value(data: dict[str, Any], key: str) -> bool:
    return data.get(key) is True


def z203_pattern_failure(data: dict[str, Any]) -> dict[str, Any]:
    patterns = data.get("patterns")
    if not isinstance(patterns, list):
        patterns = []
    failed_patterns = [
        row.get("pattern_hex")
        for row in patterns
        if isinstance(row, dict) and row.get("write_readback_matches") is False
    ]
    passed_patterns = [
        row.get("pattern_hex")
        for row in patterns
        if isinstance(row, dict) and row.get("write_readback_matches") is True
    ]
    return {
        "event": data.get("event"),
        "path_behavior": "erase_clean_program_stuck_bits",
        "erase_readback_clean": bool_value(data, "all_erase_readbacks_clean"),
        "all_writes_match": bool_value(data, "all_writes_match"),
        "aggregate_unexpected_one_mask_hex": data.get("aggregate_unexpected_one_mask_hex"),
        "unexpected_one_masks_hex": data.get("unexpected_one_masks_hex", []),
        "failed_patterns": failed_patterns,
        "passed_patterns": passed_patterns,
        "fault_signature_matches_z203_0x44": (
            bool_value(data, "all_erase_readbacks_clean")
            and data.get("all_writes_match") is False
            and data.get("aggregate_unexpected_one_mask_hex") == "0x44"
            and "0x00" in failed_patterns
        ),
    }


def z203_linux_failure(data: dict[str, Any]) -> dict[str, Any]:
    write_compare = data.get("write_compare")
    if not isinstance(write_compare, dict):
        write_compare = data.get("after_compare")
    if not isinstance(write_compare, dict):
        write_compare = {}
    return {
        "event": data.get("event"),
        "write_readback_matches": bool_value(data, "write_readback_matches"),
        "rollback_erase_passed": bool_value(data, "rollback_erase_passed"),
        "dominant_unexpected_one_bit_mask_hex": write_compare.get(
            "dominant_unexpected_one_bit_mask_hex"
        )
        or data.get("dominant_unexpected_one_bit_mask_hex"),
        "linux_path_reproduces_fault": (
            data.get("write_readback_matches") is False
            and bool_value(data, "rollback_erase_passed")
        ),
    }


def z103_pattern_health(data: dict[str, Any]) -> dict[str, Any]:
    return {
        "event": data.get("event"),
        "scratch_precondition_passed": bool_value(data, "scratch_precondition_passed"),
        "all_erase_readbacks_clean": bool_value(data, "all_erase_readbacks_clean"),
        "all_writes_match": bool_value(data, "all_writes_match"),
        "all_rollbacks_clean": bool_value(data, "all_rollbacks_clean"),
        "healthy_reference_passed": (
            bool_value(data, "scratch_precondition_passed")
            and bool_value(data, "all_erase_readbacks_clean")
            and bool_value(data, "all_writes_match")
            and bool_value(data, "all_rollbacks_clean")
        ),
    }


def z203_integrity(data: dict[str, Any] | None) -> dict[str, Any]:
    if data is None:
        return {
            "present": False,
            "qspi_integrity_pass": False,
            "safe_z203_install_mode": "sd",
        }
    return {
        "present": True,
        "event": data.get("event"),
        "qspi_integrity_pass": bool_value(data, "qspi_integrity_pass"),
        "safe_z203_install_mode": data.get("safe_z203_install_mode", "sd"),
        "diagnosis": data.get("diagnosis", ""),
    }


def classify(
    z203_pattern: dict[str, Any],
    z203_linux: dict[str, Any],
    z103_pattern: dict[str, Any],
    integrity: dict[str, Any],
) -> dict[str, Any]:
    z203_pat = z203_pattern_failure(z203_pattern)
    z203_lin = z203_linux_failure(z203_linux)
    z103_pat = z103_pattern_health(z103_pattern)
    z203_int = z203_integrity(integrity)

    fault_classified = (
        z203_pat["fault_signature_matches_z203_0x44"]
        and z203_lin["linux_path_reproduces_fault"]
        and z103_pat["healthy_reference_passed"]
        and z203_int["qspi_integrity_pass"] is False
    )

    if fault_classified:
        verdict = "z203_qspi_program_fault_classified"
        repair_policy = "block_full_fit_repair_until_z203_small_write_passes"
        install_policy = "normal_installer_must_use_sd_for_z203"
        diagnosis = (
            "Z203 erase/readback and rollback work, but program/readback leaves "
            "the 0x44 stuck-bit signature. Z103 clears the same patterns through "
            "the product-family Linux MTD path, so this is Z203-specific."
        )
    else:
        verdict = "qspi_evidence_incomplete_or_changed"
        repair_policy = "do_not_write_full_fit_without_human_review"
        install_policy = "fail_closed"
        diagnosis = (
            "Required evidence is missing or no longer matches the known Z203 "
            "fault signature. Do not infer that QSPI is repaired."
        )

    return {
        "event": "fieldmesh_qspi_fault_classification",
        "verdict": verdict,
        "fault_classified": fault_classified,
        "z203_pattern": z203_pat,
        "z203_linux": z203_lin,
        "z103_pattern": z103_pat,
        "z203_integrity": z203_int,
        "install_policy": install_policy,
        "repair_policy": repair_policy,
        "full_z203_qspi_fit_repair_allowed": False,
        "normal_z203_qspi_install_allowed": False,
        "requires_before_z203_qspi_repair": [
            "Z203 guarded small program/readback passes on a rollback scratch sector",
            "Z203 QSPI integrity gate reports qspi_integrity_pass=true",
            "U-Boot qspiboot verifies the current FieldMesh FIT",
        ],
        "diagnosis": diagnosis,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--z203-pattern-summary",
        type=Path,
        default=latest_summary(Z203_CAPTURES, "z203_uboot_qspi_program_patterns_*"),
    )
    parser.add_argument(
        "--z203-linux-summary",
        type=Path,
        default=latest_summary(Z203_CAPTURES, "z203_linux_qspi_status_tail_write_aligned_*"),
    )
    parser.add_argument(
        "--z103-pattern-summary",
        type=Path,
        default=latest_summary(Z103_CAPTURES, "z103_linux_qspi_program_patterns_*"),
    )
    parser.add_argument(
        "--z203-integrity-summary",
        type=Path,
        default=latest_summary(Z203_CAPTURES, "z203_qspi_integrity_diag_*"),
    )
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument(
        "--allow-incomplete",
        action="store_true",
        help="exit 0 even when the evidence does not classify the current fault",
    )
    args = parser.parse_args()

    output = classify(
        load_json(args.z203_pattern_summary),
        load_json(args.z203_linux_summary),
        load_json(args.z103_pattern_summary),
        load_json(args.z203_integrity_summary) if args.z203_integrity_summary else None,
    )
    text = json.dumps(output, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if output["fault_classified"] or args.allow_incomplete else 1


if __name__ == "__main__":
    raise SystemExit(main())
