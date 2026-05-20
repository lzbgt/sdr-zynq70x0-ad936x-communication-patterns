#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/gnss-timepulse-plan-verify"

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" plan > "$out_dir/plan.json"

python3 - "$repo_root" "$out_dir/plan.json" "$out_dir/capture.bin" <<'PY'
import json
import struct
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
sys.path.insert(0, str(repo_root / "tools"))
from fieldmesh_gnss_timepulse_plan import TP_KEYS, ubx_frame  # noqa: E402

plan_path = Path(sys.argv[2])
capture_path = Path(sys.argv[3])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
if plan.get("event") != "fieldmesh_gnss_timepulse_plan" or plan.get("ok") is not True:
    raise SystemExit(f"bad plan header: {plan!r}")
goal = plan.get("timepulse_goal", {})
if goal.get("tp1_enabled") is not True:
    raise SystemExit(f"TP1 should be enabled in the planned config: {goal!r}")
if goal.get("period_us") != 1_000_000 or goal.get("length_us") != 100_000:
    raise SystemExit(f"unexpected default PPS shape: {goal!r}")
if goal.get("timegrid") != "gps" or goal.get("rising_edge") is not True:
    raise SystemExit(f"unexpected default PPS timing base/polarity: {goal!r}")
if plan.get("writes_hardware") is not False:
    raise SystemExit(f"plan must be non-live: {plan!r}")
if plan.get("valset_layers") != ["ram"]:
    raise SystemExit(f"plan must default to RAM-only receiver config: {plan!r}")
if not plan.get("valget_checksum_valid") or not plan.get("valset_checksum_valid"):
    raise SystemExit(f"generated UBX checksums were not valid: {plan!r}")
if not plan.get("valget_frame_hex", "").startswith("b562068b"):
    raise SystemExit(f"VALGET frame has wrong class/id: {plan['valget_frame_hex']}")
if not plan.get("valset_frame_hex", "").startswith("b562068a"):
    raise SystemExit(f"VALSET frame has wrong class/id: {plan['valset_frame_hex']}")
settings = {row["name"]: row["value"] for row in plan.get("settings", [])}
expected = {
    "CFG-TP-PULSE_DEF": 0,
    "CFG-TP-PULSE_LENGTH_DEF": 1,
    "CFG-TP-PERIOD_TP1": 1_000_000,
    "CFG-TP-PERIOD_LOCK_TP1": 1_000_000,
    "CFG-TP-LEN_TP1": 100_000,
    "CFG-TP-LEN_LOCK_TP1": 100_000,
    "CFG-TP-TP1_ENA": True,
    "CFG-TP-SYNC_GNSS_TP1": True,
    "CFG-TP-USE_LOCKED_TP1": True,
    "CFG-TP-ALIGN_TO_TOW_TP1": True,
    "CFG-TP-POL_TP1": True,
    "CFG-TP-TIMEGRID_TP1": 1,
}
if settings != expected:
    raise SystemExit(f"unexpected TIMEPULSE settings: {settings!r}")

payload = struct.pack("<BBH", 1, 0, 0)
for name, value in expected.items():
    key = TP_KEYS[name]
    payload += struct.pack("<I", key.key_id)
    if isinstance(value, bool):
        payload += bytes((1 if value else 0,))
    elif key.value_type == "U4":
        payload += struct.pack("<I", value)
    else:
        payload += bytes((value,))
capture_path.write_bytes(ubx_frame(0x06, 0x8B, payload))
PY

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
  --capture "$out_dir/capture.bin" > "$out_dir/parsed.json"

python3 - "$out_dir/parsed.json" <<'PY'
import json
import sys
from pathlib import Path

parsed = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if parsed.get("event") != "fieldmesh_gnss_timepulse_parse" or parsed.get("ok") is not True:
    raise SystemExit(f"bad parse header: {parsed!r}")
if parsed.get("frame_count") != 1 or parsed.get("tp_item_count") != 12:
    raise SystemExit(f"unexpected parsed item counts: {parsed!r}")
items = {row["name"]: row["value"] for row in parsed.get("tp_items", [])}
if items.get("CFG-TP-TP1_ENA") is not True:
    raise SystemExit(f"TP1 enable was not decoded: {items!r}")
if items.get("CFG-TP-LEN_TP1") != 100_000:
    raise SystemExit(f"pulse length was not decoded: {items!r}")
if items.get("CFG-TP-TIMEGRID_TP1") != 1:
    raise SystemExit(f"timegrid was not decoded: {items!r}")
frame = parsed["frames"][0]
if frame.get("checksum_valid") is not True:
    raise SystemExit(f"valid synthetic frame was not accepted: {frame!r}")
analysis = parsed.get("timepulse_analysis", {})
if analysis.get("pps_possible_without_gnss_lock") is not True:
    raise SystemExit(f"synthetic unlocked PPS should be possible: {analysis!r}")
if analysis.get("blockers"):
    raise SystemExit(f"synthetic TIMEPULSE should have no readiness blockers: {analysis!r}")
PY

python3 - "$repo_root" "$out_dir/capture-unlocked-zero.bin" <<'PY'
import struct
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
sys.path.insert(0, str(repo_root / "tools"))
from fieldmesh_gnss_timepulse_plan import TP_KEYS, ubx_frame  # noqa: E402

values = {
    "CFG-TP-PULSE_DEF": 0,
    "CFG-TP-PULSE_LENGTH_DEF": 1,
    "CFG-TP-PERIOD_TP1": 1_000_000,
    "CFG-TP-PERIOD_LOCK_TP1": 1_000_000,
    "CFG-TP-LEN_TP1": 0,
    "CFG-TP-LEN_LOCK_TP1": 100_000,
    "CFG-TP-TP1_ENA": True,
    "CFG-TP-SYNC_GNSS_TP1": True,
    "CFG-TP-USE_LOCKED_TP1": True,
    "CFG-TP-ALIGN_TO_TOW_TP1": True,
    "CFG-TP-POL_TP1": True,
    "CFG-TP-TIMEGRID_TP1": 0,
}
payload = struct.pack("<BBH", 1, 0, 0)
for name, value in values.items():
    key = TP_KEYS[name]
    payload += struct.pack("<I", key.key_id)
    if isinstance(value, bool):
        payload += bytes((1 if value else 0,))
    elif key.value_type == "U4":
        payload += struct.pack("<I", value)
    else:
        payload += bytes((value,))
Path(sys.argv[2]).write_bytes(ubx_frame(0x06, 0x8B, payload))
PY

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
  --capture "$out_dir/capture-unlocked-zero.bin" > "$out_dir/parsed-unlocked-zero.json"

python3 - "$out_dir/parsed-unlocked-zero.json" <<'PY'
import json
import sys
from pathlib import Path

parsed = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
analysis = parsed.get("timepulse_analysis", {})
if analysis.get("pps_possible_without_gnss_lock") is not False:
    raise SystemExit(f"zero unlocked length should block no-lock PPS: {analysis!r}")
if analysis.get("pps_possible_with_gnss_lock") is not True:
    raise SystemExit(f"locked PPS should remain possible: {analysis!r}")
if "gnss_timepulse_unlocked_pulse_length_zero" not in analysis.get("blockers", []):
    raise SystemExit(f"zero unlocked length blocker was not surfaced: {analysis!r}")
PY

python3 - "$out_dir/capture.bin" "$out_dir/capture-bad-checksum.bin" <<'PY'
import sys
from pathlib import Path

data = bytearray(Path(sys.argv[1]).read_bytes())
data[-1] ^= 0x01
Path(sys.argv[2]).write_bytes(data)
PY

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
  --capture "$out_dir/capture-bad-checksum.bin" > "$out_dir/parsed-bad-checksum.json"

python3 - "$out_dir/parsed-bad-checksum.json" <<'PY'
import json
import sys
from pathlib import Path

parsed = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if parsed.get("tp_item_count") != 0:
    raise SystemExit(f"checksum-invalid frame produced TP items: {parsed!r}")
analysis = parsed.get("timepulse_analysis", {})
if "gnss_timepulse_cfg_tp_not_observed" not in analysis.get("blockers", []):
    raise SystemExit(f"missing no-valid-TP-frame blocker: {analysis!r}")
if parsed.get("frames", [{}])[0].get("parse_error") != "checksum_invalid":
    raise SystemExit(f"checksum error was not retained: {parsed!r}")
PY

if "$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" plan \
  --set-layers ram,bbr > "$out_dir/persistent.json"; then
  python3 - "$out_dir/persistent.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if plan.get("safety", {}).get("persistent_layers") != ["bbr"]:
    raise SystemExit(f"BBR persistence was not flagged: {plan!r}")
PY
else
  echo "TIMEPULSE planner rejected a valid RAM+BBR plan" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" plan \
  --length-us 1000000 > "$out_dir/bad-length.json" 2>"$out_dir/bad-length.err"; then
  echo "TIMEPULSE planner accepted a pulse length equal to period" >&2
  exit 1
fi

echo "fieldmesh_gnss_timepulse_plan=pass"
