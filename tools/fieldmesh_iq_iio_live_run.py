#!/usr/bin/env python3
"""Run or dry-run a guarded over-air AD936x IIO IQ burst procedure."""

from __future__ import annotations

import argparse
import atexit
import contextlib
import json
import math
import select
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
_HELPER_SERVERS: dict[tuple[str, ...], "BurstHelperServer"] = {}


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
    if args.cyclic_capture_periods < 1 or args.cyclic_capture_periods > 4:
        raise SystemExit("--cyclic-capture-periods must be between 1 and 4")
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


class BurstHelperServer:
    def __init__(self, argv: list[str], timeout_s: float) -> None:
        self.argv = argv
        self.timeout_s = timeout_s
        self.proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        ready = self._read_json_line(timeout_s, "helper_ready")
        if ready.get("event") != "fieldmesh_iio_burst_xfer_server" or ready.get("ok") is not True:
            self.close(kill=True)
            raise SystemExit(f"iio_burst_helper server did not become ready: {ready}")
        self.ready = ready
        self.transport_session_start: dict[str, Any] = {}
        self.transport_session_status: dict[str, Any] = {}
        self.transport_service_loop_start: dict[str, Any] = {}
        self.transport_service_loop_status: dict[str, Any] = {}

    def _stderr_after_exit(self) -> str:
        if self.proc.stderr is None:
            return ""
        if self.proc.poll() is None:
            return ""
        return self.proc.stderr.read()

    def _read_json_line(self, timeout_s: float, phase: str) -> dict[str, Any]:
        if self.proc.stdout is None:
            raise SystemExit("iio_burst_helper server stdout is unavailable")
        deadline = time.monotonic() + timeout_s
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.close(kill=True)
                raise SystemExit(f"iio_burst_helper server timed out during {phase}")
            ready, _, _ = select.select([self.proc.stdout], [], [], remaining)
            if not ready:
                continue
            line = self.proc.stdout.readline()
            if line:
                try:
                    data = json.loads(line)
                except json.JSONDecodeError as exc:
                    self.close(kill=True)
                    raise SystemExit(f"iio_burst_helper server emitted invalid JSON: {line.strip()}") from exc
                if not isinstance(data, dict):
                    self.close(kill=True)
                    raise SystemExit(f"iio_burst_helper server emitted non-object JSON: {line.strip()}")
                return data
            rc = self.proc.poll()
            if rc is not None:
                stderr = self._stderr_after_exit().strip()
                raise SystemExit(f"iio_burst_helper server exited during {phase}: rc={rc} stderr={stderr}")

    def xfer(self, fields: dict[str, str], timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        line = "XFER " + " ".join(f"{key}={value}" for key, value in fields.items()) + "\n"
        try:
            self.proc.stdin.write(line)
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        return self._read_json_line(timeout_s, "xfer")

    def worker_xfer(self, request_file: Path, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        line = f"WORKER_XFER request_file={request_file}\n"
        try:
            self.proc.stdin.write(line)
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        return self._read_json_line(timeout_s, "worker_xfer")

    def transport_service_loop_run(self, request_file: Path, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        line = f"TRANSPORT_SERVICE_LOOP_RUN request_file={request_file}\n"
        try:
            self.proc.stdin.write(line)
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        return self._read_json_line(timeout_s, "transport_service_loop_run")

    def start_transport_session(self, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        if self.transport_session_start:
            return self.transport_session_start
        try:
            self.proc.stdin.write("TRANSPORT_WORKER_START\n")
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        report = self._read_json_line(timeout_s, "transport_worker_start")
        if (
            report.get("event") != "fieldmesh_iio_burst_transport_worker_start"
            or report.get("ok") is not True
            or report.get("native_iio_burst_transport_session_proof")
            != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1"
        ):
            self.close(kill=True)
            raise SystemExit(f"iio_burst_helper transport session did not start: {report}")
        self.transport_session_start = report
        return report

    def start_transport_service_loop(self, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        if self.transport_service_loop_start:
            return self.transport_service_loop_start
        try:
            self.proc.stdin.write("TRANSPORT_SERVICE_LOOP_START\n")
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        report = self._read_json_line(timeout_s, "transport_service_loop_start")
        if (
            report.get("event") != "fieldmesh_iio_burst_transport_service_loop_start"
            or report.get("ok") is not True
            or report.get("native_iio_burst_transport_service_loop_proof")
            != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1"
        ):
            self.close(kill=True)
            raise SystemExit(f"iio_burst_helper transport service loop did not start: {report}")
        self.transport_service_loop_start = report
        return report

    def status_transport_session(self, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        try:
            self.proc.stdin.write("TRANSPORT_WORKER_STATUS\n")
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        report = self._read_json_line(timeout_s, "transport_worker_status")
        if report.get("event") != "fieldmesh_iio_burst_transport_worker_status":
            self.close(kill=True)
            raise SystemExit(f"iio_burst_helper transport status invalid: {report}")
        self.transport_session_status = report
        return report

    def status_transport_service_loop(self, timeout_s: float) -> dict[str, Any]:
        if self.proc.stdin is None:
            raise SystemExit("iio_burst_helper server stdin is unavailable")
        if self.proc.poll() is not None:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server is not running: stderr={stderr}")
        try:
            self.proc.stdin.write("TRANSPORT_SERVICE_LOOP_STATUS\n")
            self.proc.stdin.flush()
        except BrokenPipeError as exc:
            stderr = self._stderr_after_exit().strip()
            raise SystemExit(f"iio_burst_helper server pipe broke: stderr={stderr}") from exc
        report = self._read_json_line(timeout_s, "transport_service_loop_status")
        if report.get("event") != "fieldmesh_iio_burst_transport_service_loop_status":
            self.close(kill=True)
            raise SystemExit(f"iio_burst_helper transport service loop status invalid: {report}")
        self.transport_service_loop_status = report
        return report

    def close(self, *, kill: bool = False) -> None:
        if self.proc.poll() is None and not kill and self.proc.stdin is not None:
            with contextlib.suppress(Exception):
                self.proc.stdin.write("QUIT\n")
                self.proc.stdin.flush()
            with contextlib.suppress(subprocess.TimeoutExpired):
                self.proc.wait(timeout=1)
        if self.proc.poll() is None:
            with contextlib.suppress(Exception):
                self.proc.kill()
            with contextlib.suppress(Exception):
                self.proc.wait(timeout=1)


def close_helper_servers() -> None:
    for server in list(_HELPER_SERVERS.values()):
        server.close()
    _HELPER_SERVERS.clear()


atexit.register(close_helper_servers)


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


def tx_hardwaregain_channels(board: str) -> list[str]:
    """Return AD9361 PHY TX gain channels, which are not the same as I/Q lanes."""
    if board == "z203":
        return ["voltage0", "voltage1"]
    if board == "z103":
        return ["voltage0"]
    raise SystemExit(f"unsupported board for TX gain channel selection: {board!r}")


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
    tx_timeout_s = max(0.05, args.max_tx_duration_ms / 1000.0)
    samples = int(iq["iq_samples"])
    rx_margin_samples = math.ceil(
        int(fixture["sample_rate_hz"]) * (args.rx_arm_delay_ms + args.rx_capture_margin_ms) / 1000.0
    )
    capture_periods = args.cyclic_capture_periods if args.cyclic_tx else 1
    # Cyclic TX repeats the same IQ buffer until timeout. Two periods are the
    # conservative default for standalone live runs. The RF bridge can request
    # one period because the decoder now rejects CRC-wrong wrapped candidates.
    rx_samples = samples * capture_periods + rx_margin_samples
    buffer_size = args.buffer_size or samples
    rx_channels = stream_voltage_channels(plan["rx_board"])
    tx_channels = stream_voltage_channels(plan["tx_board"])
    tx_gain_channels = tx_hardwaregain_channels(plan["tx_board"])

    rows: list[dict[str, Any]] = []
    if not args.skip_rf_config and args.rx_gain_control_mode:
        rows.append(
            command_row(
                "configure_rx_gain_control_mode",
                iio_attr_channel(
                    rx_uri,
                    "ad9361-phy",
                    "voltage0",
                    "gain_control_mode",
                    args.rx_gain_control_mode,
                    direction="input",
                ),
            )
        )
    if not args.skip_rf_config and args.rx_hardwaregain_db is not None:
        rows.append(
            command_row(
                "configure_rx_hardwaregain",
                iio_attr_channel(
                    rx_uri,
                    "ad9361-phy",
                    "voltage0",
                    "hardwaregain",
                    args.rx_hardwaregain_db,
                    direction="input",
                ),
            )
        )
    if not args.skip_rf_config and args.tx_hardwaregain_db is not None:
        for channel in tx_gain_channels:
            rows.append(
                command_row(
                    f"configure_tx_{channel}_hardwaregain",
                    iio_attr_channel(
                        tx_uri,
                        "ad9361-phy",
                        channel,
                        "hardwaregain",
                        args.tx_hardwaregain_db,
                        direction="output",
                    ),
                )
            )

    tx_write_argv = [
        "timeout",
        f"{tx_timeout_s:.3f}".rstrip("0").rstrip("."),
        "iio_writedev",
        "-u",
        tx_uri,
    ]
    if args.cyclic_tx:
        tx_write_argv.append("-c")
    tx_write_argv += [
        "-b",
        str(buffer_size),
        "-s",
        str(samples),
        tx_iio["tx_name"],
    ] + tx_channels

    if not args.skip_rf_config:
        rows += [
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
        ]

    rows += [
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
            tx_write_argv,
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
    started = time.monotonic()
    results: list[dict[str, Any]] = []
    rx_index = next(index for index, row in enumerate(commands) if row["name"] == "arm_rx_iio_buffer")
    tx_index = next(index for index, row in enumerate(commands) if row["name"] == "load_tx_iio_buffer")
    for row in commands[:rx_index]:
        result = run_command(row)
        results.append(result)
        if result["returncode"] != 0:
            raise SystemExit(f"{row['name']} failed: {result['stderr'].strip()}")

    rx_row = commands[rx_index]
    tx_row = commands[tx_index]
    rx_stdout = open(capture_path, "wb")
    try:
        rx_started = time.monotonic()
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
        rx_timed_out = False
        try:
            rx_stderr = rx_proc.communicate(timeout=rx_timeout_s)[1]
        except subprocess.TimeoutExpired:
            rx_timed_out = True
            rx_proc.terminate()
            try:
                rx_stderr = rx_proc.communicate(timeout=2)[1]
            except subprocess.TimeoutExpired:
                rx_proc.kill()
                rx_stderr = rx_proc.communicate()[1]
        results.append(
            {
                "name": rx_row["name"],
                "returncode": rx_proc.returncode,
                "stderr": rx_stderr.decode("utf-8", errors="replace"),
                "timed_out": rx_timed_out,
                "elapsed_ms": int((time.monotonic() - rx_started) * 1000),
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
    for result in results[rx_index:]:
        allowed_timeout = (
            (args.cyclic_tx and result["name"] == "load_tx_iio_buffer" and result["returncode"] == 124)
            or (result["name"] == "arm_rx_iio_buffer" and result.get("timed_out") is True and capture_path.exists())
        )
        if result["returncode"] != 0 and not allowed_timeout:
            raise SystemExit(f"{result['name']} failed: {result.get('stderr', '').strip()}")
    results.append(
        {
            "name": "execute_live_total",
            "returncode": 0,
            "elapsed_ms": int((time.monotonic() - started) * 1000),
        }
    )
    return results


def option_after(argv: list[str], flag: str) -> str:
    try:
        return argv[argv.index(flag) + 1]
    except (ValueError, IndexError) as exc:
        raise SystemExit(f"generated command is missing {flag}: {argv}") from exc


def write_worker_xfer_request(path: Path, fields: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "event=fieldmesh_iio_burst_transport_worker_request",
        "native_iio_burst_transport_request=1",
    ]
    for key, value in fields.items():
        if "\n" in key or "\n" in value or "=" in key:
            raise SystemExit(f"invalid IIO burst transport request field: {key!r}")
        lines.append(f"{key}={value}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def helper_server_for(args: argparse.Namespace, helper_argv: list[str], channels: list[str]) -> BurstHelperServer:
    server_argv = [
        str(args.burst_helper),
        "--rx-uri",
        option_after(helper_argv, "--rx-uri"),
        "--tx-uri",
        option_after(helper_argv, "--tx-uri"),
        "--rx-device",
        option_after(helper_argv, "--rx-device"),
        "--tx-device",
        option_after(helper_argv, "--tx-device"),
        "--rx-timeout-ms",
        option_after(helper_argv, "--rx-timeout-ms"),
        "--server",
    ]
    for channel in channels:
        server_argv += ["--channel", channel]
    key = tuple(server_argv)
    server = _HELPER_SERVERS.get(key)
    if server is None or server.proc.poll() is not None:
        server = BurstHelperServer(server_argv, max(args.timeout_ms / 1000.0, 1.0))
        _HELPER_SERVERS[key] = server
    return server


def execute_live_with_helper(
    args: argparse.Namespace,
    commands: list[dict[str, Any]],
    capture_path: Path,
) -> list[dict[str, Any]]:
    started = time.monotonic()
    results: list[dict[str, Any]] = []
    rx_index = next(index for index, row in enumerate(commands) if row["name"] == "arm_rx_iio_buffer")
    tx_index = next(index for index, row in enumerate(commands) if row["name"] == "load_tx_iio_buffer")
    for row in commands[:rx_index]:
        result = run_command(row)
        results.append(result)
        if result["returncode"] != 0:
            raise SystemExit(f"{row['name']} failed: {result['stderr'].strip()}")

    rx_row = commands[rx_index]
    tx_row = commands[tx_index]
    rx_argv = rx_row["argv"]
    tx_argv = tx_row["argv"]
    rx_device_index = rx_argv.index("-s") + 2
    tx_device_index = tx_argv.index("-s") + 2
    channels = tx_argv[tx_device_index + 1 :]
    if channels != rx_argv[rx_device_index + 1 :]:
        raise SystemExit("RX/TX IIO helper requires matching stream channel lists")

    helper_argv = [
        str(args.burst_helper),
        "--rx-uri",
        option_after(rx_argv, "-u"),
        "--tx-uri",
        option_after(tx_argv, "-u"),
        "--rx-device",
        rx_argv[rx_device_index],
        "--tx-device",
        tx_argv[tx_device_index],
        "--rx-file",
        str(capture_path),
        "--tx-file",
        tx_row["stdin_file"],
        "--rx-samples",
        option_after(rx_argv, "-s"),
        "--tx-samples",
        option_after(tx_argv, "-s"),
        "--buffer-size",
        option_after(rx_argv, "-b"),
        "--rx-timeout-ms",
        str(max(args.timeout_ms, 1)),
        "--rx-arm-delay-ms",
        str(args.rx_arm_delay_ms),
        "--tx-duration-ms",
        str(args.max_tx_duration_ms),
    ]
    if args.cyclic_tx:
        helper_argv.append("--cyclic")
    for channel in channels:
        helper_argv += ["--channel", channel]

    helper_row = command_row("iio_burst_helper", helper_argv)
    helper_started = time.monotonic()
    helper_ready: dict[str, Any] = {}
    helper_transport_start: dict[str, Any] = {}
    helper_transport_status: dict[str, Any] = {}
    helper_transport_service_loop_start: dict[str, Any] = {}
    helper_transport_service_loop_status: dict[str, Any] = {}
    if getattr(args, "persistent_burst_helper", False):
        server = helper_server_for(args, helper_argv, channels)
        helper_ready = dict(server.ready)
        helper_transport_start = dict(
            server.start_transport_session(max(args.timeout_ms / 1000.0, 1.0))
        )
        helper_transport_service_loop_start = dict(
            server.start_transport_service_loop(max(args.timeout_ms / 1000.0, 1.0))
        )
        xfer_fields = {
            "tx_file": str(tx_row["stdin_file"]),
            "rx_file": str(capture_path),
            "tx_samples": option_after(tx_argv, "-s"),
            "rx_samples": option_after(rx_argv, "-s"),
            "buffer_size": option_after(rx_argv, "-b"),
            "tx_duration_ms": str(args.max_tx_duration_ms),
            "rx_arm_delay_ms": str(args.rx_arm_delay_ms),
            "cyclic": "1" if args.cyclic_tx else "0",
        }
        request_path = args.out_dir / "fieldmesh_iio_burst_transport_worker_request.kv"
        write_worker_xfer_request(request_path, xfer_fields)
        helper_report = server.transport_service_loop_run(
            request_path,
            max(args.timeout_ms / 1000.0 + 2.0, 3.0),
        )
        helper_transport_status = dict(
            server.status_transport_session(max(args.timeout_ms / 1000.0, 1.0))
        )
        helper_transport_service_loop_status = dict(
            server.status_transport_service_loop(max(args.timeout_ms / 1000.0, 1.0))
        )
        stdout = json.dumps(helper_report, sort_keys=True) + "\n"
        returncode = 0 if helper_report.get("ok") is True else 1
        stderr = ""
    else:
        proc = subprocess.run(helper_argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        stdout = proc.stdout.decode("utf-8", errors="replace")
        stderr = proc.stderr.decode("utf-8", errors="replace")
        returncode = proc.returncode
        helper_report = {}
        for line in stdout.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            with contextlib.suppress(json.JSONDecodeError):
                decoded = json.loads(line)
                if isinstance(decoded, dict):
                    helper_report = decoded
    helper_result = {
        "name": "iio_burst_helper",
        "returncode": returncode,
        "stdout": stdout,
        "stderr": stderr,
        "elapsed_ms": int((time.monotonic() - helper_started) * 1000),
        "argv": helper_row["argv"],
        "persistent_burst_helper": bool(getattr(args, "persistent_burst_helper", False)),
        "native_iio_burst_worker": helper_report.get("native_iio_burst_worker") is True,
        "persistent_native_iio_burst_worker": helper_report.get("persistent_native_iio_burst_worker") is True,
        "native_iio_burst_worker_lifecycle": helper_report.get("native_iio_burst_worker_lifecycle") is True,
        "native_iio_burst_worker_lifecycle_proof": helper_report.get("native_iio_burst_worker_lifecycle_proof"),
        "server_owned_xfer_loop": helper_report.get("server_owned_xfer_loop") is True,
        "server_xfer_count": helper_report.get("server_xfer_count"),
        "server_ready_event": helper_ready.get("event"),
        "server_ready_lifecycle": helper_ready.get("native_iio_burst_worker_lifecycle") is True,
        "server_ready_lifecycle_proof": helper_ready.get("native_iio_burst_worker_lifecycle_proof"),
        "server_ready_owned_xfer_loop": helper_ready.get("server_owned_xfer_loop") is True,
        "server_pid": helper_ready.get("server_pid"),
        "native_iio_burst_transport_worker": helper_report.get("native_iio_burst_transport_worker") is True,
        "native_iio_burst_transport_worker_proof": helper_report.get("native_iio_burst_transport_worker_proof"),
        "native_iio_burst_transport_session": helper_report.get("native_iio_burst_transport_session") is True,
        "native_iio_burst_transport_session_proof": helper_report.get("native_iio_burst_transport_session_proof"),
        "transport_session_start_count": helper_report.get("transport_session_start_count"),
        "transport_session_start_event": helper_transport_start.get("event"),
        "transport_session_start_proof": helper_transport_start.get("native_iio_burst_transport_session_proof"),
        "transport_session_status_event": helper_transport_status.get("event"),
        "transport_session_status_proof": helper_transport_status.get("native_iio_burst_transport_session_proof"),
        "transport_session_status_started": (
            helper_transport_status.get("native_iio_burst_transport_session") is True
        ),
        "native_iio_burst_transport_service_loop": (
            helper_report.get("native_iio_burst_transport_service_loop") is True
        ),
        "native_iio_burst_transport_service_loop_proof": helper_report.get(
            "native_iio_burst_transport_service_loop_proof"
        ),
        "transport_service_loop_start_count": helper_report.get("transport_service_loop_start_count"),
        "transport_service_loop_start_event": helper_transport_service_loop_start.get("event"),
        "transport_service_loop_start_proof": helper_transport_service_loop_start.get(
            "native_iio_burst_transport_service_loop_proof"
        ),
        "transport_service_loop_status_event": helper_transport_service_loop_status.get("event"),
        "transport_service_loop_status_proof": helper_transport_service_loop_status.get(
            "native_iio_burst_transport_service_loop_proof"
        ),
        "transport_service_loop_status_started": (
            helper_transport_service_loop_status.get("native_iio_burst_transport_service_loop") is True
        ),
        "transport_service_loop_run": helper_report.get("transport_service_loop_run") is True,
        "transport_service_loop_run_count": helper_report.get("transport_service_loop_run_count"),
        "transport_worker_request": helper_report.get("transport_worker_request") is True,
        "transport_worker_request_count": helper_report.get("transport_worker_request_count"),
        "python_xfer_field_orchestration": helper_report.get("python_xfer_field_orchestration") is True,
        "python_worker_xfer_submission": helper_report.get("python_worker_xfer_submission") is True,
        "next_boundary": helper_report.get("next_boundary"),
        "transport_worker_request_file": str(request_path) if getattr(args, "persistent_burst_helper", False) else None,
        "libiio_rx_tx_worker": helper_report.get("libiio_rx_tx_worker") is True,
        "python_iio_transport": helper_report.get("python_iio_transport") is True,
        "helper_event": helper_report.get("event"),
    }
    results.append(helper_result)
    if returncode != 0:
        detail = helper_result["stderr"].strip() or helper_result["stdout"].strip()
        raise SystemExit(f"iio_burst_helper failed: {detail}")
    results.append(
        {
            "name": "execute_live_total",
            "returncode": 0,
            "elapsed_ms": int((time.monotonic() - started) * 1000),
            "burst_helper": str(args.burst_helper),
            "persistent_burst_helper": bool(getattr(args, "persistent_burst_helper", False)),
            "native_iio_burst_worker": helper_result["native_iio_burst_worker"],
            "persistent_native_iio_burst_worker": helper_result["persistent_native_iio_burst_worker"],
            "native_iio_burst_worker_lifecycle": helper_result["native_iio_burst_worker_lifecycle"],
            "native_iio_burst_worker_lifecycle_proof": helper_result["native_iio_burst_worker_lifecycle_proof"],
            "server_owned_xfer_loop": helper_result["server_owned_xfer_loop"],
            "server_xfer_count": helper_result["server_xfer_count"],
            "native_iio_burst_transport_worker": helper_result["native_iio_burst_transport_worker"],
            "native_iio_burst_transport_worker_proof": helper_result["native_iio_burst_transport_worker_proof"],
            "native_iio_burst_transport_session": helper_result["native_iio_burst_transport_session"],
            "native_iio_burst_transport_session_proof": helper_result["native_iio_burst_transport_session_proof"],
            "transport_session_start_count": helper_result["transport_session_start_count"],
            "transport_session_start_proof": helper_result["transport_session_start_proof"],
            "transport_session_status_proof": helper_result["transport_session_status_proof"],
            "transport_session_status_started": helper_result["transport_session_status_started"],
            "native_iio_burst_transport_service_loop": helper_result[
                "native_iio_burst_transport_service_loop"
            ],
            "native_iio_burst_transport_service_loop_proof": helper_result[
                "native_iio_burst_transport_service_loop_proof"
            ],
            "transport_service_loop_start_count": helper_result["transport_service_loop_start_count"],
            "transport_service_loop_start_proof": helper_result["transport_service_loop_start_proof"],
            "transport_service_loop_status_proof": helper_result["transport_service_loop_status_proof"],
            "transport_service_loop_status_started": helper_result[
                "transport_service_loop_status_started"
            ],
            "transport_service_loop_run": helper_result["transport_service_loop_run"],
            "transport_service_loop_run_count": helper_result["transport_service_loop_run_count"],
            "transport_worker_request": helper_result["transport_worker_request"],
            "transport_worker_request_count": helper_result["transport_worker_request_count"],
            "python_xfer_field_orchestration": helper_result["python_xfer_field_orchestration"],
            "python_worker_xfer_submission": helper_result["python_worker_xfer_submission"],
            "next_boundary": helper_result["next_boundary"],
            "transport_worker_request_file": helper_result["transport_worker_request_file"],
            "libiio_rx_tx_worker": helper_result["libiio_rx_tx_worker"],
            "python_iio_transport": helper_result["python_iio_transport"],
        }
    )
    return results


def recovered_crc(frame: bytes) -> int:
    return int(iq_smoke.frame_metadata(frame).get("frame_crc", iq_smoke.frame_crc32(frame)))


def burst_crc(frame: bytes) -> int:
    return iq_smoke.frame_crc32(frame)


def run_json(cmd: list[str]) -> dict[str, Any]:
    try:
        completed = subprocess.run(cmd, check=True, text=True, capture_output=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            f"{cmd[0]} failed with rc={exc.returncode}: {exc.stderr.strip() or exc.stdout.strip()}"
        ) from exc
    last_json: dict[str, Any] | None = None
    for line in completed.stdout.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            last_json = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{cmd[0]} emitted invalid JSON: {line}") from exc
    if last_json is None:
        raise SystemExit(f"{cmd[0]} did not emit JSON")
    return last_json


def decode_capture_with_c_helper(
    plan: dict[str, Any],
    args: argparse.Namespace,
    capture_path: Path,
    smoke_report: dict[str, Any],
    modulation: str,
    samples_per_symbol: int,
    bit_repeat: int,
) -> dict[str, Any] | None:
    encoding = smoke_report.get("encoding", {})
    if encoding.get("uses_c_modem_helper") is not True:
        return None
    helper_text = encoding.get("modem_helper") or (str(args.burst_helper) if args.burst_helper else None)
    if not helper_text:
        return None
    helper = Path(helper_text)
    if not helper.exists():
        return None
    decoded_path = args.out_dir / "rx_capture_decoded_frame.bin"
    cmd = [
        str(helper),
        f"--{modulation}-decode",
        "--iq-file",
        str(capture_path),
        "--decoded-file",
        str(decoded_path),
        "--expected-frame-len",
        str(smoke_report["frame"]["bytes"]),
        "--expected-frame-crc",
        f"0x{burst_crc(Path(smoke_report['frame']['path']).read_bytes()):08x}",
        "--sample-rate-hz",
        str(smoke_report["rf_fixture"]["sample_rate_hz"]),
        "--samples-per-symbol",
        str(samples_per_symbol),
        "--bit-repeat",
        str(bit_repeat),
    ]
    if modulation == "bfsk":
        cmd.extend(
            [
                "--space-hz",
                str(int(encoding.get("bfsk_space_hz", iq_smoke.DEFAULT_BFSK_SPACE_HZ))),
                "--mark-hz",
                str(int(encoding.get("bfsk_mark_hz", iq_smoke.DEFAULT_BFSK_MARK_HZ))),
            ]
        )
    elif int(encoding.get("baseband_carrier_hz", 0)) != 0:
        cmd.extend(["--baseband-carrier-hz", str(int(encoding.get("baseband_carrier_hz", 0)))])
    try:
        decoded = run_json(cmd)
    except SystemExit as exc:
        return {"attempted": True, "ok": False, "error": str(exc), "decoder": "fieldmesh_iio_burst_xfer_c"}
    if decoded.get("ok") is not True or not decoded_path.exists():
        return {
            "attempted": True,
            "ok": False,
            "error": decoded.get("error", "C modem helper did not decode capture"),
            "capture_bytes": capture_path.stat().st_size,
            "decoder": "fieldmesh_iio_burst_xfer_c",
            "modem_helper": str(helper),
        }
    recovered = decoded_path.read_bytes()
    crc = recovered_crc(recovered)
    return {
        "attempted": True,
        "ok": crc == plan["iq_burst"]["frame_crc"],
        "capture_bytes": capture_path.stat().st_size,
        "recovered_frame_hex": recovered.hex(),
        "recovered_frame_bytes": len(recovered),
        "recovered_frame_crc": crc,
        "expected_frame_crc": plan["iq_burst"]["frame_crc"],
        "sample_offset": decoded.get("sample_offset"),
        "chip_phase": decoded.get("chip_phase"),
        "bit_start": decoded.get("bit_start"),
        "decoder": f"fieldmesh_iio_burst_xfer_c_{modulation}",
        "modem_helper": str(helper),
    }


def decode_capture(plan: dict[str, Any], args: argparse.Namespace, capture_path: Path) -> dict[str, Any]:
    started = time.monotonic()
    if not capture_path.exists():
        return {"attempted": False, "reason": "capture file missing"}
    iq = capture_path.read_bytes()
    if not iq:
        return {"attempted": False, "reason": "capture file empty"}
    smoke_report = load_json(Path(plan["iq_burst"]["report"]))
    samples_per_symbol = int(smoke_report["encoding"]["samples_per_symbol"])
    modulation = str(smoke_report["encoding"].get("modulation", "bpsk"))
    bit_repeat = int(smoke_report["encoding"].get("bit_repeat", 1))
    c_decoded = decode_capture_with_c_helper(
        plan,
        args,
        capture_path,
        smoke_report,
        modulation,
        samples_per_symbol,
        bit_repeat,
    )
    if c_decoded and c_decoded.get("ok") is True:
        c_decoded["elapsed_ms"] = int((time.monotonic() - started) * 1000)
        return c_decoded
    return {
        "attempted": True,
        "ok": False,
        "error": "C modem helper did not decode capture",
        "capture_bytes": len(iq),
        "decoder": "fieldmesh_iio_burst_xfer_c_required",
        "c_decoder": c_decoded,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    started = time.monotonic()
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
        command_results = (
            execute_live_with_helper(args, commands, capture_path)
            if args.burst_helper
            else execute_live(args, commands, capture_path)
        )
        decode = decode_capture(plan, args, capture_path)
    native_iio_burst_worker_required = bool(
        args.execute_live_rf and args.burst_helper and getattr(args, "persistent_burst_helper", False)
    )
    native_iio_burst_worker_proven = bool(
        command_results
        and any(
            result.get("name") == "iio_burst_helper"
            and result.get("returncode") == 0
            and result.get("persistent_burst_helper") is True
            and result.get("native_iio_burst_worker") is True
            and result.get("persistent_native_iio_burst_worker") is True
            and result.get("libiio_rx_tx_worker") is True
            and result.get("python_iio_transport") is False
            for result in command_results
        )
    )
    native_iio_burst_worker_lifecycle_proven = bool(
        not native_iio_burst_worker_required
        or (
            command_results
            and any(
                result.get("name") == "iio_burst_helper"
                and result.get("returncode") == 0
                and result.get("persistent_burst_helper") is True
                and result.get("persistent_native_iio_burst_worker") is True
                and result.get("native_iio_burst_worker_lifecycle") is True
                and result.get("native_iio_burst_worker_lifecycle_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1"
                and result.get("server_ready_lifecycle") is True
                and result.get("server_ready_lifecycle_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1"
                and result.get("server_owned_xfer_loop") is True
                and result.get("server_ready_owned_xfer_loop") is True
                and isinstance(result.get("server_xfer_count"), int)
                and result.get("server_xfer_count") >= 1
                for result in command_results
            )
        )
    )
    native_iio_burst_transport_worker_proven = bool(
        not native_iio_burst_worker_required
        or (
            command_results
            and any(
                result.get("name") == "iio_burst_helper"
                and result.get("returncode") == 0
                and result.get("native_iio_burst_transport_worker") is True
                and result.get("native_iio_burst_transport_worker_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1"
                and result.get("transport_worker_request") is True
                and isinstance(result.get("transport_worker_request_count"), int)
                and result.get("transport_worker_request_count") >= 1
                and result.get("python_xfer_field_orchestration") is False
                for result in command_results
            )
        )
    )
    native_iio_burst_transport_session_proven = bool(
        not native_iio_burst_worker_required
        or (
            command_results
            and any(
                result.get("name") == "iio_burst_helper"
                and result.get("returncode") == 0
                and result.get("native_iio_burst_transport_worker") is True
                and result.get("native_iio_burst_transport_worker_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1"
                and result.get("native_iio_burst_transport_session") is True
                and result.get("native_iio_burst_transport_session_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1"
                and result.get("transport_session_start_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1"
                and result.get("transport_session_status_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1"
                and result.get("transport_session_status_started") is True
                and isinstance(result.get("transport_session_start_count"), int)
                and result.get("transport_session_start_count") >= 1
                for result in command_results
            )
        )
    )
    native_iio_burst_transport_service_loop_proven = bool(
        not native_iio_burst_worker_required
        or (
            command_results
            and any(
                result.get("name") == "iio_burst_helper"
                and result.get("returncode") == 0
                and result.get("native_iio_burst_transport_worker") is True
                and result.get("native_iio_burst_transport_worker_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1"
                and result.get("native_iio_burst_transport_session") is True
                and result.get("native_iio_burst_transport_session_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1"
                and result.get("native_iio_burst_transport_service_loop") is True
                and result.get("native_iio_burst_transport_service_loop_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1"
                and result.get("transport_service_loop_start_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1"
                and result.get("transport_service_loop_status_proof")
                == "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1"
                and result.get("transport_service_loop_status_started") is True
                and result.get("transport_service_loop_run") is True
                and isinstance(result.get("transport_service_loop_start_count"), int)
                and result.get("transport_service_loop_start_count") >= 1
                and isinstance(result.get("transport_service_loop_run_count"), int)
                and result.get("transport_service_loop_run_count") >= 1
                and result.get("python_worker_xfer_submission") is False
                and result.get("next_boundary") == "native_transport_worker_autonomous_scheduler"
                for result in command_results
            )
        )
    )

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
        "cyclic_tx": bool(args.cyclic_tx),
        "cyclic_capture_periods": args.cyclic_capture_periods,
        "rx_gain_control_mode": args.rx_gain_control_mode,
        "rx_hardwaregain_db": args.rx_hardwaregain_db,
        "tx_hardwaregain_db": args.tx_hardwaregain_db,
        "skip_rf_config": bool(args.skip_rf_config),
        "burst_helper": str(args.burst_helper) if args.burst_helper else None,
        "persistent_burst_helper": bool(getattr(args, "persistent_burst_helper", False)),
        "python_modem_decode_allowed": False,
        "decode_policy": "compiled_c_modem_required",
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
        "native_iio_burst_worker_required": native_iio_burst_worker_required,
        "native_iio_burst_worker_proven": native_iio_burst_worker_proven,
        "native_iio_burst_worker_lifecycle_proven": native_iio_burst_worker_lifecycle_proven,
        "native_iio_burst_transport_worker_proven": native_iio_burst_transport_worker_proven,
        "native_iio_burst_transport_session_proven": native_iio_burst_transport_session_proven,
        "native_iio_burst_transport_service_loop_proven": (
            native_iio_burst_transport_service_loop_proven
        ),
        "decode": decode,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
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
    parser.add_argument("--cyclic-tx", action="store_true")
    parser.add_argument("--cyclic-capture-periods", type=int, default=2)
    parser.add_argument("--rx-gain-control-mode")
    parser.add_argument("--rx-hardwaregain-db", type=float)
    parser.add_argument("--tx-hardwaregain-db", type=float)
    parser.add_argument("--skip-rf-config", action="store_true")
    parser.add_argument("--burst-helper", type=Path)
    parser.add_argument("--persistent-burst-helper", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0 if report.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
