#!/usr/bin/env python3
"""Generate or execute a guarded FieldMesh authorized over-air TX-enable run.

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
CONFIRMATION = "I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH"
LEGACY_CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"
BACKEND_REQUEST_FILENAME = "fieldmesh_rf_tx_enable_backend_request.json"


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
    if safety.get("requires_manual_rf_path_review") is not True and safety.get("requires_manual_fixture_review") is not True:
        raise SystemExit("plan does not require manual RF path review")
    sequence = plan.get("sequence", [])
    if not isinstance(sequence, list) or not sequence:
        raise SystemExit("plan is missing a sequence")
    names = {row.get("name") for row in sequence if isinstance(row, dict)}
    for required in (
        "prove_rf_guard_action_policy",
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
    proof = plan.get("rf_guard_action_policy_self_test")
    if not isinstance(proof, dict):
        raise SystemExit("plan is missing RF guard action-policy self-test proof")
    for key, value in (
        ("active_guard_apply_allowed", False),
        ("active_source_select_allowed", True),
        ("idle_guard_apply_allowed", True),
        ("idle_source_select_allowed", True),
        ("fault_guard_apply_allowed", False),
        ("fault_source_select_allowed", False),
        ("reads_hardware", False),
        ("writes_hardware", False),
    ):
        if proof.get(key) is not value:
            raise SystemExit(f"plan RF guard action-policy self-test key {key} mismatch")


def require_args(args: argparse.Namespace, plan: dict[str, Any]) -> None:
    if not args.authorized_rf_path and not args.conducted_or_shielded:
        raise SystemExit("--authorized-rf-path is required")
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
    if args.conducted_or_shielded and args.fixture_attenuation_db < MIN_FIXTURE_ATTENUATION_DB:
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
        if args.operator_confirmation not in (CONFIRMATION, LEGACY_CONFIRMATION):
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
    action_policy = rows["prove_rf_guard_action_policy"]
    source = rows["select_fieldmesh_dac_source"]
    guard = rows["arm_fieldmesh_tx_guard"]
    tune = rows["configure_tx_frequency_profile"]

    return [
        "#!/bin/sh",
        "set -eu",
        "",
        "# Generated by fieldmesh_rf_tx_enable_run.py.",
        "# Must run only on an authorized over-air RF path with RX already armed.",
        "script_dir=$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)",
        f"FIELD_MESH_FIXTURE_ID={shlex.quote(args.fixture_id or 'REVIEW_ONLY')}",
        f"FIELD_MESH_MAX_TX_DURATION_MS={int(args.max_tx_duration_ms)}",
        f"FIELD_MESH_FIXTURE_ATTENUATION_DB={float(args.fixture_attenuation_db):g}",
        f"FIELD_MESH_RF_TX_ENABLE_REQUEST=${{FIELD_MESH_RF_TX_ENABLE_REQUEST:-$script_dir/{BACKEND_REQUEST_FILENAME}}}",
        "FIELD_MESH_ALLOW_HARDWARE_WRITES=${FIELD_MESH_ALLOW_HARDWARE_WRITES:-0}",
        "FIELD_MESH_ALLOW_RF_TX=${FIELD_MESH_ALLOW_RF_TX:-0}",
        "export FIELD_MESH_FIXTURE_ID FIELD_MESH_MAX_TX_DURATION_MS FIELD_MESH_FIXTURE_ATTENUATION_DB",
        "export FIELD_MESH_RF_TX_ENABLE_REQUEST FIELD_MESH_ALLOW_HARDWARE_WRITES FIELD_MESH_ALLOW_RF_TX",
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
        f"{action_policy['shell']}",
        "",
        "if [ \"${FIELD_MESH_EXECUTE_LIVE_TX:-0}\" != \"1\" ]; then",
        "  echo fieldmesh_rf_tx_enable_live_tx=skipped",
        "  exit 0",
        "fi",
        "if [ \"${FIELD_MESH_ALLOW_HARDWARE_WRITES:-0}\" != \"1\" ] || [ \"${FIELD_MESH_ALLOW_RF_TX:-0}\" != \"1\" ]; then",
        "  echo fieldmesh_rf_tx_enable_live_tx=missing_authorization >&2",
        "  exit 1",
        "fi",
        "",
        f"{source['shell']}",
        f"{guard['shell']}",
        "",
        f"# C backend performs planned tuning step: {tune['shell']}",
        f"{shlex.quote(str(backend))} --bounded-tx-enable --request \"$FIELD_MESH_RF_TX_ENABLE_REQUEST\"",
        f"# planned bounded TX step: {bounded['shell']}",
        "echo fieldmesh_rf_tx_enable_live_tx=done",
    ]


def write_script(path: Path, plan: dict[str, Any], args: argparse.Namespace) -> None:
    path.write_text("\n".join(script_lines(plan, args)) + "\n", encoding="utf-8")
    path.chmod(0o755)


def build_backend_request(args: argparse.Namespace, plan: dict[str, Any], script_path: Path) -> dict[str, Any]:
    rows = sequence_by_name(plan)
    proof = plan["rf_guard_action_policy_self_test"]
    return {
        "event": "fieldmesh_rf_tx_enable_backend_request",
        "ok": True,
        "contract_version": 1,
        "mode": "execute-live-tx" if args.execute_live_tx else "dry-run",
        "plan": str(args.tx_enable_plan),
        "generated_script": str(script_path),
        "fixture_id": args.fixture_id,
        "fixture_attenuation_db": float(args.fixture_attenuation_db),
        "center_frequency_hz": int(plan["center_frequency_hz"]),
        "sample_rate_hz": int(plan["sample_rate_hz"]),
        "rf_bandwidth_hz": int(plan["rf_bandwidth_hz"]),
        "tx_attenuation_db": float(plan["tx_attenuation_db"]),
        "max_tx_duration_ms": int(args.max_tx_duration_ms),
        "authorized_rf_path": bool(args.authorized_rf_path),
        "conducted_or_shielded": bool(args.conducted_or_shielded),
        "legal_frequency_profile": True,
        "rx_first": True,
        "tx_enable_guard": True,
        "sidecar_preflight_passed": True,
        "rf_engine_ready": True,
        "target_is_zynq_board": True,
        "requires_bounded_tx_duration": True,
        "requires_native_tune": True,
        "requires_rollback": True,
        "requires_c_rf_guard_action_policy_self_test": True,
        "starts_rf_tx_when_executed": True,
        "writes_hardware_when_executed": True,
        "opens_iio_buffers": False,
        "uses_inter_board_ip_routing": False,
        "rf_guard_action_policy_self_test": {
            "event": proof.get("event"),
            "ok": proof.get("ok"),
            "active_guard_apply_allowed": proof.get("active_guard_apply_allowed"),
            "active_source_select_allowed": proof.get("active_source_select_allowed"),
            "idle_guard_apply_allowed": proof.get("idle_guard_apply_allowed"),
            "idle_source_select_allowed": proof.get("idle_source_select_allowed"),
            "fault_guard_apply_allowed": proof.get("fault_guard_apply_allowed"),
            "fault_source_select_allowed": proof.get("fault_source_select_allowed"),
            "reads_hardware": proof.get("reads_hardware"),
            "writes_hardware": proof.get("writes_hardware"),
        },
        "sequence": {
            name: rows[name]["shell"]
            for name in (
                "prove_rf_guard_action_policy",
                "select_fieldmesh_dac_source",
                "arm_fieldmesh_tx_guard",
                "configure_tx_frequency_profile",
                "bounded_tx_enable_window",
                "rollback_tx_enable",
                "rollback_fieldmesh_dac_source",
                "rollback_fieldmesh_tx_guard",
            )
        },
    }


def write_backend_request(path: Path, request: dict[str, Any], pretty: bool) -> None:
    text = json.dumps(request, indent=2, sort_keys=True) if pretty else json.dumps(request, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def run_backend(args: argparse.Namespace, request_path: Path) -> dict[str, Any]:
    env = os.environ.copy()
    env.update(
        {
            "FIELD_MESH_EXECUTE_LIVE_TX": "1",
            "FIELD_MESH_ALLOW_HARDWARE_WRITES": "1",
            "FIELD_MESH_ALLOW_RF_TX": "1",
            "FIELD_MESH_FIXTURE_ID": args.fixture_id,
            "FIELD_MESH_MAX_TX_DURATION_MS": str(args.max_tx_duration_ms),
            "FIELD_MESH_FIXTURE_ATTENUATION_DB": f"{args.fixture_attenuation_db:g}",
            "FIELD_MESH_RF_TX_ENABLE_REQUEST": str(request_path),
        }
    )
    started = time.monotonic()
    proc = subprocess.run(
        [str(args.tx_enable_backend), "--bounded-tx-enable", "--request", str(request_path)],
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
    parser.add_argument("--authorized-rf-path", action="store_true")
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
    request_path = args.out_dir / BACKEND_REQUEST_FILENAME
    backend_request = build_backend_request(args, plan, script_path)
    write_backend_request(request_path, backend_request, args.pretty)
    write_script(script_path, plan, args)

    execution: dict[str, Any] | None = None
    if args.execute_live_tx:
        execution = run_backend(args, request_path)

    report = {
        "event": "fieldmesh_rf_tx_enable_run",
        "ok": execution is None or execution.get("ok") is True,
        "mode": "execute-live-tx" if args.execute_live_tx else "dry-run",
        "generated_script": str(script_path),
        "backend_request": str(request_path),
        "backend_contract_version": 1,
        "fixture_id": args.fixture_id,
        "fixture_attenuation_db": args.fixture_attenuation_db,
        "max_tx_duration_ms": args.max_tx_duration_ms,
        "safety": {
            "authorized_rf_path": True,
            "conducted_or_shielded": bool(args.conducted_or_shielded),
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
            "requires_backend_request_contract": True,
            "requires_bounded_tx_duration": True,
            "requires_native_tune": True,
            "requires_rollback": True,
            "rf_guard_action_policy_self_test_proven": True,
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
