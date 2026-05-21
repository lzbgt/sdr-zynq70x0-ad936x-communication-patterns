#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-burst-xfer-verify"
cc="${CC:-cc}"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$cc" -std=c99 -Wall -Wextra -Werror \
  "$repo_root/tools/fieldmesh_iio_burst_xfer.c" \
  -liio -lpthread \
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
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing libiio helper primitives: {missing}")
print('{"event":"fieldmesh_iio_burst_xfer_check","ok":true}')
PY
