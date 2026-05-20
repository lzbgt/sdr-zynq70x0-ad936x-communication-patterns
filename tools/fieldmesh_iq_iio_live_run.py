#!/usr/bin/env python3
"""Run or dry-run a guarded over-air AD936x IIO IQ burst procedure."""

from __future__ import annotations

import argparse
import contextlib
import json
import math
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any

import fieldmesh_iq_burst_smoke as iq_smoke
import fieldmesh_rf_fixture_evidence as fixture_evidence


MIN_FIXTURE_ATTENUATION_DB = 30.0
MIN_AD936X_LIVE_SAMPLE_RATE_HZ = 2_083_333
MAX_LIVE_TX_DURATION_MS = 1000
DEFAULT_RX_ARM_DELAY_MS = 10
DEFAULT_RX_CAPTURE_MARGIN_MS = 10
LIVE_RF_CONFIRMATION = "I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH"
LEGACY_LIVE_RF_CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"
VALID_LIVE_RF_CONFIRMATIONS = {LIVE_RF_CONFIRMATION, LEGACY_LIVE_RF_CONFIRMATION}


def plan_center_frequency_hz(plan: dict[str, Any]) -> int | None:
    for step in plan.get("command_plan", []):
        if isinstance(step, dict) and step.get("name") == "configure_rx_phy":
            value = step.get("center_frequency_hz")
            return int(value) if value is not None else None
    return None


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_plan(plan: dict[str, Any]) -> None:
    if plan.get("event") != "fieldmesh_iq_iio_live_plan" or plan.get("ok") is not True:
        raise SystemExit("input is not a successful FieldMesh IIO live plan")
    management = plan.get("management_plane", {})
    safety = plan.get("safety", {})
    if management.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("live run plan must not use inter-board IP routing")
    for key in ("executes_commands", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
        if safety.get(key) is not False:
            raise SystemExit(f"live run must start from a non-executing plan: {key}={safety.get(key)!r}")
    if plan.get("tx_board") == plan.get("rx_board"):
        raise SystemExit("live run requires distinct TX and RX boards")
    for step in plan.get("command_plan", []):
        if isinstance(step, dict) and step.get("name") in {"configure_rx_phy", "configure_tx_phy"}:
            rate = int(step.get("sample_rate_hz", 0))
            if rate < MIN_AD936X_LIVE_SAMPLE_RATE_HZ:
                raise SystemExit(
                    f"AD936x live sample rate must be >= {MIN_AD936X_LIVE_SAMPLE_RATE_HZ}; got {rate}"
                )


def require_guard(args: argparse.Namespace, plan: dict[str, Any]) -> None:
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
    plan_attenuation = float(plan.get("safety", {}).get("fixture_attenuation_db", 0.0))
    if args.fixture_attenuation_db < plan_attenuation:
        raise SystemExit(
            f"--fixture-attenuation-db must be >= planned {plan_attenuation:g} dB"
        )
    if args.max_tx_duration_ms < 1 or args.max_tx_duration_ms > MAX_LIVE_TX_DURATION_MS:
        raise SystemExit(
            f"--max-tx-duration-ms must be between 1 and {MAX_LIVE_TX_DURATION_MS}"
        )
    if args.rx_arm_delay_ms < 0:
        raise SystemExit("--rx-arm-delay-ms must be >= 0")
    if args.rx_capture_margin_ms < 0:
        raise SystemExit("--rx-capture-margin-ms must be >= 0")
    if args.execute_live_rf:
        if not args.allow_hardware_writes:
            raise SystemExit("--execute-live-rf also requires --allow-hardware-writes")
        if not args.allow_rf_tx:
            raise SystemExit("--execute-live-rf also requires --allow-rf-tx")
        if args.operator_confirmation not in VALID_LIVE_RF_CONFIRMATIONS:
            raise SystemExit(
                f"--execute-live-rf requires --operator-confirmation {LIVE_RF_CONFIRMATION!r}"
            )
        if not args.fixture_id:
            raise SystemExit("--execute-live-rf requires --fixture-id")
        if not args.fixture_evidence:
            raise SystemExit("--execute-live-rf requires --fixture-evidence")
        fixture_evidence.validate_fixture_evidence(
            fixture_evidence.load_json(args.fixture_evidence),
            fixture_id=args.fixture_id,
            fixture_attenuation_db=args.fixture_attenuation_db,
            center_frequency_hz=plan_center_frequency_hz(plan),
            require_production_evidence=True,
        )
        if not (args.tx_uri and args.rx_uri):
            raise SystemExit("--execute-live-rf requires --tx-uri and --rx-uri")


def shell_quote(args: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in args)


def command_row(
    name: str,
    args: list[str],
    *,
    stdin_file: str | None = None,
    stdout_file: str | None = None,
    background: bool = False,
) -> dict[str, Any]:
    rendered = shell_quote(args)
    if stdin_file:
        rendered = f"{rendered} < {shlex.quote(stdin_file)}"
    if stdout_file:
        rendered = f"{rendered} > {shlex.quote(stdout_file)}"
    if background:
        rendered = f"{rendered} &"
    return {
        "name": name,
        "argv": args,
        "stdin_file": stdin_file,
        "stdout_file": stdout_file,
        "background": background,
        "shell": rendered,
    }


def iio_attr_channel(
    uri: str,
    device: str,
    channel: str,
    attr: str,
    value: int | float | str,
    *,
    direction: str | None = None,
) -> list[str]:
    args = [
        "iio_attr",
        "-u",
        uri,
    ]
    if direction == "input":
        args.append("-i")
    elif direction == "output":
        args.append("-o")
    elif direction is not None:
        raise SystemExit(f"unsupported IIO channel direction: {direction!r}")
    args += [
        "-c",
        device,
        channel,
        attr,
        str(value),
    ]
    return args


def stream_voltage_channels(board: str) -> list[str]:
    """Return one complex I/Q stream lane for the known board variant."""
    if board in {"z103", "z203"}:
        return ["voltage0", "voltage1"]
    raise SystemExit(f"unsupported board for IIO stream channel selection: {board!r}")


def command_script(plan: dict[str, Any], args: argparse.Namespace, capture_path: Path) -> list[dict[str, Any]]:
    fixture = {
        "center_frequency_hz": None,
        "sample_rate_hz": None,
        "rf_bandwidth_hz": None,
    }
    for step in plan["command_plan"]:
        if step["name"] == "configure_rx_phy":
            fixture.update(
                {
                    "center_frequency_hz": step["center_frequency_hz"],
                    "sample_rate_hz": step["sample_rate_hz"],
                    "rf_bandwidth_hz": step["rf_bandwidth_hz"],
                }
            )
            break
    if None in fixture.values():
        raise SystemExit("live plan is missing RF fixture parameters")

    tx_iio = plan["radio_data_plane"]["tx_iio"]
    rx_iio = plan["radio_data_plane"]["rx_iio"]
    iq = plan["iq_burst"]
    tx_uri = args.tx_uri or f"ip:<{plan['tx_board']}-management-ip>"
    rx_uri = args.rx_uri or f"ip:<{plan['rx_board']}-management-ip>"
    timeout_s = max(1, math.ceil(args.timeout_ms / 1000))
    tx_timeout_s = max(1, math.ceil(args.max_tx_duration_ms / 1000))
    samples = int(iq["iq_samples"])
    rx_samples = samples + math.ceil(
        int(fixture["sample_rate_hz"]) * (args.rx_arm_delay_ms + args.rx_capture_margin_ms) / 1000.0
    )
    buffer_size = args.buffer_size or samples
    rx_channels = stream_voltage_channels(plan["rx_board"])
    tx_channels = stream_voltage_channels(plan["tx_board"])

    rows = [
        command_row(
            "configure_rx_sampling_frequency",
            iio_attr_channel(
                rx_uri,
                "ad9361-phy",
                "voltage0",
                "sampling_frequency",
                fixture["sample_rate_hz"],
                direction="input",
            ),
        ),
        command_row(
            "configure_rx_rf_bandwidth",
            iio_attr_channel(
                rx_uri,
                "ad9361-phy",
                "voltage0",
                "rf_bandwidth",
                fixture["rf_bandwidth_hz"],
                direction="input",
            ),
        ),
        command_row(
            "configure_rx_lo",
            iio_attr_channel(
                rx_uri,
                "ad9361-phy",
                "altvoltage0",
                "frequency",
                fixture["center_frequency_hz"],
                direction="output",
            ),
        ),
        command_row(
            "configure_tx_sampling_frequency",
            iio_attr_channel(
                tx_uri,
                "ad9361-phy",
                "voltage0",
                "sampling_frequency",
                fixture["sample_rate_hz"],
                direction="output",
            ),
        ),
        command_row(
            "configure_tx_rf_bandwidth",
            iio_attr_channel(
                tx_uri,
                "ad9361-phy",
                "voltage0",
                "rf_bandwidth",
                fixture["rf_bandwidth_hz"],
                direction="output",
            ),
        ),
        command_row(
            "configure_tx_lo",
            iio_attr_channel(
                tx_uri,
                "ad9361-phy",
                "altvoltage1",
                "frequency",
                fixture["center_frequency_hz"],
                direction="output",
            ),
        ),
        command_row(
            "arm_rx_iio_buffer",
            [
                "timeout",
                str(timeout_s),
                "iio_readdev",
                "-u",
                rx_uri,
                "-b",
                str(buffer_size),
                "-s",
                str(rx_samples),
                rx_iio["rx_name"],
            ]
            + rx_channels,
            stdout_file=str(capture_path),
            background=True,
        ),
        command_row(
            "load_tx_iio_buffer",
            [
                "timeout",
                str(tx_timeout_s),
                "iio_writedev",
                "-u",
                tx_uri,
                "-b",
                str(buffer_size),
                "-s",
                str(samples),
                tx_iio["tx_name"],
            ]
            + tx_channels,
            stdin_file=iq["iq_file"],
        ),
    ]
    return rows


def write_script(path: Path, commands: list[dict[str, Any]]) -> None:
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        "# Generated by fieldmesh_iq_iio_live_run.py. Review fixture safety before use.",
    ]
    for row in commands:
        lines.append(f"# {row['name']}")
        lines.append(row["shell"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o755)


def run_command(row: dict[str, Any], *, stdin_file: str | None = None, stdout_file: str | None = None) -> dict[str, Any]:
    started = time.monotonic()
    stdin_context = open(stdin_file, "rb") if stdin_file else contextlib.nullcontext(subprocess.DEVNULL)
    stdout_context = open(stdout_file, "wb") if stdout_file else contextlib.nullcontext(subprocess.DEVNULL)
    with stdin_context as stdin_handle, stdout_context as stdout_handle:
        proc = subprocess.run(
            row["argv"],
            stdin=stdin_handle,
            stdout=stdout_handle,
            stderr=subprocess.PIPE,
            check=False,
        )
    return {
        "name": row["name"],
        "returncode": proc.returncode,
        "stderr": proc.stderr.decode("utf-8", errors="replace"),
        "elapsed_ms": int((time.monotonic() - started) * 1000),
    }


def execute_live(args: argparse.Namespace, commands: list[dict[str, Any]], capture_path: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for row in commands[:6]:
        result = run_command(row)
        results.append(result)
        if result["returncode"] != 0:
            raise SystemExit(f"{row['name']} failed: {result['stderr'].strip()}")

    rx_row = commands[6]
    tx_row = commands[7]
    rx_stdout = open(capture_path, "wb")
    try:
        rx_proc = subprocess.Popen(
            rx_row["argv"],
            stdin=subprocess.DEVNULL,
            stdout=rx_stdout,
            stderr=subprocess.PIPE,
        )
        time.sleep(args.rx_arm_delay_ms / 1000.0)
        tx_result = run_command(tx_row, stdin_file=tx_row["stdin_file"])
        results.append(tx_result)
        rx_timeout_s = int(rx_row["argv"][1]) + 2
        rx_stderr = rx_proc.communicate(timeout=rx_timeout_s)[1]
        results.append(
            {
                "name": rx_row["name"],
                "returncode": rx_proc.returncode,
                "stderr": rx_stderr.decode("utf-8", errors="replace"),
            }
        )
    finally:
        rx_stdout.close()
        if rx_proc.poll() is None:
            rx_proc.terminate()
            try:
                rx_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                rx_proc.kill()
    for result in results[6:]:
        if result["returncode"] != 0:
            raise SystemExit(f"{result['name']} failed: {result.get('stderr', '').strip()}")
    return results


def decode_capture(plan: dict[str, Any], args: argparse.Namespace, capture_path: Path) -> dict[str, Any]:
    if not capture_path.exists():
        return {"attempted": False, "reason": "capture file missing"}
    iq = capture_path.read_bytes()
    if not iq:
        return {"attempted": False, "reason": "capture file empty"}
    smoke_report = load_json(Path(plan["iq_burst"]["report"]))
    samples_per_symbol = int(smoke_report["encoding"]["samples_per_symbol"])
    baseband_carrier_hz = int(smoke_report["encoding"].get("baseband_carrier_hz", 0))
    carrier_candidates = [baseband_carrier_hz]
    if baseband_carrier_hz:
        carrier_candidates += [
            baseband_carrier_hz - 20000,
            baseband_carrier_hz + 20000,
            baseband_carrier_hz - 50000,
            baseband_carrier_hz + 50000,
        ]
    coherent: dict[str, Any] = {"ok": False, "score": 0.0}
    for carrier_hz in carrier_candidates:
        candidate_iq = iq_smoke.mix_iq(iq, smoke_report["rf_fixture"]["sample_rate_hz"], carrier_hz) if carrier_hz else iq
        candidate = iq_smoke.decode_bpsk_iq_coherent(candidate_iq, samples_per_symbol)
        candidate["baseband_carrier_hz"] = carrier_hz
        if candidate.get("ok") is True:
            coherent = candidate
            break
        if float(candidate.get("score", 0.0)) > float(coherent.get("score", 0.0)):
            coherent = candidate
    if coherent.get("ok") is True:
        recovered = coherent["recovered"]
        crc = iq_smoke.harness.unpack_memory_frame(recovered).get("frame_crc")
        return {
            "attempted": True,
            "ok": crc == plan["iq_burst"]["frame_crc"],
            "capture_bytes": len(iq),
            "recovered_frame_hex": recovered.hex(),
            "recovered_frame_bytes": len(recovered),
            "recovered_frame_crc": crc,
            "expected_frame_crc": plan["iq_burst"]["frame_crc"],
            "sample_offset": coherent["sample_offset"],
            "symbol_start": coherent["symbol_start"],
            "phase_i": coherent["phase_i"],
            "phase_q": coherent["phase_q"],
            "sync_score": coherent["score"],
            "decoder": "coherent_complex_bpsk_v1",
            "baseband_carrier_hz": coherent["baseband_carrier_hz"],
        }
    last_error = "missing IQ burst preamble/sync"
    for sample_offset in range(samples_per_symbol):
        try:
            bits = iq_smoke.decode_bpsk_iq_bits(iq, samples_per_symbol, sample_offset)
        except Exception as exc:  # noqa: BLE001 - preserve decode diagnostic.
            last_error = str(exc)
            continue
        for bit_shift in range(8):
            shifted = bits[bit_shift:]
            for inverted in (False, True):
                candidate_bits = [1 - bit for bit in shifted] if inverted else shifted
                try:
                    recovered = iq_smoke.recover_frame(iq_smoke.bits_to_bytes(candidate_bits))
                except Exception as exc:  # noqa: BLE001 - keep searching other alignments.
                    last_error = str(exc)
                    continue
                crc = iq_smoke.harness.unpack_memory_frame(recovered).get("frame_crc")
                return {
                    "attempted": True,
                    "ok": crc == plan["iq_burst"]["frame_crc"],
                    "capture_bytes": len(iq),
                    "recovered_frame_hex": recovered.hex(),
                    "recovered_frame_bytes": len(recovered),
                    "recovered_frame_crc": crc,
                    "expected_frame_crc": plan["iq_burst"]["frame_crc"],
                    "sample_offset": sample_offset,
                    "bit_shift": bit_shift,
                    "inverted": inverted,
                }
    return {
        "attempted": True,
        "ok": False,
        "error": last_error,
        "capture_bytes": len(iq),
        "best_coherent_score": coherent.get("score"),
        "best_coherent_sample_offset": coherent.get("sample_offset"),
        "best_coherent_symbol_start": coherent.get("symbol_start"),
        "best_coherent_phase_i": coherent.get("phase_i"),
        "best_coherent_phase_q": coherent.get("phase_q"),
        "best_coherent_carrier_hz": coherent.get("baseband_carrier_hz"),
        "decoder": "coherent_complex_bpsk_v1",
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    plan = load_json(args.live_plan)
    require_plan(plan)
    require_guard(args, plan)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    capture_path = args.out_dir / "rx_capture_i16le.iq"
    commands = command_script(plan, args, capture_path)
    script_path = args.out_dir / "run_iio_burst.sh"
    write_script(script_path, commands)

    command_results: list[dict[str, Any]] = []
    decode: dict[str, Any] = {"attempted": False, "reason": "dry-run"}
    if args.execute_live_rf:
        command_results = execute_live(args, commands, capture_path)
        decode = decode_capture(plan, args, capture_path)

    safety = {
        "authorized_rf_path": True,
        "conducted_or_shielded": bool(args.conducted_or_shielded),
        "fixture_attenuation_db": args.fixture_attenuation_db,
        "fixture_id": args.fixture_id or None,
        "fixture_evidence": str(args.fixture_evidence) if args.fixture_evidence else None,
        "legal_frequency_profile": True,
        "tx_enable_guard": True,
        "rx_first": True,
        "allow_hardware_writes": bool(args.allow_hardware_writes),
        "allow_rf_tx": bool(args.allow_rf_tx),
        "operator_confirmation_ok": args.operator_confirmation in VALID_LIVE_RF_CONFIRMATIONS,
        "max_tx_duration_ms": args.max_tx_duration_ms,
        "executes_commands": bool(args.execute_live_rf),
        "opens_iio_buffers": bool(args.execute_live_rf),
        "starts_rf_tx": bool(args.execute_live_rf),
        "writes_hardware": bool(args.execute_live_rf),
        "live_rf_allowed_by_this_tool": bool(args.execute_live_rf),
    }
    report = {
        "event": "fieldmesh_iq_iio_live_run",
        "ok": not args.execute_live_rf or decode.get("ok") is True,
        "mode": "execute-live-rf" if args.execute_live_rf else "dry-run",
        "tx_board": plan["tx_board"],
        "rx_board": plan["rx_board"],
        "tx_uri": args.tx_uri,
        "rx_uri": args.rx_uri,
        "management_plane": plan["management_plane"],
        "radio_data_plane": plan["radio_data_plane"],
        "iq_burst": plan["iq_burst"],
        "safety": safety,
        "generated_script": str(script_path),
        "capture_file": str(capture_path),
        "commands": commands,
        "command_results": command_results,
        "decode": decode,
    }
    out_path = args.out_dir / "fieldmesh_iq_iio_live_run.json"
    out_path.write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live-plan", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/iq-iio-live-run"))
    parser.add_argument("--tx-uri")
    parser.add_argument("--rx-uri")
    parser.add_argument("--buffer-size", type=int)
    parser.add_argument("--timeout-ms", type=int, default=5000)
    parser.add_argument("--rx-arm-delay-ms", type=int, default=DEFAULT_RX_ARM_DELAY_MS)
    parser.add_argument("--rx-capture-margin-ms", type=int, default=DEFAULT_RX_CAPTURE_MARGIN_MS)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--authorized-rf-path", action="store_true")
    parser.add_argument("--conducted-or-shielded", action="store_true")
    parser.add_argument("--legal-frequency-profile", action="store_true")
    parser.add_argument("--tx-enable-guard", action="store_true")
    parser.add_argument("--rx-first", action="store_true")
    parser.add_argument("--execute-live-rf", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--fixture-id")
    parser.add_argument("--fixture-evidence", type=Path)
    parser.add_argument("--rf-path-id", dest="fixture_id")
    parser.add_argument("--rf-path-evidence", type=Path, dest="fixture_evidence")
    parser.add_argument("--operator-confirmation")
    parser.add_argument("--max-tx-duration-ms", type=int, default=MAX_LIVE_TX_DURATION_MS)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0 if report.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
