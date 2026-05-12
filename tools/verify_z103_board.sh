#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
capture_dir="${CAPTURE_DIR:-$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures}"
timestamp="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$capture_dir"

"$repo_root/tools/verify_board.sh" "$board_ip" | tee "$capture_dir/z103_verify_board_${timestamp}.txt"

echo
echo "Z103 capture written under: $capture_dir"
