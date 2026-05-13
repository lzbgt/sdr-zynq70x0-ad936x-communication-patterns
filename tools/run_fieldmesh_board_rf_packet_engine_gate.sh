#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
variant="${VARIANT:-${2:-z103}}"
frame="${FRAME:-$repo_root/resources/fieldmesh/vectors/frame_000.bin}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-rf-packet-engine-gate-$(date +%Y%m%d-%H%M%S)}"
center_frequency_hz="${CENTER_FREQUENCY_HZ:-2400000000}"
sample_rate_hz="${SAMPLE_RATE_HZ:-1000000}"
rf_bandwidth_hz="${RF_BANDWIDTH_HZ:-1000000}"
fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-60}"

mkdir -p "$out_dir"

if [[ ! -f "$frame" ]]; then
  echo "Missing FieldMesh frame vector: $frame" >&2
  exit 1
fi

sdk_dir="$out_dir/sdk_daemon"
dma_dir="$out_dir/sidecar_dma_smoke"
transport_dir="$out_dir/rf_packet_engine_transport"

BOARD_IP="$board_ip" VARIANT="$variant" OUT_DIR="$sdk_dir" FORCE_UPLOAD="${FORCE_UPLOAD:-1}" \
  "$repo_root/tools/run_fieldmesh_board_sdk_daemon.sh"

"$repo_root/tools/run_fieldmesh_board_dma_smoke.sh" "$board_ip" "$frame" "$dma_dir"

"$repo_root/tools/fieldmesh_rf_packet_engine_transport.py" \
  --frame "$frame" \
  --handoff-report "$sdk_dir/host_query.ndjson" \
  --out-dir "$transport_dir" \
  --center-frequency-hz "$center_frequency_hz" \
  --sample-rate-hz "$sample_rate_hz" \
  --rf-bandwidth-hz "$rf_bandwidth_hz" \
  --fixture-attenuation-db "$fixture_attenuation_db" \
  --conducted-or-shielded \
  > "$out_dir/rf_packet_engine_transport.ndjson"

"$repo_root/tools/fieldmesh_rf_packet_engine_binding_assert.py" \
  --handoff "$sdk_dir/host_query.ndjson" \
  --dma-smoke "$dma_dir/dma_smoke.ndjson" \
  --transport-report "$transport_dir/fieldmesh_rf_packet_engine_transport.json" \
  --out "$out_dir/fieldmesh_rf_packet_engine_binding_assert.json" \
  --pretty

echo "Capture directory: $out_dir"
