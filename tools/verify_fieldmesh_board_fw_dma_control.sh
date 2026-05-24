#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root/tools/run_fieldmesh_board_fw_dma_control.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "run_fieldmesh_board_sidecar_preflight.sh",
    "fw_dma_base",
    "fw_dma_reads_hardware",
    "fw_dma_writes_hardware",
    "status|config|arm|stop",
    "PEER_INDEX",
    "DESCRIPTOR_FLAGS:$descriptor_flags:63",
    "SEQ_SEED",
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1",
    "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-config",
    "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-arm",
    "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-stop",
    "fieldmesh_board_fw_dma_control_assert",
]
for token in required:
    if token not in script:
        raise SystemExit(f"run_fieldmesh_board_fw_dma_control.sh missing token: {token}")

preflight_check = script.index("fw_dma_base")
config_write = script.index("--fw-dma-config")
arm_write = script.index("--fw-dma-arm")
stop_write = script.index("--fw-dma-stop")
if preflight_check > config_write or preflight_check > arm_write or preflight_check > stop_write:
    raise SystemExit("firmware-DMA writes must be after sidecar preflight validation")
if script.index("fieldmesh_fw_dma_control_skipped") > arm_write:
    raise SystemExit("dry-run skip path must be defined before write command")
PY

printf 'fieldmesh_board_fw_dma_control=pass\n'
