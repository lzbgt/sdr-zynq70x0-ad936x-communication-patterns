#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root/tools/run_fieldmesh_board_dma_smoke.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    'fw_dma_base',
    'fw_dma_reads_hardware',
    'fw_dma_writes_hardware',
    'sidecar preflight is missing firmware-DMA status',
    'firmware-DMA status preflight is not read-only',
    '--allow-live-writes',
]
for token in required:
    if token not in script:
        raise SystemExit(f"run_fieldmesh_board_dma_smoke.sh missing token: {token}")

preflight_check = script.index('fw_dma_base')
live_write = script.index('--allow-live-writes')
if preflight_check > live_write:
    raise SystemExit("firmware-DMA preflight check must precede dma-smoke --allow-live-writes")
PY

printf 'fieldmesh_board_dma_smoke_guard=pass\n'
