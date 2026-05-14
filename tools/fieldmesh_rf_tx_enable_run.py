#!/usr/bin/env python3
"""Generate or execute a guarded FieldMesh conducted/shielded TX-enable run.

The default mode only validates the plan and writes a board-local execution
script. Live execution requires an explicit backend script plus RF/hardware
write authorizations, so this wrapper can enforce FieldMesh safety contracts
without guessing board-specific AD936x enable commands.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any


MIN_FIXTURE_ATTENUATION_DB = 30.0
MAX_TX_DURATION_MS = 1000
CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_plan(plan: dict[str, Any]) -> None:
    if plan.get("event") != "fieldmesh_rf_tx_enable_plan" or plan.get("ok") is not True:
        raise SystemExit("input is not a successful FieldMesh RF TX-enable plan")
    if plan.get("mode") != "review-plan":
        raise SystemExit("TX-enable executor requires a review-plan input")
    safety = plan.get("safety", {})
    for key in (
        "executes_commands",
        "writes_hardware",
        "starts_rf_tx",
        "opens_iio_buffers",
        "uses_inter_board_ip_routing",
        "live_tx_enable_authorized",
    ):
        if safety.get(key) is not False:
            raise SystemExit(f"plan safety key {key} already crossed boundary")
    if safety.get("requires_manual_fixture_review") is not True:
        raise SystemExit("plan does not require manual fixture review")
    sequence = plan.get("sequence", [])
    if not isinstance(sequence, list) or not sequence:
        raise SystemExit("plan is missing a sequence")
    names = {row.get("name") for row in sequence if isinstance(row, dict)}
    for required in (
        "select_fieldmesh_dac_source",
        "arm_fieldmesh_tx_guard",
        "configure_tx_frequency_profile",
        "bounded_tx_enable_window",
        "rollback_tx_enable",
        "rollback_fieldmesh_dac_source",
        "rollback_fieldmesh_tx_guard",
    ):
        if required not in names:
            raise SystemExit(f"plan is missing sequence step {required}")


def require_args(args: argparse.Namespace, plan: dict[str, Any]) -> None:
    if not args.conducted_or_shielded:
        raise SystemExit("--conducted-or-shielded is required")
    if not args.legal_frequency_profile:
        raise SystemExit("--legal-frequency-profile is required")
    if not args.rx_first:
        raise SystemExit("--rx-first is required")
    if not args.tx_enable_guard:
        raise SystemExit("--tx-enable-guard is required")
    if not args.sidecar_preflight_passed:
        raise SystemExit("--sidecar-preflight-passed is required")
    if not args.rf_engine_ready:
        raise SystemExit("--rf-engine-ready is required")
    if not args.target_is_zynq_board:
        raise SystemExit("--target-is-zynq-board is required")
    if args.fixture_attenuation_db < MIN_FIXTURE_ATTENUATION_DB:
        raise SystemExit(f"--fixture-attenuation-db must be >= {MIN_FIXTURE_ATTENUATION_DB:g}")
    if args.fixture_attenuation_db < float(plan.get("fixture_attenuation_db", 0.0)):
        raise SystemExit("--fixture-attenuation-db is less than the planned attenuation")
    if args.max_tx_duration_ms < 1 or args.max_tx_duration_ms > MAX_TX_DURATION_MS:
        raise SystemExit(f"--max-tx-duration-ms must be 1..{MAX_TX_DURATION_MS}")
    if args.max_tx_duration_ms > int(plan.get("max_tx_duration_ms", MAX_TX_DURATION_MS)):
        raise SystemExit("--max-tx-duration-ms exceeds the planned duration")
    if args.execute_live_tx:
        if not args.allow_hardware_writes:
            raise SystemExit("--execute-live-tx requires --allow-hardware-writes")
        if not args.allow_rf_tx:
            raise SystemExit("--execute-live-tx requires --allow-rf-tx")
        if args.operator_confirmation != CONFIRMATION:
            raise SystemExit(f"--operator-confirmation must equal {CONFIRMATION}")
        if not args.fixture_id:
            raise SystemExit("--execute-live-tx requires --fixture-id")
        if args.tx_enable_backend is None:
            raise SystemExit("--execute-live-tx requires --tx-enable-backend")
        if not args.tx_enable_backend.exists():
            raise SystemExit(f"missing TX-enable backend: {args.tx_enable_backend}")
        if not os.access(args.tx_enable_backend, os.X_OK):
            raise SystemExit(f"TX-enable backend is not executable: {args.tx_enable_backend}")


def shell(argv: list[str]) -> str:
    return " ".join(shlex.quote(str(arg)) for arg in argv)


def sequence_by_name(plan: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(row["name"]): row for row in plan["sequence"]}


def script_lines(plan: dict[str, Any], args: argparse.Namespace) -> list[str]:
    rows = sequence_by_name(plan)
    backend = args.tx_enable_backend or Path("/usr/libexec/fieldmesh/fieldmesh-rf-tx-enable-backend")
    bounded = rows["bounded_tx_enable_window"]
    rollback_tx = rows["rollback_tx_enable"]
    rollback_source = rows["rollback_fieldmesh_dac_source"]
    rollback_guard = rows["rollback_fieldmesh_tx_guard"]
    source = rows["select_fieldmesh_dac_source"]
    guard = rows["arm_fieldmesh_tx_guard"]
    tune = rows["configure_tx_frequency_profile"]

    return [
        "#!/bin/sh",
        "set -eu",
        "",
        "# Generated by fieldmesh_rf_tx_enable_run.py.",
        "# Must run only on a conducted/shielded fixture with RX already armed.",
        f"FIELD_MESH_FIXTURE_ID={shlex.quote(args.fixture_id or 'REVIEW_ONLY')}",
        f"FIELD_MESH_MAX_TX_DURATION_MS={int(args.max_tx_duration_ms)}",
        f"FIELD_MESH_FIXTURE_ATTENUATION_DB={float(args.fixture_attenuation_db):g}",
        "export FIELD_MESH_FIXTURE_ID FIELD_MESH_MAX_TX_DURATION_MS FIELD_MESH_FIXTURE_ATTENUATION_DB",
        "",
        "rollback() {",
        f"  {rollback_tx['shell']} || true",
        f"  {rollback_source['shell']} || true",
        f"  {rollback_guard['shell']} || true",
        "}",
        "trap rollback EXIT INT TERM",
        "",
        "echo fieldmesh_rf_tx_enable_preflight=begin",
        "test -c /dev/mem",
        "command -v fieldmesh-udp-probe >/dev/null 2>&1",
        "echo fieldmesh_rf_tx_enable_preflight=ok",
        "",
        f"{source['shell']}",
        f"{guard['shell']}",
        f"{tune['shell']}",
        "",
        "if [ \"${FIELD_MESH_EXECUTE_LIVE_TX:-0}\" != \"1\" ]; then",
        "  echo fieldmesh_rf_tx_enable_live_tx=skipped",
        "  exit 0",
        "fi",
        f"{shell([str(backend), '--bounded-tx-enable'])}",
        f"# planned bounded TX step: {bounded['shell']}",
        "echo fieldmesh_rf_tx_enable_live_tx=done",
    ]


def write_script(path: Path, plan: dict[str, Any], args: argparse.Namespace) -> None:
    path.write_text("\n".join(script_lines(plan, args)) + "\n", encoding="utf-8")
    path.chmod(0o755)


def run_backend(args: argparse.Namespace, plan: dict[str, Any], script_path: Path) -> dict[str, Any]:
    del plan, script_path
    env = os.environ.copy()
    env.update(
        {
            "FIELD_MESH_EXECUTE_LIVE_TX": "1",
            "FIELD_MESH_FIXTURE_ID": args.fixture_id,
            "FIELD_MESH_MAX_TX_DURATION_MS": str(args.max_tx_duration_ms),
            "FIELD_MESH_FIXTURE_ATTENUATION_DB": f"{args.fixture_attenuation_db:g}",
        }
    )
    started = time.monotonic()
    proc = subprocess.run(
        [str(args.tx_enable_backend), "--bounded-tx-enable"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return {
        "returncode": proc.returncode,
        "ok": proc.returncode == 0,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "stdout": proc.stdout.decode("utf-8", errors="replace")[:8192],
        "stderr": proc.stderr.decode("utf-8", errors="replace")[:8192],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tx-enable-plan", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--max-tx-duration-ms", type=int, required=True)
    parser.add_argument("--fixture-id")
    parser.add_argument("--operator-confirmation")
    parser.add_argument("--tx-enable-backend", type=Path)
    parser.add_argument("--conducted-or-shielded", action="store_true")
    parser.add_argument("--legal-frequency-profile", action="store_true")
    parser.add_argument("--rx-first", action="store_true")
    parser.add_argument("--tx-enable-guard", action="store_true")
    parser.add_argument("--sidecar-preflight-passed", action="store_true")
    parser.add_argument("--rf-engine-ready", action="store_true")
    parser.add_argument("--target-is-zynq-board", action="store_true")
    parser.add_argument("--allow-review-script", action="store_true")
    parser.add_argument("--execute-live-tx", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = load_json(args.tx_enable_plan)
    require_plan(plan)
    require_args(args, plan)
    if not args.allow_review_script:
        raise SystemExit("--allow-review-script is required to generate the board script")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    script_path = args.out_dir / "fieldmesh_rf_tx_enable_execute.sh"
    write_script(script_path, plan, args)

    execution: dict[str, Any] | None = None
    if args.execute_live_tx:
        execution = run_backend(args, plan, script_path)

    report = {
        "event": "fieldmesh_rf_tx_enable_run",
        "ok": execution is None or execution.get("ok") is True,
        "mode": "execute-live-tx" if args.execute_live_tx else "dry-run",
        "generated_script": str(script_path),
        "fixture_id": args.fixture_id,
        "fixture_attenuation_db": args.fixture_attenuation_db,
        "max_tx_duration_ms": args.max_tx_duration_ms,
        "safety": {
            "conducted_or_shielded": True,
            "legal_frequency_profile": True,
            "rx_first": True,
            "tx_enable_guard": True,
            "sidecar_preflight_passed": True,
            "rf_engine_ready": True,
            "target_is_zynq_board": True,
            "commands_executed": bool(args.execute_live_tx),
            "writes_hardware": bool(args.execute_live_tx),
            "starts_rf_tx": bool(args.execute_live_tx),
            "opens_iio_buffers": False,
            "uses_inter_board_ip_routing": False,
            "requires_backend": True,
            "requires_bounded_tx_duration": True,
            "requires_rollback": True,
        },
        "plan": str(args.tx_enable_plan),
        "execution": execution,
    }
    text = json.dumps(report, indent=2, sort_keys=True) if args.pretty else json.dumps(report, sort_keys=True)
    (args.out_dir / "fieldmesh_rf_tx_enable_run.json").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
