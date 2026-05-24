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

python3 - "$out_dir/fieldmesh_iq_burst_smoke.json" "$out_dir/modem_helper.txt" <<'PY'
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
if report["encoding"].get("uses_c_modem_helper") is not True:
    raise SystemExit("IQ burst smoke did not use the C modem helper")
if report["encoding"].get("uses_python_modem") is not False:
    raise SystemExit("IQ burst smoke must not use Python modem primitives by default")
if report["encoding"].get("modem_helper_event_encode") != "fieldmesh_bpsk_modem_encode":
    raise SystemExit("IQ burst smoke missing C BPSK encode evidence")
if report["encoding"].get("modem_helper_event_decode") != "fieldmesh_bpsk_modem_decode":
    raise SystemExit("IQ burst smoke missing C BPSK decode evidence")
iq_file = Path(report["encoding"]["iq_file"])
if not iq_file.exists() or iq_file.stat().st_size <= 0:
    raise SystemExit("missing IQ sample output")
source = Path("tools/fieldmesh_iq_burst_smoke.py").read_text(encoding="utf-8")
if "--python-modem" not in source or "run_c_modem_roundtrip" not in source:
    raise SystemExit("IQ burst smoke must expose explicit Python fallback and C modem default")
Path(sys.argv[2]).write_text(str(report["encoding"]["modem_helper"]), encoding="utf-8")
print(json.dumps({
    "event": "fieldmesh_iq_burst_smoke_check",
    "ok": True,
    "iq_samples": report["encoding"]["iq_samples"],
    "fixture_attenuation_db": report["rf_fixture"]["fixture_attenuation_db"],
}, sort_keys=True))
PY

carrier_dir="$out_dir/carrier"
mkdir -p "$carrier_dir"
"$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$carrier_dir" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --samples-per-symbol 8 \
  --baseband-carrier-hz 125000 \
  --conducted-or-shielded \
  > "$carrier_dir/stdout.json"
python3 - "$carrier_dir/fieldmesh_iq_burst_smoke.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True:
    raise SystemExit(f"bad carrier IQ burst report: {report}")
if report["encoding"].get("uses_c_modem_helper") is not True:
    raise SystemExit("carrier IQ burst smoke did not use the C modem helper")
if report["encoding"].get("uses_python_modem") is not False:
    raise SystemExit("carrier IQ burst smoke must not use Python modem primitives")
if report["encoding"].get("baseband_carrier_hz") != 125000:
    raise SystemExit(f"carrier IQ burst report lost carrier metadata: {report}")
if report["decode"].get("recovered_frame_match") is not True:
    raise SystemExit(f"carrier IQ burst decode did not recover frame: {report}")
print(json.dumps({
    "event": "fieldmesh_iq_burst_smoke_carrier_c_modem_check",
    "ok": True,
    "baseband_carrier_hz": report["encoding"]["baseband_carrier_hz"],
}, sort_keys=True))
PY

modem_helper="$(cat "$out_dir/modem_helper.txt")"
python3 - "$repo_root/resources/fieldmesh/vectors/frame_000.bin" "$out_dir/bad_frame.bin" "$out_dir/frame_crc.txt" <<'PY'
import sys
import zlib
from pathlib import Path

frame = Path(sys.argv[1]).read_bytes()
bad_frame = bytearray(frame)
bad_frame[-1] ^= 0x01
Path(sys.argv[2]).write_bytes(bad_frame)
Path(sys.argv[3]).write_text(f"0x{zlib.crc32(frame) & 0xffffffff:08x}\n", encoding="ascii")
PY
"$modem_helper" --bfsk-encode \
  --frame-file "$out_dir/bad_frame.bin" \
  --iq-file "$out_dir/bad_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$out_dir/bad_bfsk_encode.json"
"$modem_helper" --bfsk-encode \
  --frame-file "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --iq-file "$out_dir/good_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$out_dir/good_bfsk_encode.json"
python3 - "$out_dir/bad_frame.iq" "$out_dir/good_frame.iq" "$out_dir/combined.iq" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[3]).write_bytes(Path(sys.argv[1]).read_bytes() + Path(sys.argv[2]).read_bytes())
PY
"$modem_helper" --bfsk-decode \
  --iq-file "$out_dir/combined.iq" \
  --decoded-file "$out_dir/combined_decoded.bin" \
  --expected-frame-len "$(wc -c <"$repo_root/resources/fieldmesh/vectors/frame_000.bin")" \
  --expected-frame-crc "$(cat "$out_dir/frame_crc.txt")" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$out_dir/bfsk_decode_after_bad_crc.json"
cmp "$repo_root/resources/fieldmesh/vectors/frame_000.bin" "$out_dir/combined_decoded.bin"
python3 - "$out_dir/bfsk_decode_after_bad_crc.json" <<'PY'
import json
import sys
from pathlib import Path

decoded = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if decoded.get("event") != "fieldmesh_bfsk_modem_decode" or decoded.get("ok") is not True:
    raise SystemExit(f"C BFSK decoder did not skip CRC-wrong sync candidate: {decoded}")
if decoded.get("bit_start", 0) <= 0:
    raise SystemExit(f"C BFSK decoder did not skip the leading bad candidate: {decoded}")
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
