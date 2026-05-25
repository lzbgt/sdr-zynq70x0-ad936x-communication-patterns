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
if ! grep -q -- "--qpsk-encode" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C QPSK modem contract" >&2
  exit 1
fi
if ! grep -q -- "--qpsk-benchmark" "$work_dir/help.txt"; then
  echo "fieldmesh_iio_burst_xfer help output is missing C QPSK benchmark contract" >&2
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
for key in (
    "native_iio_burst_worker",
    "persistent_server_supported",
    "persistent_worker_lifecycle_supported",
    "server_owned_xfer_loop_supported",
    "native_iio_burst_transport_worker_supported",
    "native_iio_burst_transport_session_supported",
    "native_iio_burst_transport_service_loop_supported",
    "native_iio_burst_transport_scheduler_supported",
    "native_iio_burst_transport_autonomous_loop_supported",
    "native_iio_burst_transport_background_daemon_supported",
    "native_iio_burst_integrated_rf_service_daemon_supported",
    "native_iio_burst_state_daemon_transport_queue_supported",
    "native_iio_burst_state_daemon_transport_lifecycle_supported",
    "native_iio_burst_state_daemon_transport_modem_profile_supported",
    "libiio_rx_tx_worker",
    "same_process_rx_tx",
):
    if report.get(key) is not True:
        raise SystemExit(f"C native IIO worker did not prove {key}: {report}")
if report.get("native_iio_burst_worker_lifecycle_proof") != "FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1":
    raise SystemExit(f"C native IIO worker lifecycle proof token drifted: {report}")
if report.get("native_iio_burst_transport_worker_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1":
    raise SystemExit(f"C native IIO burst transport worker proof token drifted: {report}")
if report.get("native_iio_burst_transport_session_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1":
    raise SystemExit(f"C native IIO burst transport session proof token drifted: {report}")
if report.get("native_iio_burst_transport_service_loop_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1":
    raise SystemExit(f"C native IIO burst transport service loop proof token drifted: {report}")
if report.get("native_iio_burst_transport_scheduler_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1":
    raise SystemExit(f"C native IIO burst transport scheduler proof token drifted: {report}")
if report.get("native_iio_burst_transport_autonomous_loop_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1":
    raise SystemExit(f"C native IIO burst autonomous transport loop proof token drifted: {report}")
if report.get("native_iio_burst_transport_background_daemon_proof") != "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1":
    raise SystemExit(f"C native IIO burst background transport daemon proof token drifted: {report}")
if report.get("native_iio_burst_integrated_rf_service_daemon_proof") != "FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1":
    raise SystemExit(f"C native IIO burst integrated RF service daemon proof token drifted: {report}")
if report.get("native_iio_burst_state_daemon_transport_queue_proof") != "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_QUEUE v1":
    raise SystemExit(f"C native IIO burst state-daemon transport queue proof token drifted: {report}")
if report.get("native_iio_burst_state_daemon_transport_lifecycle_proof") != "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_LIFECYCLE v1":
    raise SystemExit(f"C native IIO burst state-daemon transport lifecycle proof token drifted: {report}")
if report.get("native_iio_burst_state_daemon_transport_modem_profile_proof") != "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_MODEM_PROFILE v1":
    raise SystemExit(f"C native IIO burst state-daemon transport modem profile proof token drifted: {report}")
if report.get("native_iio_burst_state_daemon_libiio_execution_proof") != "FIELDMESH_IIO_BURST_STATE_DAEMON_LIBIIO_EXECUTION v1":
    raise SystemExit(f"C native IIO burst state-daemon libiio execution proof token drifted: {report}")
if report.get("python_xfer_field_orchestration") is not False:
    raise SystemExit(f"C native IIO transport worker must reject Python field orchestration: {report}")
if report.get("python_worker_xfer_submission") is not False:
    raise SystemExit(f"C native IIO service loop must reject Python WORKER_XFER submission: {report}")
if report.get("python_direct_service_loop_run") is not False:
    raise SystemExit(f"C native IIO scheduler must reject direct service loop pacing: {report}")
if report.get("python_scheduler_drain_submission") is not False:
    raise SystemExit(f"C native IIO autonomous loop must reject Python scheduler-drain pacing: {report}")
if report.get("python_autonomous_loop_run_submission") is not False:
    raise SystemExit(f"C native IIO background daemon must reject Python autonomous-loop run pacing: {report}")
if report.get("python_background_daemon_start_submission") is not False:
    raise SystemExit(f"C native IIO integrated RF service daemon must reject Python background-daemon start pacing: {report}")
if report.get("python_transport_request_file_submission") is not False:
    raise SystemExit(f"C native IIO state-daemon transport queue must reject Python request-file submission: {report}")
if report.get("python_transport_scheduler_queue_file_submission") is not False:
    raise SystemExit(f"C native IIO state-daemon transport queue must reject Python scheduler-queue file submission: {report}")
if report.get("python_transport_helper_command_status_pacing") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python helper command/status pacing: {report}")
if report.get("python_libiio_execution_call") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python libiio execution calls: {report}")
if report.get("python_iio_helper_modem_profile_mapping") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python helper modem-profile mapping: {report}")
if report.get("python_selected_modem_profile_fields") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python-selected modem fields: {report}")
if report.get("python_integrated_daemon_enqueue_submission") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python integrated-daemon enqueue pacing: {report}")
if report.get("python_background_daemon_status_polling") is not False:
    raise SystemExit(f"C native IIO state-daemon transport lifecycle must reject Python background status polling: {report}")
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

"$work_dir/fieldmesh_iio_burst_xfer" --qpsk-self-test \
  >"$work_dir/qpsk_self_test.json"
python3 - "$work_dir/qpsk_self_test.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_qpsk_modem_self_test" or report.get("ok") is not True:
    raise SystemExit(f"C QPSK self-test failed: {report}")
for key in ("base_ok", "phase_recovery_ok", "carrier_ok"):
    if report.get(key) is not True:
        raise SystemExit(f"C QPSK self-test did not prove {key}: {report}")
if report.get("bits_per_symbol") != 2:
    raise SystemExit(f"C QPSK self-test did not report 2 bits/symbol: {report}")
if report.get("frame_bytes", 0) <= 0 or report.get("iq_bytes", 0) <= 0:
    raise SystemExit(f"C QPSK self-test did not report useful byte counts: {report}")
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
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  --iterations 50 \
  >"$work_dir/bpsk_benchmark.json"
"$work_dir/fieldmesh_iio_burst_xfer" --qpsk-benchmark \
  --frame-file "$work_dir/frame.bin" \
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  --iterations 50 \
  >"$work_dir/qpsk_benchmark.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-benchmark \
  --frame-file "$work_dir/frame.bin" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  --iterations 50 \
  >"$work_dir/bfsk_benchmark.json"
python3 - "$work_dir/bpsk_benchmark.json" "$work_dir/bfsk_benchmark.json" "$work_dir/qpsk_benchmark.json" <<'PY'
import json
import sys
from pathlib import Path

for path, event in (
    (Path(sys.argv[1]), "fieldmesh_bpsk_modem_benchmark"),
    (Path(sys.argv[2]), "fieldmesh_bfsk_modem_benchmark"),
    (Path(sys.argv[3]), "fieldmesh_qpsk_modem_benchmark"),
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
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_frame.iq" \
  --decoded-file "$work_dir/bpsk_decoded.bin" \
  --samples-per-symbol 4 \
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
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_rotated_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_rotated_decoded.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/bpsk_carrier_frame.iq" \
  --sample-rate-hz 1000000 \
  --baseband-carrier-hz 125000 \
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_carrier_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-decode \
  --iq-file "$work_dir/bpsk_carrier_frame.iq" \
  --decoded-file "$work_dir/bpsk_carrier_decoded.bin" \
  --sample-rate-hz 1000000 \
  --baseband-carrier-hz 125000 \
  --samples-per-symbol 4 \
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
"$work_dir/fieldmesh_iio_burst_xfer" --qpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/fast_frame.iq" \
  --sample-rate-hz 7680000 \
  --baseband-carrier-hz 100000 \
  --samples-per-symbol 1 \
  --bit-repeat 1 \
  >"$work_dir/qpsk_fast_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --qpsk-decode \
  --iq-file "$work_dir/fast_frame.iq" \
  --decoded-file "$work_dir/fast_decoded.bin" \
  --sample-rate-hz 7680000 \
  --baseband-carrier-hz 100000 \
  --samples-per-symbol 1 \
  --bit-repeat 1 \
  >"$work_dir/qpsk_fast_decode.json"
cmp "$work_dir/frame.bin" "$work_dir/fast_decoded.bin"

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
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_bad_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bpsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/bpsk_good_frame.iq" \
  --samples-per-symbol 4 \
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
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bpsk_decode_after_bad_crc.json"
cmp "$work_dir/frame.bin" "$work_dir/bpsk_combined_decoded.bin"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-encode \
  --frame-file "$work_dir/bad_frame.bin" \
  --iq-file "$work_dir/bad_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 4 \
  --bit-repeat 2 \
  >"$work_dir/bfsk_bad_encode.json"
"$work_dir/fieldmesh_iio_burst_xfer" --bfsk-encode \
  --frame-file "$work_dir/frame.bin" \
  --iq-file "$work_dir/good_frame.iq" \
  --sample-rate-hz 1000000 \
  --space-hz 50000 \
  --mark-hz 150000 \
  --samples-per-symbol 4 \
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
  --samples-per-symbol 4 \
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
python3 - "$work_dir/bfsk_encode.json" "$work_dir/bfsk_decode.json" "$work_dir/qpsk_fast_encode.json" "$work_dir/qpsk_fast_decode.json" <<'PY'
import json
import sys
from pathlib import Path

encode = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
decode = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
fast_encode = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
fast_decode = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
if encode.get("event") != "fieldmesh_bfsk_modem_encode" or encode.get("ok") is not True:
    raise SystemExit(f"C BFSK encode failed: {encode}")
if decode.get("event") != "fieldmesh_bfsk_modem_decode" or decode.get("ok") is not True:
    raise SystemExit(f"C BFSK decode failed: {decode}")
if encode.get("frame_bytes") != decode.get("frame_bytes"):
    raise SystemExit(f"C BFSK encode/decode byte counts differ: {encode} {decode}")
if fast_encode.get("event") != "fieldmesh_qpsk_modem_encode" or fast_encode.get("ok") is not True:
    raise SystemExit(f"C fast QPSK encode failed: {fast_encode}")
if fast_decode.get("event") != "fieldmesh_qpsk_modem_decode" or fast_decode.get("ok") is not True:
    raise SystemExit(f"C fast QPSK decode failed: {fast_decode}")
if fast_encode.get("samples_per_symbol") != 1 or fast_encode.get("bit_repeat") != 1:
    raise SystemExit(f"C fast QPSK profile drifted: {fast_encode}")
if fast_decode.get("samples_per_symbol") != 1 or fast_decode.get("bit_repeat") != 1:
    raise SystemExit(f"C fast QPSK decoder profile drifted: {fast_decode}")
if fast_encode.get("bits_per_symbol") != 2 or fast_decode.get("bits_per_symbol") != 2:
    raise SystemExit(f"C fast QPSK bits/symbol proof drifted: {fast_encode} {fast_decode}")
raw_bitrate_bps = 7_680_000 * 2 / (fast_encode["samples_per_symbol"] * fast_encode["bit_repeat"])
if raw_bitrate_bps < 15_360_000:
    raise SystemExit(f"C fast QPSK raw PHY target regressed: {raw_bitrate_bps}")
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
    "FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1",
    "FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1",
    "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_QUEUE v1",
    "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_LIFECYCLE v1",
    "TRANSPORT_WORKER_START",
    "TRANSPORT_WORKER_STATUS",
    "TRANSPORT_SERVICE_LOOP_START",
    "TRANSPORT_SERVICE_LOOP_STATUS",
    "TRANSPORT_SERVICE_LOOP_RUN",
    "TRANSPORT_SCHEDULER_START",
    "TRANSPORT_SCHEDULER_STATUS",
    "TRANSPORT_SCHEDULER_DRAIN",
    "TRANSPORT_AUTONOMOUS_LOOP_START",
    "TRANSPORT_AUTONOMOUS_LOOP_STATUS",
    "TRANSPORT_AUTONOMOUS_LOOP_RUN",
    "TRANSPORT_BACKGROUND_DAEMON_START",
    "TRANSPORT_BACKGROUND_DAEMON_STATUS",
    "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_START",
    "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_STATUS",
    "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_ENQUEUE",
    "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_ENQUEUE_FIELDS",
    "TRANSPORT_STATE_DAEMON_LIFECYCLE_XFER_FIELDS",
    "WORKER_XFER",
    "fieldmesh_iio_burst_transport_worker_start",
    "fieldmesh_iio_burst_transport_worker_status",
    "fieldmesh_iio_burst_transport_worker_request",
    "fieldmesh_iio_burst_transport_service_loop_start",
    "fieldmesh_iio_burst_transport_service_loop_status",
    "fieldmesh_iio_burst_transport_service_loop_run",
    "fieldmesh_iio_burst_transport_scheduler_start",
    "fieldmesh_iio_burst_transport_scheduler_status",
    "fieldmesh_iio_burst_transport_scheduler_drain",
    "fieldmesh_iio_burst_transport_autonomous_loop_start",
    "fieldmesh_iio_burst_transport_autonomous_loop_status",
    "fieldmesh_iio_burst_transport_autonomous_loop_run",
    "fieldmesh_iio_burst_transport_background_daemon_start",
    "fieldmesh_iio_burst_transport_background_daemon_status",
    "fieldmesh_iio_burst_integrated_rf_service_daemon_start",
    "fieldmesh_iio_burst_integrated_rf_service_daemon_status",
    "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue",
    "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields",
    "fieldmesh_iio_burst_state_daemon_transport_lifecycle_xfer",
    "native_iio_burst_worker",
    "persistent_native_iio_burst_worker",
    "native_iio_burst_worker_lifecycle",
    "server_owned_xfer_loop",
    "server_xfer_count",
    "native_iio_burst_transport_worker",
    "native_iio_burst_transport_session",
    "native_iio_burst_transport_service_loop",
    "native_iio_burst_transport_scheduler",
    "native_iio_burst_transport_autonomous_loop",
    "native_iio_burst_transport_background_daemon",
    "native_iio_burst_integrated_rf_service_daemon",
    "native_iio_burst_state_daemon_transport_queue",
    "native_iio_burst_state_daemon_transport_lifecycle",
    "native_iio_burst_state_daemon_transport_modem_profile",
    "transport_session_start_count",
    "transport_worker_request_count",
    "transport_service_loop_start_count",
    "transport_service_loop_run_count",
    "transport_scheduler_start_count",
    "transport_scheduler_drain_count",
    "transport_scheduler_scheduled_request_count",
    "transport_autonomous_loop_start_count",
    "transport_autonomous_loop_run_count",
    "transport_autonomous_loop_scheduled_request_count",
    "transport_background_daemon_start_count",
    "transport_background_daemon_xfer_count",
    "transport_background_daemon_scheduled_request_count",
    "transport_integrated_rf_service_daemon_start_count",
    "transport_integrated_rf_service_daemon_enqueue_count",
    "transport_integrated_rf_service_daemon_drained_count",
    "transport_state_daemon_queue_request_count",
    "transport_state_daemon_lifecycle_xfer_count",
    "python_xfer_field_orchestration",
    "python_worker_xfer_submission",
    "python_direct_service_loop_run",
    "python_scheduler_drain_submission",
    "python_autonomous_loop_run_submission",
    "python_background_daemon_start_submission",
    "python_transport_request_file_submission",
    "python_transport_scheduler_queue_file_submission",
    "python_transport_helper_command_status_pacing",
    "python_libiio_execution_call",
    "python_integrated_daemon_enqueue_submission",
    "python_background_daemon_status_polling",
    "python_selected_modem_profile_fields",
    "state_daemon_transport_selected_samples_per_symbol",
    "state_daemon_transport_selected_bit_repeat",
    "state_daemon_transport_modem_profile_request",
    "state_daemon_transport_modem_profile",
    "native_iio_burst_state_daemon_libiio_execution",
    "state_daemon_libiio_execution",
    "state_daemon_libiio_execution_count",
    "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_MODEM_PROFILE v1",
    "FIELDMESH_IIO_BURST_STATE_DAEMON_LIBIIO_EXECUTION v1",
    "native_transport_worker_autonomous_daemon",
    "libiio_rx_tx_worker",
    "python_iio_transport",
    "fieldmesh_bpsk_modem_encode",
    "fieldmesh_bpsk_modem_decode",
    "fieldmesh_bpsk_modem_self_test",
    "fieldmesh_qpsk_modem_encode",
    "fieldmesh_qpsk_modem_decode",
    "fieldmesh_qpsk_modem_self_test",
    "qpsk_decode_frame_coherent",
    "project_qpsk_bits",
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
