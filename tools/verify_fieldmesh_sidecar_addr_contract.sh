#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/sidecar-addr-contract"
cc="${CC:-cc}"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  -xc - \
  -o "$work_dir/fieldmesh-sidecar-addr-smoke" <<'EOF_C'
#include "fieldmesh_sidecar_addr.h"

int main(void) {
    if (FIELDMESH_SIDECAR_CTRL_BASE != 0x43c00000u ||
        FIELDMESH_SIDECAR_TX_DMA_BASE != 0x43c10000u ||
        FIELDMESH_SIDECAR_RX_DMA_BASE != 0x43c20000u ||
        FIELDMESH_SIDECAR_FIRMWARE_RING_BASE != 0x43c30000u ||
        FIELDMESH_SIDECAR_WINDOW_SIZE != 0x10000u) {
        return 1;
    }
    if (!fieldmesh_sidecar_addr_default_map_valid() ||
        !fieldmesh_sidecar_addr_default_windows_disjoint()) {
        return 2;
    }
    if (!fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_CTRL_BASE) ||
        fieldmesh_sidecar_addr_window_aligned(FIELDMESH_SIDECAR_CTRL_BASE + 0x40u)) {
        return 3;
    }
    return 0;
}
EOF_C

"$work_dir/fieldmesh-sidecar-addr-smoke"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
header = (repo / "sdk/c/include/fieldmesh_sidecar_addr.h").read_text(encoding="utf-8")
ctrl_tool = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
probe_z203 = (repo / "meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")
probe_z103 = (repo / "meta-sdr-z103/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")

required_header_tokens = [
    "FIELDMESH_SIDECAR_CTRL_BASE 0x43c00000u",
    "FIELDMESH_SIDECAR_TX_DMA_BASE 0x43c10000u",
    "FIELDMESH_SIDECAR_RX_DMA_BASE 0x43c20000u",
    "FIELDMESH_SIDECAR_FIRMWARE_RING_BASE 0x43c30000u",
    "FIELDMESH_SIDECAR_WINDOW_SIZE 0x00010000u",
    "FIELDMESH_SIDECAR_CTRL_NODE",
    "FIELDMESH_SIDECAR_DMA_COMPAT",
    "FIELDMESH_SIDECAR_FIRMWARE_RING_COMPAT",
    "fieldmesh_sidecar_addr_default_map_valid",
]
missing = [token for token in required_header_tokens if token not in header]
if missing:
    raise SystemExit(f"missing sidecar address header tokens: {missing}")

for name, source in (
    ("fieldmesh_ctrl_write.c", ctrl_tool),
    ("z203 fieldmesh_udp_probe.c", probe_z203),
    ("z103 fieldmesh_udp_probe.c", probe_z103),
):
    if '#include "fieldmesh_sidecar_addr.h"' not in source:
        raise SystemExit(f"{name} does not consume fieldmesh_sidecar_addr.h")

for token in (
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "FIELDMESH_SIDECAR_TX_DMA_BASE",
    "FIELDMESH_SIDECAR_RX_DMA_BASE",
    "FIELDMESH_SIDECAR_WINDOW_SIZE",
    "FIELDMESH_SIDECAR_CTRL_NODE",
    "FIELDMESH_SIDECAR_DMA_COMPAT",
):
    if token not in probe_z203 or token not in probe_z103:
        raise SystemExit(f"fieldmesh_udp_probe sources do not use {token}")

for stale in (
    ".ctrl_base = 0x43c00000U",
    ".tx_dma_base = 0x43c10000U",
    ".rx_dma_base = 0x43c20000U",
    ".dma_size = 0x10000U",
    '"fieldmesh,sidecar-ctrl-1.0", 0x43c00000U',
    '"adi,axi-dmac-1.00.a", 0x43c10000U',
    '"adi,axi-dmac-1.00.a", 0x43c20000U',
):
    if stale in probe_z203 or stale in probe_z103:
        raise SystemExit(f"fieldmesh_udp_probe still duplicates sidecar address contract: {stale}")

if "0x43c00000u" in ctrl_tool:
    raise SystemExit("fieldmesh-ctrl-write still hardcodes the firmware-DMA base")
if "FIELDMESH_SIDECAR_CTRL_BASE" not in ctrl_tool:
    raise SystemExit("fieldmesh-ctrl-write does not use the shared sidecar control base")

recipe_paths = [
    repo / "meta-sdr-z203/recipes-core/fieldmesh-udp-probe/fieldmesh-udp-probe_0.1.bb",
    repo / "meta-sdr-z103/recipes-core/fieldmesh-udp-probe/fieldmesh-udp-probe_0.1.bb",
    repo / "meta-sdr-z203/recipes-core/fieldmesh-rf-tools/fieldmesh-rf-tools_0.1.bb",
    repo / "meta-sdr-z103/recipes-core/fieldmesh-rf-tools/fieldmesh-rf-tools_0.1.bb",
    repo / "meta-sdr-z203/recipes-core/fieldmesh-sdk-demos/fieldmesh-sdk-demos_0.1.bb",
    repo / "meta-sdr-z103/recipes-core/fieldmesh-sdk-demos/fieldmesh-sdk-demos_0.1.bb",
]
for path in recipe_paths:
    source = path.read_text(encoding="utf-8")
    if "fieldmesh_sidecar_addr.h" not in source:
        raise SystemExit(f"{path} does not package the sidecar address C header")

if probe_z203 != probe_z103:
    raise SystemExit("Z203 and Z103 fieldmesh_udp_probe.c sources diverged")

print('{"event":"fieldmesh_sidecar_addr_contract","ok":true,'
      '"ctrl_base":"0x43c00000","tx_dma_base":"0x43c10000",'
      '"rx_dma_base":"0x43c20000","window_size":"0x10000",'
      '"native_c_contract":true}')
PY
