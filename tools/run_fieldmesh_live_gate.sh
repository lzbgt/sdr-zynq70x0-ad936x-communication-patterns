#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z103}"
board_ip="${BOARD_IP:-192.168.2.1}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
run_boot="${RUN_BOOT:-1}"
run_preflight="${RUN_PREFLIGHT:-1}"
wait_after_boot="${WAIT_AFTER_BOOT:-20}"
timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/live-gate-$variant-$timestamp}"
status_file="$out_dir/status.tsv"

case "$variant" in
  z203|z103) ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

mkdir -p "$out_dir"
printf 'step\tstatus\tlog\n' >"$status_file"

run_step() {
  local name="$1"
  shift
  local log="$out_dir/$name.log"
  local status

  printf '== %s ==\n' "$name"
  "$@" >"$log" 2>&1
  status=$?
  printf '%s\t%s\t%s\n' "$name" "$status" "$log" >>"$status_file"
  if [[ "$status" -ne 0 ]]; then
    printf '%s failed with status %s; see %s\n' "$name" "$status" "$log" >&2
  fi
  return "$status"
}

record_skip() {
  local name="$1"
  local reason="$2"
  local log="$out_dir/$name.log"
  printf '%s\n' "$reason" >"$log"
  printf '%s\tSKIP\t%s\n' "$name" "$log" >>"$status_file"
}

overall=0

run_step verify_runtime_artifacts \
  "$repo_root/tools/verify_fieldmesh_runtime_artifacts.sh" "$variant" || overall=1

run_step prepare_jtag_ram_payload \
  env PREPARE_ONLY=1 OUT_DIR="$out_dir/jtag_ram_payload" \
    "$repo_root/tools/run_fieldmesh_jtag_yocto_ram.sh" "$variant" || overall=1

run_step usb_reachability \
  "$repo_root/tools/diagnose_pluto_usb_reachability.sh" "$board_ip" || true

run_step jtag_scan "$repo_root/tools/probe_openocd_jtag.sh" || overall=1

boot_status=0
if [[ "$run_boot" == "1" ]]; then
  run_step fieldmesh_jtag_ram_boot \
    env OUT_DIR="$out_dir/jtag_ram_payload" \
      "$repo_root/tools/run_fieldmesh_jtag_yocto_ram.sh" "$variant"
  boot_status=$?
  if [[ "$boot_status" -ne 0 ]]; then
    overall=1
  fi
else
  record_skip fieldmesh_jtag_ram_boot "RUN_BOOT=$run_boot"
  boot_status=1
fi

if [[ "$run_preflight" == "1" && "$boot_status" -eq 0 ]]; then
  if [[ "$wait_after_boot" != "0" ]]; then
    sleep "$wait_after_boot"
  fi
  run_step board_sidecar_preflight \
    env BOARD_IP="$board_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
      OUT_DIR="$out_dir/sidecar_preflight" \
      "$repo_root/tools/run_fieldmesh_board_sidecar_preflight.sh" "$board_ip" || overall=1
else
  record_skip board_sidecar_preflight \
    "RUN_PREFLIGHT=$run_preflight boot_status=$boot_status"
fi

printf 'fieldmesh_live_gate=%s\n' "$variant"
printf 'out_dir=%s\n' "$out_dir"
cat "$status_file"

exit "$overall"
