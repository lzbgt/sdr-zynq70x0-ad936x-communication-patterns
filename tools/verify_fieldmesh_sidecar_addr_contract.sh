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

probe_z203_bin="$work_dir/fieldmesh-udp-probe-z203"
probe_z103_bin="$work_dir/fieldmesh-udp-probe-z103"
OUT="$probe_z203_bin" "$repo_root/tools/build_fieldmesh_udp_probe_host.sh" \
    "$repo_root/meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" >/dev/null
OUT="$probe_z103_bin" "$repo_root/tools/build_fieldmesh_udp_probe_host.sh" \
    "$repo_root/meta-sdr-z103/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" >/dev/null
"$probe_z203_bin" sidecar-addr-self-test >"$work_dir/z203_sidecar_addr.json"
"$probe_z103_bin" sidecar-addr-self-test >"$work_dir/z103_sidecar_addr.json"

python3 - "$repo_root" "$work_dir/z203_sidecar_addr.json" "$work_dir/z103_sidecar_addr.json" <<'PY'
import json
import sys
import importlib.util
from pathlib import Path

repo = Path(sys.argv[1])
z203_report = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
z103_report = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
header = (repo / "sdk/c/include/fieldmesh_sidecar_addr.h").read_text(encoding="utf-8")
ctrl_tool = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
probe_z203 = (repo / "meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")
probe_z103 = (repo / "meta-sdr-z103/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")
devicetree_plan_path = repo / "tools/fieldmesh_devicetree_plan.py"
devicetree_plan = devicetree_plan_path.read_text(encoding="utf-8")
vendor_inventory_path = repo / "tools/fieldmesh_vendor_dma_inventory.py"
vendor_inventory = vendor_inventory_path.read_text(encoding="utf-8")

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
    "FIELDMESH_SIDECAR_FIRMWARE_RING_BASE",
    "FIELDMESH_SIDECAR_WINDOW_SIZE",
    "FIELDMESH_SIDECAR_CTRL_NODE",
    "FIELDMESH_SIDECAR_DMA_COMPAT",
    "sidecar-addr-self-test",
    "fieldmesh_sidecar_addr_self_test",
    "native_c_contract",
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

if "fieldmesh_sidecar_addr.h" not in vendor_inventory:
    raise SystemExit("fieldmesh_vendor_dma_inventory.py does not read the sidecar address C contract")
for stale in (
    "DEFAULT_WINDOW_SIZE = 0x10000",
    '("fieldmesh_ctrl", 0x43C00000',
    '("fieldmesh_tx_dma", 0x43C10000',
    '("fieldmesh_rx_dma", 0x43C20000',
    '("fieldmesh_ring", 0x43C30000',
):
    if stale in vendor_inventory:
        raise SystemExit(f"fieldmesh_vendor_dma_inventory.py still duplicates sidecar address contract: {stale}")

if "fieldmesh_sidecar_addr.h" not in devicetree_plan:
    raise SystemExit("fieldmesh_devicetree_plan.py does not read the sidecar address C contract")
if "SIDECAR_DTSI_TEMPLATE" not in devicetree_plan or "render_sidecar_dtsi" not in devicetree_plan:
    raise SystemExit("fieldmesh_devicetree_plan.py no longer renders DTSI from a contract template")
for stale in (
    "fieldmesh-ctrl@43c00000",
    "dma@43c10000",
    "dma@43c20000",
    "fieldmesh-ring@43c30000",
    "reg = <0x43c00000 0x10000>",
    "reg = <0x43c10000 0x10000>",
    "reg = <0x43c20000 0x10000>",
    "reg = <0x43c30000 0x10000>",
):
    if stale in devicetree_plan:
        raise SystemExit(f"fieldmesh_devicetree_plan.py still duplicates sidecar address contract: {stale}")

spec = importlib.util.spec_from_file_location("fieldmesh_devicetree_plan", devicetree_plan_path)
if spec is None or spec.loader is None:
    raise SystemExit("could not load fieldmesh_devicetree_plan.py")
devicetree_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(devicetree_module)
plan_contract = devicetree_module.load_sidecar_addr_contract()
fragment = devicetree_module.render_sidecar_dtsi(plan_contract)
expected_plan_contract = {
    "source": "sdk/c/include/fieldmesh_sidecar_addr.h",
    "ctrl_base": "0x43c00000",
    "tx_dma_base": "0x43c10000",
    "rx_dma_base": "0x43c20000",
    "firmware_ring_base": "0x43c30000",
    "window_size": "0x10000",
    "ctrl_node": "fieldmesh-ctrl@43c00000",
    "tx_dma_node": "dma@43c10000",
    "rx_dma_node": "dma@43c20000",
    "firmware_ring_node": "fieldmesh-ring@43c30000",
    "packet_node": "fieldmesh-packet",
    "ctrl_compat": "fieldmesh,sidecar-ctrl-1.0",
    "dma_compat": "adi,axi-dmac-1.00.a",
    "firmware_ring_compat": "fieldmesh,firmware-ring-1.0",
    "packet_compat": "fieldmesh,packet-sidecar-1.0",
}
if plan_contract != expected_plan_contract:
    raise SystemExit(f"fieldmesh_devicetree_plan.py C contract projection drifted: {plan_contract!r}")
for token in (
    "fieldmesh_ctrl: fieldmesh-ctrl@43c00000",
    "reg = <0x43c00000 0x10000>",
    "fieldmesh_tx_dma: dma@43c10000",
    "reg = <0x43c10000 0x10000>",
    "fieldmesh_rx_dma: dma@43c20000",
    "reg = <0x43c20000 0x10000>",
    "fieldmesh_ring: fieldmesh-ring@43c30000",
    "reg = <0x43c30000 0x10000>",
    'compatible = "fieldmesh,sidecar-ctrl-1.0"',
    'compatible = "fieldmesh,firmware-ring-1.0", "generic-uio"',
    'compatible = "fieldmesh,packet-sidecar-1.0"',
):
    if token not in fragment:
        raise SystemExit(f"rendered FieldMesh devicetree fragment missing {token!r}")

inventory_spec = importlib.util.spec_from_file_location("fieldmesh_vendor_dma_inventory", vendor_inventory_path)
if inventory_spec is None or inventory_spec.loader is None:
    raise SystemExit("could not load fieldmesh_vendor_dma_inventory.py")
inventory_module = importlib.util.module_from_spec(inventory_spec)
inventory_spec.loader.exec_module(inventory_module)
if inventory_module.DEFAULT_WINDOW_SIZE != 0x10000:
    raise SystemExit(f"vendor inventory window size drifted: {inventory_module.DEFAULT_WINDOW_SIZE!r}")
expected_inventory_windows = (
    ("fieldmesh_ctrl", 0x43C00000, 0x10000),
    ("fieldmesh_tx_dma", 0x43C10000, 0x10000),
    ("fieldmesh_rx_dma", 0x43C20000, 0x10000),
    ("fieldmesh_ring", 0x43C30000, 0x10000),
)
if inventory_module.SIDECAR_WINDOWS != expected_inventory_windows:
    raise SystemExit(f"vendor inventory sidecar windows drifted: {inventory_module.SIDECAR_WINDOWS!r}")
inventory_check = inventory_module.sidecar_check({})
if (
    not inventory_check.get("ok") or
    inventory_check.get("window_size") != 0x10000 or
    inventory_check.get("source") != "sdk/c/include/fieldmesh_sidecar_addr.h"
):
    raise SystemExit(f"vendor inventory sidecar check failed: {inventory_check!r}")
inventory_addresses = [row.get("address") for row in inventory_check.get("proposed_windows", [])]
if inventory_addresses != ["0x43C00000", "0x43C10000", "0x43C20000", "0x43C30000"]:
    raise SystemExit(f"vendor inventory sidecar addresses drifted: {inventory_addresses!r}")

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

for label, report in (("z203", z203_report), ("z103", z103_report)):
    expected = {
        "event": "fieldmesh_sidecar_addr_self_test",
        "ok": True,
        "ctrl_base": "0x43c00000",
        "tx_dma_base": "0x43c10000",
        "rx_dma_base": "0x43c20000",
        "firmware_ring_base": "0x43c30000",
        "window_size": "0x00010000",
        "native_c_contract": True,
        "reads_hardware": False,
        "writes_hardware": False,
    }
    for key, value in expected.items():
        if report.get(key) != value:
            raise SystemExit(f"{label} sidecar address self-test mismatch for {key}: {report!r}")

print('{"event":"fieldmesh_sidecar_addr_contract","ok":true,'
      '"ctrl_base":"0x43c00000","tx_dma_base":"0x43c10000",'
      '"rx_dma_base":"0x43c20000","window_size":"0x10000",'
      '"native_c_contract":true}')
PY
