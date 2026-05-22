#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timestamp="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
out_dir="${OUT_DIR:-$repo_root/resources/variants/sdr-z103-z7010-1r1t/firmware/qspi-live-backup-$timestamp}"

BOARD_IP="${BOARD_IP:-192.168.3.1}" \
SSH_USER="${SSH_USER:-root}" \
SSH_PASS="${SSH_PASS:-analog}" \
OUT_DIR="$out_dir" \
"$repo_root/tools/backup_qspi_live.sh"
