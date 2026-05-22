#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

python3 - "$repo_root" "$work_dir" <<'PY'
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
work = Path(sys.argv[2])
script = repo / "tools/diagnose_z103_recovery_state.sh"
text = script.read_text(encoding="utf-8")

required_tokens = [
    "board_ip=\"${BOARD_IP:-${1:-192.168.3.1}}\"",
    "fieldmesh_set_jtag_defaults z103",
    "safe_to_attempt_jtag_boot",
    "requires_physical_power_cycle",
    '"writes_flash": False',
    '"starts_rf_tx": False',
    "DIAGNOSE_PLUTO_USB_REACHABILITY_SH",
    "PROBE_OPENOCD_JTAG_SH",
    "PROBE_OPENOCD_ZYNQ_DAP_HALT_SH",
]
missing = [token for token in required_tokens if token not in text]
if missing:
    raise SystemExit("diagnose_z103_recovery_state.sh missing tokens: " + ", ".join(missing))

def write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)

usb = work / "usb.sh"
jtag = work / "jtag.sh"
dap_fail = work / "dap_fail.sh"
dap_pass = work / "dap_pass.sh"

write_exec(
    usb,
    """#!/usr/bin/env bash
echo usb_diag "$@"
exit 0
""",
)
write_exec(
    jtag,
    """#!/usr/bin/env bash
echo "JTAG tap: zynq.cpu tap/device found"
exit 0
""",
)
write_exec(
    dap_fail,
    """#!/usr/bin/env bash
if [[ -n "${OUT:-}" ]]; then
  printf '%s\\n' '{"classification":"dap_dscr_halt_timeout","requires_physical_power_cycle":true,"ok":false}' >"$OUT"
fi
echo "timeout waiting for DSCR bit change"
exit 1
""",
)
write_exec(
    dap_pass,
    """#!/usr/bin/env bash
if [[ -n "${OUT:-}" ]]; then
  printf '%s\\n' '{"classification":"dap_halt_ok","requires_physical_power_cycle":false,"ok":true}' >"$OUT"
fi
echo "target halted in ARM state"
exit 0
""",
)

base_env = os.environ.copy()
base_env.update(
    {
        "RUN_USB": "0",
        "RUN_JTAG": "1",
        "RUN_DAP": "1",
        "PROBE_OPENOCD_JTAG_SH": str(jtag),
        "DIAGNOSE_PLUTO_USB_REACHABILITY_SH": str(usb),
    }
)

fail_dir = work / "fail"
fail_env = base_env.copy()
fail_env.update(
    {
        "OUT_DIR": str(fail_dir),
        "PROBE_OPENOCD_ZYNQ_DAP_HALT_SH": str(dap_fail),
    }
)
fail = subprocess.run(
    [str(script)],
    cwd=repo,
    env=fail_env,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if fail.returncode == 0:
    raise SystemExit("DAP failure case unexpectedly passed")
fail_report = json.loads((fail_dir / "summary.json").read_text(encoding="utf-8"))
if fail_report["safe_to_attempt_jtag_boot"]:
    raise SystemExit("failure report incorrectly allowed JTAG boot")
if fail_report["dap_classification"] != "dap_dscr_halt_timeout":
    raise SystemExit(f"unexpected DAP classification: {fail_report['dap_classification']}")
if not fail_report["requires_physical_power_cycle"]:
    raise SystemExit("failure report did not preserve physical power-cycle requirement")
if fail_report["writes_flash"] or fail_report["starts_rf_tx"]:
    raise SystemExit("diagnostic report must remain non-flashing and RF-silent")

pass_dir = work / "pass"
pass_env = base_env.copy()
pass_env.update(
    {
        "OUT_DIR": str(pass_dir),
        "PROBE_OPENOCD_ZYNQ_DAP_HALT_SH": str(dap_pass),
    }
)
passed = subprocess.run(
    [str(script)],
    cwd=repo,
    env=pass_env,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if passed.returncode != 0:
    raise SystemExit(
        "DAP pass case failed\nstdout:\n"
        + passed.stdout
        + "\nstderr:\n"
        + passed.stderr
    )
pass_report = json.loads((pass_dir / "summary.json").read_text(encoding="utf-8"))
if not pass_report["safe_to_attempt_jtag_boot"]:
    raise SystemExit("pass report did not allow JTAG boot")
if pass_report["ftdi_serial"] != "CKQCQFHQPUJB":
    raise SystemExit(f"Z103 FTDI serial default mismatch: {pass_report['ftdi_serial']}")

print("fieldmesh_z103_recovery_state=pass")
PY
