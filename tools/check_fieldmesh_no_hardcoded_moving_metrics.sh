#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

metric_assignment_pattern='(out_metrics->|metrics\.)(rssi_dbm|snr_db|evm_db|per_mille|ack_latency_ms|jitter_ms|queue_age_ms|delivered_kbps|estimated_kbps|cfo_hz|doppler_hz|timing_residual_ns|measured_age_ms)\s*=\s*-?[0-9]'
rtls_assignment_pattern='(x_m|y_m|z_m|range_m|tdoa_ns)\s*=\s*-?[0-9]'

if rg -n "$metric_assignment_pattern|$rtls_assignment_pattern" \
    sdk/c/src \
    apps/fieldmesh-control-camera-demo \
    sdk/c/examples/fieldmesh_state_daemon_demo.c; then
  echo "fieldmesh guardrail: moving RF/RTLS metrics must come from reports or fixtures, not numeric literals" >&2
  exit 1
fi

if rg -n 'scripts/config --file \$\{B\}/\.config --disable (SPI_BCM2835|SPI_BCM2835AUX|ATA|SATA_AHCI|SATA_AHCI_PLATFORM)' \
    meta-sdr-z203/recipes-kernel/linux \
    meta-sdr-z103/recipes-kernel/linux; then
  echo "fieldmesh guardrail: do not hide machine-config drift by disabling unrelated kernel peripherals" >&2
  exit 1
fi

echo "fieldmesh no-hardcoded-moving-metrics guard: ok"
