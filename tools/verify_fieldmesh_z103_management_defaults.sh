#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
missing = []

checks = {
    "tools/verify_z103_board.sh": [
        'board_ip="${BOARD_IP:-${1:-192.168.3.1}}"',
    ],
    "tools/backup_z103_qspi_live.sh": [
        'BOARD_IP="${BOARD_IP:-192.168.3.1}"',
    ],
    "tools/run_fieldmesh_live_gate.sh": [
        'z203)',
        'board_ip="${board_ip:-192.168.1.10}"',
        'z103)',
        'board_ip="${board_ip:-192.168.3.1}"',
        'diagnose_pluto_usb_reachability.sh" "$board_ip"',
    ],
}

for rel, tokens in checks.items():
    text = (repo / rel).read_text(encoding="utf-8")
    for token in tokens:
        if token not in text:
            missing.append(f"{rel}: missing token {token!r}")

network_doc = (repo / "docs/fieldmesh-network-configuration.md").read_text(
    encoding="utf-8"
)
for token in [
    "after reboot, `192.168.2.1` resolved to Z203",
    "`192.168.3.1` resolved to",
    "  Z103;",
]:
    if token not in network_doc:
        missing.append(f"docs/fieldmesh-network-configuration.md missing token {token!r}")

if missing:
    raise SystemExit("\n".join(missing))

print("fieldmesh_z103_management_defaults=pass")
PY
