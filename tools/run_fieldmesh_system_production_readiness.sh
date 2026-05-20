#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/system-production-readiness-$(date +%Y%m%d-%H%M%S)-$$}"

gnss_report="${GNSS_PREFLIGHT_REPORT:-}"
timepulse_report="${GNSS_TIMEPULSE_POLL_REPORT:-}"
native_ip_report="${NATIVE_IP_IPERF_SEQUENCE_REPORT:-}"
real_rf_report="${REAL_RF_PRODUCTION_GATE_REPORT:-}"

run_gnss_preflight="${RUN_GNSS_PREFLIGHT:-1}"
run_gnss_timepulse_poll="${RUN_GNSS_TIMEPULSE_POLL:-1}"
run_native_ip_preflight="${RUN_NATIVE_IP_PREFLIGHT:-1}"

require_gnss_fix="${REQUIRE_GNSS_FIX:-1}"
require_gnss_pps="${REQUIRE_GNSS_PPS:-1}"
require_gnss_receiver_health="${REQUIRE_GNSS_RECEIVER_HEALTH:-1}"
require_native_ip_iperf="${REQUIRE_NATIVE_IP_IPERF:-1}"
require_real_rf="${REQUIRE_REAL_RF:-1}"

gnss_runner="${FIELDMESH_GNSS_PREFLIGHT_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_gnss_live_preflight.sh}"
timepulse_runner="${FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh}"
native_ip_runner="${FIELDMESH_NATIVE_IP_PREFLIGHT_RUNNER:-$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh}"

bool01() {
    case "$1" in
        0|1) return 0 ;;
        *) return 1 ;;
    esac
}

for value in \
    "$run_gnss_preflight" \
    "$run_gnss_timepulse_poll" \
    "$run_native_ip_preflight" \
    "$require_gnss_fix" \
    "$require_gnss_pps" \
    "$require_gnss_receiver_health" \
    "$require_native_ip_iperf" \
    "$require_real_rf"; do
    if ! bool01 "$value"; then
        echo "readiness flags must be 0 or 1" >&2
        exit 2
    fi
done

mkdir -p "$out_dir"

if [ -z "$gnss_report" ] && [ "$run_gnss_preflight" = "1" ]; then
    set +e
    REQUIRE_GNSS_FIX="$require_gnss_fix" \
      REQUIRE_GNSS_PPS="$require_gnss_pps" \
      REQUIRE_GNSS_RECEIVER_HEALTH="$require_gnss_receiver_health" \
      OUT_DIR="$out_dir/gnss_preflight" \
      "$gnss_runner" \
      >"$out_dir/gnss_preflight.stdout" \
      2>"$out_dir/gnss_preflight.stderr"
    gnss_rc="$?"
    set -e
    printf '%s\n' "$gnss_rc" >"$out_dir/gnss_preflight.rc"
    gnss_report="$out_dir/gnss_preflight/summary.json"
fi

if [ -z "$timepulse_report" ] && [ "$run_gnss_timepulse_poll" = "1" ]; then
    set +e
    OUT_DIR="$out_dir/gnss_timepulse_poll" \
      "$timepulse_runner" \
      >"$out_dir/gnss_timepulse_poll.stdout" \
      2>"$out_dir/gnss_timepulse_poll.stderr"
    timepulse_rc="$?"
    set -e
    printf '%s\n' "$timepulse_rc" >"$out_dir/gnss_timepulse_poll.rc"
    timepulse_report="$out_dir/gnss_timepulse_poll/summary.json"
fi

if [ -z "$native_ip_report" ] && [ "$run_native_ip_preflight" = "1" ]; then
    set +e
    PREFLIGHT_ONLY=1 \
      OUT_DIR="$out_dir/native_ip_preflight" \
      "$native_ip_runner" \
      >"$out_dir/native_ip_preflight.stdout" \
      2>"$out_dir/native_ip_preflight.stderr"
    native_ip_rc="$?"
    set -e
    printf '%s\n' "$native_ip_rc" >"$out_dir/native_ip_preflight.rc"
    native_ip_report="$out_dir/native_ip_preflight/native_ip_iperf_production_sequence.json"
fi

args=(--output "$out_dir/system_readiness.json")
if [ -n "$gnss_report" ] && [ -f "$gnss_report" ]; then
    args+=(--gnss-preflight "$gnss_report")
fi
if [ -n "$timepulse_report" ] && [ -f "$timepulse_report" ]; then
    args+=(--gnss-timepulse-poll "$timepulse_report")
fi
if [ -n "$native_ip_report" ] && [ -f "$native_ip_report" ]; then
    args+=(--native-ip-iperf-sequence "$native_ip_report")
fi
if [ -n "$real_rf_report" ] && [ -f "$real_rf_report" ]; then
    args+=(--real-rf-production-gate "$real_rf_report")
fi

if [ "$require_gnss_fix" = "0" ]; then
    args+=(--no-require-gnss-fix)
fi
if [ "$require_gnss_pps" = "0" ]; then
    args+=(--no-require-gnss-pps)
fi
if [ "$require_gnss_receiver_health" = "0" ]; then
    args+=(--no-require-gnss-receiver-health)
fi
if [ "$require_native_ip_iperf" = "0" ]; then
    args+=(--no-require-native-ip-iperf)
fi
if [ "$require_real_rf" = "0" ]; then
    args+=(--no-require-real-rf)
fi

set +e
"$repo_root/tools/fieldmesh_system_production_readiness.py" "${args[@]}" \
  | tee "$out_dir/system_readiness.stdout"
summary_rc="${PIPESTATUS[0]}"
set -e

if [ -f "$out_dir/system_readiness.json" ]; then
    "$repo_root/tools/fieldmesh_system_readiness_actions.py" \
      "$out_dir/system_readiness.json" \
      --output "$out_dir/system_readiness_actions.json" \
      >"$out_dir/system_readiness_actions.stdout"
fi

echo "Capture directory: $out_dir"
exit "$summary_rc"
