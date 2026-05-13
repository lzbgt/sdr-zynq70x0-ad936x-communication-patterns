#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/iq-burst-smoke"

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$out_dir" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --samples-per-symbol 8 \
  --conducted-or-shielded \
  > "$out_dir/stdout.json"

python3 - "$out_dir/fieldmesh_iq_burst_smoke.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iq_burst_smoke" or report.get("ok") is not True:
    raise SystemExit(f"bad IQ burst report: {report}")
if report["safety"]["starts_rf_tx"] is not False:
    raise SystemExit("IQ burst smoke must not start RF TX")
if report["safety"]["opens_iio_buffers"] is not False:
    raise SystemExit("IQ burst smoke must not open IIO buffers")
if report["decode"]["recovered_frame_match"] is not True:
    raise SystemExit("IQ burst decode did not recover frame")
if report["frame"]["traffic_class"] != "C0" or report["frame"]["mode"] != "scheduled":
    raise SystemExit("unexpected FieldMesh vector metadata")
iq_file = Path(report["encoding"]["iq_file"])
if not iq_file.exists() or iq_file.stat().st_size <= 0:
    raise SystemExit("missing IQ sample output")
print(json.dumps({
    "event": "fieldmesh_iq_burst_smoke_check",
    "ok": True,
    "iq_samples": report["encoding"]["iq_samples"],
    "fixture_attenuation_db": report["rf_fixture"]["fixture_attenuation_db"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$out_dir/negative" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  >/dev/null 2>&1; then
  echo "IQ burst smoke accepted missing conducted/shielded guard" >&2
  exit 1
fi
