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

python3 - "$repo_root" "$repo_root/resources/fieldmesh/vectors/frame_000.bin" <<'PY'
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
sys.path.insert(0, str(repo_root / "tools"))
import fieldmesh_iq_burst_smoke as iq  # noqa: E402

frame = Path(sys.argv[2]).read_bytes()
bad_frame = bytearray(frame)
bad_frame[-1] ^= 0x01
sample_rate_hz = 1_000_000
samples_per_symbol = 8
bit_repeat = 2
bad_iq = iq.encode_bfsk_iq(
    iq.burst_payload(bytes(bad_frame)),
    samples_per_symbol,
    sample_rate_hz=sample_rate_hz,
    space_hz=iq.DEFAULT_BFSK_SPACE_HZ,
    mark_hz=iq.DEFAULT_BFSK_MARK_HZ,
    bit_repeat=bit_repeat,
)
good_iq = iq.encode_bfsk_iq(
    iq.burst_payload(frame),
    samples_per_symbol,
    sample_rate_hz=sample_rate_hz,
    space_hz=iq.DEFAULT_BFSK_SPACE_HZ,
    mark_hz=iq.DEFAULT_BFSK_MARK_HZ,
    bit_repeat=bit_repeat,
)
decoded = iq.decode_bfsk_iq(
    bad_iq + good_iq,
    samples_per_symbol,
    sample_rate_hz=sample_rate_hz,
    space_hz=iq.DEFAULT_BFSK_SPACE_HZ,
    mark_hz=iq.DEFAULT_BFSK_MARK_HZ,
    expected_frame_len=len(frame),
    expected_frame_crc=iq.frame_crc32(frame),
    bit_repeat=bit_repeat,
)
if decoded.get("ok") is not True or decoded.get("recovered") != frame:
    raise SystemExit(f"BFSK decoder did not skip CRC-wrong sync candidate: {decoded}")
print('{"event":"fieldmesh_bfsk_crc_candidate_check","ok":true}')
PY

if "$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$out_dir/negative" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  >/dev/null 2>&1; then
  echo "IQ burst smoke accepted missing authorized RF-path guard" >&2
  exit 1
fi
