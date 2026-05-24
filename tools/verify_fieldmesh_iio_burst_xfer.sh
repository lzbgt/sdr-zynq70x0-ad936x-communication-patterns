#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-burst-xfer-verify"
cc="${CC:-cc}"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$cc" -std=c99 -Wall -Wextra -Werror \
  "$repo_root/tools/fieldmesh_iio_burst_xfer.c" \
  -liio -lpthread -lm \
  -o "$work_dir/fieldmesh_iio_burst_xfer"

"$work_dir/fieldmesh_iio_burst_xfer" --help >"$work_dir/help.txt"
if ! grep -q -- "--tx-uri" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing CLI contract" >&2
  exit 1
fi
if ! grep -q -- "--server" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing persistent server contract" >&2
  exit 1
fi
if ! grep -q -- "--native-worker-self-test" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing native IIO worker contract" >&2
  exit 1
fi
if ! grep -q -- "--bfsk-encode" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C BFSK modem contract" >&2
  exit 1
fi
if ! grep -q -- "--bpsk-encode" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C BPSK modem contract" >&2
  exit 1
fi
if ! grep -q -- "--bpsk-benchmark" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C BPSK benchmark contract" >&2
  exit 1
fi
if ! grep -q -- "--bfsk-benchmark" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C BFSK benchmark contract" >&2
  exit 1
fi
if ! grep -q -- "--baseband-carrier-hz" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C BPSK carrier contract" >&2
  exit 1
fi

"$work_dir/fieldmesh_iio_burst_xfer" --native-worker-self-test \
  >"$work_dir/native_worker_self_test.json"
python3 - "$work_dir/native_worker_self_test.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iio_burst_native_worker_self_test" or report.get("ok") is not True:
    raise SystemExit(f"C native IIO worker self-test failed: {report}")
if report.get("proof") != "FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1":
    raise SystemExit(f"C native IIO worker proof token drifted: {report}")
for key in ("native_iio_burst_worker", "persistent_server_supported", "libiio_rx_tx_worker", "same_process_rx_tx"):
    if report.get(key) is not True:
        raise SystemExit(f"C native IIO worker did not prove {key}: {report}")
for key in ("python_iio_transport", "reads_hardware", "writes_hardware", "starts_rf_tx"):
    if report.get(key) is not False:
        raise SystemExit(f"C native IIO worker self-test must be read/write-free for {key}: {report}")
PY

"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-self-test \
  >"$work_dir/bpsk_self_test.json"
python3 - "$work_dir/bpsk_self_test.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_bpsk_modem_self_test" or report.get("ok") is not True:
    raise SystemExit(f"C BPSK self-test failed: {report}")
for key in ("base_ok", "phase_recovery_ok", "carrier_ok"):
    if report.get(key) is not True:
        raise SystemExit(f"C BPSK self-test did not prove {key}: {report}")
if report.get("baseband_carrier_hz") != 125000:
    raise SystemExit(f"C BPSK self-test did not report carrier coverage: {report}")
if report.get("frame_bytes", 0) <= 0 or report.get("iq_bytes", 0) <= 0:
    raise SystemExit(f"C BPSK self-test did not report useful byte counts: {report}")
PY

"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-self-test \
  >"$work_dir/bfsk_self_test.json"
python3 - "$work_dir/bfsk_self_test.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_bfsk_modem_self_test" or report.get("ok") is not True:
    raise SystemExit(f"C BFSK self-test failed: {report}")
if report.get("frame_bytes", 0) <= 0 or report.get("iq_bytes", 0) <= 0:
    raise SystemExit(f"C BFSK self-test did not report useful byte counts: {report}")
PY

cp "$repo_root/resources/fieldmesh/vectors/frame_000.bin" "$work_dir/frame.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-benchmark \
  --frame-file "$work_dir/frame.bin" \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  --iterations 50 \
  >"$work_dir/bpsk_benchmark.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-benchmark \
  --frame-file "$work_dir/frame.bin" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  --iterations 50 \
  >"$work_dir/bfsk_benchmark.json"
python3 - "$work_dir/bpsk_benchmark.json" "$work_dir/bfsk_benchmark.json" <<'PY'
import json
import sys
from pathlib import Path

for path, event in (
    (Path(sys.argv[1]), "fieldmesh_bpsk_modem_benchmark"),
    (Path(sys.argv[2]), "fieldmesh_bfsk_modem_benchmark"),
):
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("event") != event or report.get("ok") is not True:
        raise SystemExit(f"C modem benchmark failed: {report}")
    if report.get("hot_path_language") != "c" or report.get("uses_python_modem") is not False:
        raise SystemExit(f"C modem benchmark left native path: {report}")
    if report.get("iterations") != 50:
        raise SystemExit(f"C modem benchmark iteration count drifted: {report}")
    if report.get("encode_frame_kbps", 0) < 100 or report.get("decode_frame_kbps", 0) < 100:
        raise SystemExit(f"C modem benchmark under M1-scale service-rate floor: {report}")
PY
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/bpsk_frame.iq" \
  --samples-per-symbol 16 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_frame.iq" \
  --decoded-file "$work_dir/bpsk_decoded.bin" \
  --samples-per-symbol 16 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_decoded.bin"
python3 - "$work_dir/bpsk_frame.iq" "$work_dir/bpsk_rotated_frame.iq" <<'PY'
import struct
import sys
from pathlib import Path

iq = Path(sys.argv[1]).read_bytes()
out = bytearray()
for offset in range(0, len(iq), 4):
    i, q = struct.unpack_from("<hh", iq, offset)
    out.extend(struct.pack("<hh", -q, i))
Path(sys.argv[2]).write_bytes(out)
PY
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_rotated_frame.iq" \
  --decoded-file "$work_dir/bpsk_rotated_decoded.bin" \
  --samples-per-symbol 16 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_rotated_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_rotated_decoded.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/bpsk_carrier_frame.iq" \
  --sample-rate-hz 1000000 \
  --baseband-carrier-hz 125000 \
  --samples-per-symbol 16 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_carrier_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_carrier_frame.iq" \
  --decoded-file "$work_dir/bpsk_carrier_decoded.bin" \
  --sample-rate-hz 1000000 \
  --baseband-carrier-hz 125000 \
  --samples-per-symbol 16 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_carrier_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_carrier_decoded.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/frame.iq" \
  --samples-per-symbol 32 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-decode \
  --iq-file "$work_dir/frame.iq" \
  --decoded-file "$work_dir/decoded.bin" \
  --samples-per-symbol 32 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/decoded.bin"

python3 - "$work_dir/frame.bin" "$work_dir/bad_frame.bin" "$work_dir/frame_crc.txt" <<'PY'
import sys
import zlib
from pathlib import Path

frame = Path(sys.argv[1]).read_bytes()
bad = bytearray(frame)
bad[-1] ^= 0x01
Path(sys.argv[2]).write_bytes(bad)
Path(sys.argv[3]).write_text(f"0x{zlib.crc32(frame) & 0xffffffff:08x}\n", encoding="ascii")
PY
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/bad_frame.bin" \
  --iq-file "$work_dir/bpsk_bad_frame.iq" \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_bad_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/bpsk_good_frame.iq" \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_good_encode.json"
python3 - "$work_dir/bpsk_bad_frame.iq" "$work_dir/bpsk_good_frame.iq" "$work_dir/bpsk_combined.iq" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[3]).write_bytes(Path(sys.argv[1]).read_bytes() + Path(sys.argv[2]).read_bytes())
PY
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_combined.iq" \
  --decoded-file "$work_dir/bpsk_combined_decoded.bin" \
  --expected-frame-len "$(wc -c <"$work_dir/frame.bin")" \
  --expected-frame-crc "$(cat "$work_dir/frame_crc.txt")" \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_decode_after_bad_crc.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_combined_decoded.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-encode \
  --frame-file "$work_dir/bad_frame.bin" \
  --iq-file "$work_dir/bad_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_bad_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/good_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_good_encode.json"
python3 - "$work_dir/bad_frame.iq" "$work_dir/good_frame.iq" "$work_dir/combined.iq" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[3]).write_bytes(Path(sys.argv[1]).read_bytes() + Path(sys.argv[2]).read_bytes())
PY
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-decode \
  --iq-file "$work_dir/combined.iq" \
  --decoded-file "$work_dir/combined_decoded.bin" \
  --expected-frame-len "$(wc -c <"$work_dir/frame.bin")" \
  --expected-frame-crc "$(cat "$work_dir/frame_crc.txt")" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 8 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_decode_after_bad_crc.json"
cmp "$work_dir/frame.bin" "$work_dir/combined_decoded.bin"
python3 - "$work_dir/bpsk_encode.json" "$work_dir/bpsk_decode.json" <<'PY'
import json
import sys
from pathlib import Path

encode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
decode = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if encode.get("event") != "fieldmesh_bpsk_modem_encode" or encode.get("ok") is not True:
    raise SystemExit(f"C BPSK encode failed: {encode}")
if decode.get("event") != "fieldmesh_bpsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C BPSK decode failed: {decode}")
if encode.get("frame_bytes") != decode.get("frame_bytes"):
    raise SystemExit(f"C BPSK encode/decode byte counts differ: {encode} {decode}")
PY

python3 - "$work_dir/bpsk_rotated_decode.json" <<'PY'
import json
import sys
from pathlib import Path

decode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if decode.get("event") != "fieldmesh_bpsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C coherent BPSK decoder did not recover rotated IQ: {decode}")
print('{"event":"fieldmesh_bpsk_coherent_phase_check","ok":true}')
PY

python3 - "$work_dir/bpsk_carrier_encode.json" "$work_dir/bpsk_carrier_decode.json" <<'PY'
import json
import sys
from pathlib import Path

encode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
decode = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if encode.get("event") != "fieldmesh_bpsk_modem_encode" or encode.get("ok") is not True:
    raise SystemExit(f"C carrier BPSK encode failed: {encode}")
if decode.get("event") != "fieldmesh_bpsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C carrier BPSK decode failed: {decode}")
if encode.get("baseband_carrier_hz") != 125000 or decode.get("baseband_carrier_hz") != 125000:
    raise SystemExit(f"C carrier BPSK did not report carrier: {encode} {decode}")
PY

python3 - "$work_dir/bpsk_decode_after_bad_crc.json" <<'PY'
import json
import sys
from pathlib import Path

decode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if decode.get("event") != "fieldmesh_bpsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C BPSK decoder did not recover after CRC-wrong candidate: {decode}")
if decode.get("bit_start", 0) <= 0:
    raise SystemExit(f"C BPSK decoder did not skip the leading bad candidate: {decode}")
PY
python3 - "$work_dir/bfsk_encode.json" "$work_dir/bfsk_decode.json" <<'PY'
import json
import sys
from pathlib import Path

encode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
decode = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if encode.get("event") != "fieldmesh_bfsk_modem_encode" or encode.get("ok") is not True:
    raise SystemExit(f"C BFSK encode failed: {encode}")
if decode.get("event") != "fieldmesh_bfsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C BFSK decode failed: {decode}")
if encode.get("frame_bytes") != decode.get("frame_bytes"):
    raise SystemExit(f"C BFSK encode/decode byte counts differ: {encode} {decode}")
PY

python3 - "$work_dir/bfsk_decode_after_bad_crc.json" <<'PY'
import json
import sys
from pathlib import Path

decode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if decode.get("event") != "fieldmesh_bfsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C BFSK decoder did not recover after CRC-wrong candidate: {decode}")
if decode.get("bit_start", 0) <= 0:
    raise SystemExit(f"C BFSK decoder did not skip the leading bad candidate: {decode}")
PY

if "$work_dir/fieldmesh_iio_burst_xfer" \
  --tx-uri ip:127.0.0.1 \
  --rx-uri ip:127.0.0.1 \
  --tx-device cf-ad9361-dds-core-lpc \
  --rx-device cf-ad9361-lpc \
  --tx-file "$work_dir/missing.iq" \
  --rx-file "$work_dir/rx.iq" \
  --tx-samples 8 \
  --rx-samples 8 \
  >/dev/null 2>"$work_dir/missing_context.err"; then
  echo "fieldmesh_iio_burst_xfer unexpectedly succeeded without a live IIO context" >&2
  exit 1
fi

python3 - "$repo_root/tools/fieldmesh_iio_burst_xfer.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "iio_create_context_from_uri",
    "iio_context_set_timeout",
    "iio_device_find_channel",
    "iio_channel_enable",
    "iio_device_create_buffer",
    "iio_buffer_refill",
    "iio_buffer_push",
    "pthread_create",
    "fieldmesh_iio_burst_xfer_server",
    "fieldmesh_iio_burst_native_worker_self_test",
    "FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1",
    "native_iio_burst_worker",
    "libiio_rx_tx_worker",
    "python_iio_transport",
    "fieldmesh_bpsk_modem_encode",
    "fieldmesh_bpsk_modem_decode",
    "fieldmesh_bpsk_modem_self_test",
    "phase_recovery_ok",
    "carrier_ok",
    "--baseband-carrier-hz",
    "bpsk_decode_frame_coherent",
    "decode_bpsk_hard_bits",
    "fieldmesh_bfsk_modem_encode",
    "fieldmesh_bfsk_modem_decode",
    "fieldmesh_bfsk_modem_self_test",
    "expected_frame_crc",
    "build_tone_prefixes",
    "prefix_tone_energy",
    "recover_frame_from_bits",
    "FMBATCH1",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing libiio helper primitives: {missing}")
print('{"event":"fieldmesh_iio_burst_xfer_check","ok":true}')
PY
