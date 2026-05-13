#!/usr/bin/env python3
"""Patch a copied Pluto HDL tree with FieldMesh sidecar RTL file references."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import fieldmesh_sidecar_plan as sidecar_plan


MAKE_BEGIN = "# FieldMesh sidecar overlay files: begin"
MAKE_END = "# FieldMesh sidecar overlay files: end"
BD_FILES_BEGIN = "# FieldMesh sidecar RTL files: begin"
BD_FILES_END = "# FieldMesh sidecar RTL files: end"
BD_CTRL_BEGIN = "# FieldMesh sidecar control overlay: begin"
BD_CTRL_END = "# FieldMesh sidecar control overlay: end"
BD_BRIDGE_BEGIN = "# FieldMesh sidecar bridge overlay: begin"
BD_BRIDGE_END = "# FieldMesh sidecar bridge overlay: end"
BD_DMA_BEGIN = "# FieldMesh sidecar DMA overlay: begin"
BD_DMA_END = "# FieldMesh sidecar DMA overlay: end"
BD_RF_ENGINE_BEGIN = "# FieldMesh RF packet engine overlay: begin"
BD_RF_ENGINE_END = "# FieldMesh RF packet engine overlay: end"


def rel_rtl_name(rtl_path: str) -> str:
    return f"fieldmesh/{Path(rtl_path).name}"


def patch_system_project(text: str, rel_files: list[str]) -> tuple[str, bool]:
    if all(f'"{rel}"' in text for rel in rel_files):
        return text, False

    lines = text.splitlines()
    marker = '  "$ad_hdl_dir/library/common/ad_iobuf.v"]'
    try:
        idx = lines.index(marker)
    except ValueError as exc:
        raise SystemExit("system_project.tcl: expected ad_iobuf.v list terminator not found") from exc

    new_lines = lines[:idx]
    new_lines.append('  "$ad_hdl_dir/library/common/ad_iobuf.v" \\')
    for rel in rel_files[:-1]:
        new_lines.append(f'  "{rel}" \\')
    new_lines.append(f'  "{rel_files[-1]}"]')
    new_lines.extend(lines[idx + 1 :])
    return "\n".join(new_lines) + "\n", True


def patch_makefile(text: str, rel_files: list[str]) -> tuple[str, bool]:
    if MAKE_BEGIN in text and MAKE_END in text:
        return text, False

    anchor = "LIB_DEPS += axi_ad9361"
    try:
        idx = text.index(anchor)
    except ValueError as exc:
        raise SystemExit("Makefile: expected LIB_DEPS anchor not found") from exc

    block = [MAKE_BEGIN]
    block.extend(f"M_DEPS += {rel}" for rel in rel_files)
    block.append(MAKE_END)
    block.append("")
    patched = text[:idx] + "\n".join(block) + "\n" + text[idx:]
    return patched, True


def render_bd_files_overlay() -> str:
    return f"""
{BD_FILES_BEGIN}
set fieldmesh_sidecar_files [glob -nocomplain [file join [pwd] fieldmesh *.v]]
if {{[llength $fieldmesh_sidecar_files] == 0}} {{
  error "FieldMesh sidecar overlay requires copied fieldmesh/*.v files"
}}
add_files -norecurse $fieldmesh_sidecar_files
update_compile_order -fileset sources_1
{BD_FILES_END}
"""


def render_control_overlay() -> str:
    return f"""
{BD_CTRL_BEGIN}
create_bd_cell -type module -reference fieldmesh_sidecar_ctrl_axi_lite fieldmesh_ctrl
ad_connect sys_cpu_clk fieldmesh_ctrl/s_axi_aclk
ad_connect sys_cpu_resetn fieldmesh_ctrl/s_axi_aresetn
ad_cpu_interconnect 0x43C00000 fieldmesh_ctrl
ad_cpu_interrupt ps-11 mb-11 fieldmesh_ctrl/irq
{BD_CTRL_END}
"""


def render_bridge_overlay(park_byte_ports: bool, rf_engine_overlay: bool = False) -> str:
    byte_parking = ""
    packet_loopback = """ad_connect fieldmesh_axis_bridge/m_tx_packet_tvalid fieldmesh_axis_bridge/s_rx_packet_tvalid
ad_connect fieldmesh_axis_bridge/s_rx_packet_tready fieldmesh_axis_bridge/m_tx_packet_tready
ad_connect fieldmesh_axis_bridge/m_tx_packet_tdata fieldmesh_axis_bridge/s_rx_packet_tdata
ad_connect fieldmesh_axis_bridge/m_tx_packet_tlast fieldmesh_axis_bridge/s_rx_packet_tlast
ad_connect fieldmesh_axis_bridge/m_tx_packet_tuser_class fieldmesh_axis_bridge/s_rx_packet_tuser_class
ad_connect fieldmesh_axis_bridge/m_tx_packet_tuser_mode fieldmesh_axis_bridge/s_rx_packet_tuser_mode
ad_connect fieldmesh_axis_bridge/m_tx_packet_tuser_stream_id fieldmesh_axis_bridge/s_rx_packet_tuser_stream_id
ad_connect fieldmesh_axis_bridge/m_tx_packet_tuser_slot fieldmesh_axis_bridge/s_rx_packet_tuser_slot
"""
    if park_byte_ports:
        byte_parking = """ad_connect GND fieldmesh_axis_bridge/s_tx_axis_tvalid
ad_connect GND fieldmesh_axis_bridge/s_tx_axis_tdata
ad_connect GND fieldmesh_axis_bridge/s_tx_axis_tlast
ad_connect VCC fieldmesh_axis_bridge/m_rx_axis_tready
"""
        packet_loopback = """ad_connect VCC fieldmesh_axis_bridge/m_tx_packet_tready
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tvalid
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tdata
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tlast
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_class
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_mode
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_stream_id
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_slot
"""
    elif rf_engine_overlay:
        packet_loopback = """ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tvalid
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tdata
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tlast
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_class
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_mode
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_stream_id
ad_connect GND fieldmesh_axis_bridge/s_rx_packet_tuser_slot
"""
    return f"""
{BD_BRIDGE_BEGIN}
create_bd_cell -type module -reference fieldmesh_sidecar_axis_bridge fieldmesh_axis_bridge
ad_connect sys_cpu_clk fieldmesh_axis_bridge/clk
ad_connect sys_cpu_reset fieldmesh_axis_bridge/rst
ad_connect VCC fieldmesh_axis_bridge/enable
{byte_parking.rstrip()}
{packet_loopback.rstrip()}
{BD_BRIDGE_END}
"""


def render_dma_overlay() -> str:
    return f"""
{BD_DMA_BEGIN}
ad_ip_parameter sys_ps7 CONFIG.PCW_USE_S_AXI_HP0 {{1}}
ad_ip_parameter sys_ps7 CONFIG.PCW_USE_S_AXI_HP3 {{1}}

ad_ip_instance axi_dmac fieldmesh_tx_dma
ad_ip_parameter fieldmesh_tx_dma CONFIG.DMA_TYPE_SRC 0
ad_ip_parameter fieldmesh_tx_dma CONFIG.DMA_TYPE_DEST 1
ad_ip_parameter fieldmesh_tx_dma CONFIG.CYCLIC 0
ad_ip_parameter fieldmesh_tx_dma CONFIG.AXI_SLICE_SRC 0
ad_ip_parameter fieldmesh_tx_dma CONFIG.AXI_SLICE_DEST 0
ad_ip_parameter fieldmesh_tx_dma CONFIG.DMA_2D_TRANSFER 0
ad_ip_parameter fieldmesh_tx_dma CONFIG.DMA_DATA_WIDTH_DEST 16

ad_ip_instance axi_dmac fieldmesh_rx_dma
ad_ip_parameter fieldmesh_rx_dma CONFIG.DMA_TYPE_SRC 1
ad_ip_parameter fieldmesh_rx_dma CONFIG.DMA_TYPE_DEST 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.CYCLIC 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.SYNC_TRANSFER_START 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.AXI_SLICE_SRC 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.AXI_SLICE_DEST 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.DMA_2D_TRANSFER 0
ad_ip_parameter fieldmesh_rx_dma CONFIG.DMA_DATA_WIDTH_SRC 16

create_bd_cell -type module -reference fieldmesh_axis16_byte_adapter fieldmesh_axis16_adapter
ad_connect sys_cpu_clk fieldmesh_axis16_adapter/clk
ad_connect sys_cpu_reset fieldmesh_axis16_adapter/rst
ad_connect VCC fieldmesh_axis16_adapter/enable

ad_connect fieldmesh_tx_dma/m_axis fieldmesh_axis16_adapter/s_axis16
ad_connect fieldmesh_axis16_adapter/m_axis8 fieldmesh_axis_bridge/s_tx_axis
ad_connect fieldmesh_axis_bridge/m_rx_axis fieldmesh_axis16_adapter/s_axis8
ad_connect fieldmesh_axis16_adapter/m_axis16 fieldmesh_rx_dma/s_axis

ad_cpu_interconnect 0x43C10000 fieldmesh_tx_dma
ad_cpu_interconnect 0x43C20000 fieldmesh_rx_dma

ad_connect sys_cpu_clk sys_ps7/S_AXI_HP0_ACLK
ad_connect fieldmesh_rx_dma/m_dest_axi sys_ps7/S_AXI_HP0
create_bd_addr_seg -range 0x40000000 -offset 0x00000000 \\
                    [get_bd_addr_spaces fieldmesh_rx_dma/m_dest_axi] \\
                    [get_bd_addr_segs sys_ps7/S_AXI_HP0/HP0_DDR_LOWOCM] \\
                    SEG_sys_ps7_HP0_DDR_LOWOCM_fieldmesh_rx

ad_connect sys_cpu_clk sys_ps7/S_AXI_HP3_ACLK
ad_connect fieldmesh_tx_dma/m_src_axi sys_ps7/S_AXI_HP3
create_bd_addr_seg -range 0x40000000 -offset 0x00000000 \\
                    [get_bd_addr_spaces fieldmesh_tx_dma/m_src_axi] \\
                    [get_bd_addr_segs sys_ps7/S_AXI_HP3/HP3_DDR_LOWOCM] \\
                    SEG_sys_ps7_HP3_DDR_LOWOCM_fieldmesh_tx

ad_connect sys_cpu_clk fieldmesh_tx_dma/m_src_axi_aclk
ad_connect sys_cpu_clk fieldmesh_tx_dma/m_axis_aclk
ad_connect sys_cpu_resetn fieldmesh_tx_dma/m_src_axi_aresetn
ad_connect sys_cpu_clk fieldmesh_rx_dma/m_dest_axi_aclk
ad_connect sys_cpu_clk fieldmesh_rx_dma/s_axis_aclk
ad_connect sys_cpu_resetn fieldmesh_rx_dma/m_dest_axi_aresetn

ad_cpu_interrupt ps-9 mb-9 fieldmesh_tx_dma/irq
ad_cpu_interrupt ps-10 mb-10 fieldmesh_rx_dma/irq
{BD_DMA_END}
"""


def render_rf_engine_overlay() -> str:
    return f"""
{BD_RF_ENGINE_BEGIN}
create_bd_cell -type module -reference fieldmesh_bpsk_iq_symbolizer fieldmesh_bpsk_symbolizer
ad_connect sys_cpu_clk fieldmesh_bpsk_symbolizer/clk
ad_connect sys_cpu_reset fieldmesh_bpsk_symbolizer/rst
ad_connect VCC fieldmesh_bpsk_symbolizer/enable

create_bd_cell -type module -reference fieldmesh_iq_tx_guard fieldmesh_iq_tx_guard
ad_connect sys_cpu_clk fieldmesh_iq_tx_guard/clk
ad_connect sys_cpu_reset fieldmesh_iq_tx_guard/rst
ad_connect VCC fieldmesh_iq_tx_guard/enable
ad_connect GND fieldmesh_iq_tx_guard/tx_enable
ad_connect GND fieldmesh_iq_tx_guard/tx_armed
ad_connect GND fieldmesh_iq_tx_guard/schedule_enable
ad_connect GND fieldmesh_iq_tx_guard/current_epoch
ad_connect GND fieldmesh_iq_tx_guard/current_slot
ad_connect GND fieldmesh_iq_tx_guard/tx_epoch
ad_connect GND fieldmesh_iq_tx_guard/tx_slot

ad_connect fieldmesh_axis_bridge/m_tx_packet_tvalid fieldmesh_bpsk_symbolizer/s_axis_tvalid
ad_connect fieldmesh_bpsk_symbolizer/s_axis_tready fieldmesh_axis_bridge/m_tx_packet_tready
ad_connect fieldmesh_axis_bridge/m_tx_packet_tdata fieldmesh_bpsk_symbolizer/s_axis_tdata
ad_connect fieldmesh_axis_bridge/m_tx_packet_tlast fieldmesh_bpsk_symbolizer/s_axis_tlast

# The symbolizer and TX guard are BD-visible here, but the guard is deliberately
# unarmed and its IQ output is parked behind the RF packet-engine boundary. No
# AD936x TX path, IIO buffer, RF tuning, or TX-enable driver is connected by
# this overlay.
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tvalid fieldmesh_iq_tx_guard/s_axis_tvalid
ad_connect fieldmesh_iq_tx_guard/s_axis_tready fieldmesh_bpsk_symbolizer/m_axis_tready
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tlast fieldmesh_iq_tx_guard/s_axis_tlast
ad_connect VCC fieldmesh_iq_tx_guard/m_axis_tready
{BD_RF_ENGINE_END}
"""


def patch_system_bd(
    text: str,
    control_overlay: bool,
    bridge_overlay: bool,
    dma_overlay: bool,
    rf_engine_overlay: bool,
) -> tuple[str, bool]:
    if not control_overlay and not bridge_overlay and not dma_overlay and not rf_engine_overlay:
        return text, False
    if rf_engine_overlay:
        dma_overlay = True
    if dma_overlay:
        control_overlay = True
        bridge_overlay = True
    blocks = []
    if BD_FILES_BEGIN not in text:
        blocks.append(render_bd_files_overlay())
    if "ad_cpu_interconnect 0x43C00000" in text or "fieldmesh_ctrl/irq" in text:
        if BD_CTRL_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh control overlay appears partially present")
    if "fieldmesh_axis_bridge" in text:
        if BD_BRIDGE_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh bridge overlay appears partially present")
        if dma_overlay and BD_DMA_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh bridge overlay is already parked; start from a clean copied HDL tree for --dma-overlay")
    if ("fieldmesh_tx_dma" in text or "fieldmesh_rx_dma" in text) and BD_DMA_BEGIN not in text:
        raise SystemExit("system_bd.tcl: FieldMesh DMA overlay appears partially present")
    if (
        "fieldmesh_bpsk_symbolizer" in text
        or "fieldmesh_iq_tx_guard" in text
    ) and BD_RF_ENGINE_BEGIN not in text:
        raise SystemExit("system_bd.tcl: FieldMesh RF packet engine overlay appears partially present")
    if control_overlay and BD_CTRL_BEGIN not in text:
        if "ad_cpu_interconnect 0x7C420000 axi_ad9361_dac_dma" not in text:
            raise SystemExit("system_bd.tcl: expected ADI DMA interconnect anchor not found")
        if "ad_cpu_interrupt ps-12 mb-12 axi_ad9361_dac_dma/irq" not in text:
            raise SystemExit("system_bd.tcl: expected ADI DMA interrupt anchor not found")
        blocks.append(render_control_overlay())
    if bridge_overlay and BD_BRIDGE_BEGIN not in text:
        blocks.append(render_bridge_overlay(park_byte_ports=not dma_overlay, rf_engine_overlay=rf_engine_overlay))
    if dma_overlay and BD_DMA_BEGIN not in text:
        blocks.append(render_dma_overlay())
    if rf_engine_overlay and BD_RF_ENGINE_BEGIN not in text:
        blocks.append(render_rf_engine_overlay())
    if not blocks:
        return text, False
    return text.rstrip() + "".join(blocks) + "\n", True


def load_plan(repo_root: Path, variant_name: str, system_bd: Path) -> dict:
    return sidecar_plan.build_plan(
        [(variant_name, system_bd)],
        check_sidecar=True,
        repo_root=repo_root,
        check_rtl=True,
        check_hp_policy=True,
    )


def apply_patch(
    repo_root: Path,
    hdl_tree: Path,
    variant_name: str,
    apply: bool,
    control_overlay: bool,
    bridge_overlay: bool,
    dma_overlay: bool,
    rf_engine_overlay: bool,
) -> dict:
    if rf_engine_overlay:
        dma_overlay = True
    if dma_overlay:
        control_overlay = True
        bridge_overlay = True

    project_dir = hdl_tree / "projects" / "pluto"
    system_bd = project_dir / "system_bd.tcl"
    system_project = project_dir / "system_project.tcl"
    makefile = project_dir / "Makefile"

    for required in (system_bd, system_project, makefile):
        if not required.is_file():
            raise SystemExit(f"{required}: not found")

    plan = load_plan(repo_root, variant_name, system_bd)
    rel_files = [rel_rtl_name(path) for path in sidecar_plan.REQUIRED_RTL]
    copied_files = []
    for src_rel, dst_rel in zip(sidecar_plan.REQUIRED_RTL, rel_files, strict=True):
        src = repo_root / src_rel
        dst = project_dir / dst_rel
        copied_files.append(str(dst))
        if apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

    project_text = system_project.read_text()
    patched_project, project_changed = patch_system_project(project_text, rel_files)
    make_text = makefile.read_text()
    patched_make, make_changed = patch_makefile(make_text, rel_files)
    system_bd_text = system_bd.read_text()
    patched_system_bd, system_bd_changed = patch_system_bd(
        system_bd_text,
        control_overlay,
        bridge_overlay,
        dma_overlay,
        rf_engine_overlay,
    )

    if apply:
        if project_changed:
            system_project.write_text(patched_project)
        if make_changed:
            makefile.write_text(patched_make)
        if system_bd_changed:
            system_bd.write_text(patched_system_bd)

    post_plan_ok = True
    if apply and (control_overlay or bridge_overlay or dma_overlay or rf_engine_overlay):
        post_plan = load_plan(repo_root, variant_name, system_bd)
        post_plan_ok = bool(post_plan["ok"])

    return {
        "event": "fieldmesh_vivado_overlay_patch",
        "ok": True,
        "applied": apply,
        "bridge_overlay": bridge_overlay,
        "control_overlay": control_overlay,
        "dma_overlay": dma_overlay,
        "rf_engine_overlay": rf_engine_overlay,
        "variant": variant_name,
        "hdl_tree": str(hdl_tree),
        "system_bd": str(system_bd),
        "system_bd_changed": system_bd_changed,
        "system_project_changed": project_changed,
        "makefile_changed": make_changed,
        "copied_rtl_files": copied_files,
        "sidecar_ok": plan["ok"],
        "post_patch_sidecar_ok": post_plan_ok,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd(), help="repository root containing rtl/fieldmesh")
    parser.add_argument("--hdl-tree", type=Path, required=True, help="copied Pluto HDL tree to patch")
    parser.add_argument("--variant-name", default="fieldmesh", help="variant label for checks")
    parser.add_argument("--apply", action="store_true", help="write changes; default is dry-run JSON only")
    parser.add_argument(
        "--control-overlay",
        action="store_true",
        help="also add an idempotent fieldmesh_ctrl BD module/address/IRQ overlay to system_bd.tcl",
    )
    parser.add_argument(
        "--bridge-overlay",
        action="store_true",
        help="also add an idempotent fieldmesh_axis_bridge BD module for the sidecar byte-stream boundary",
    )
    parser.add_argument(
        "--dma-overlay",
        action="store_true",
        help="also add provisional fieldmesh_tx_dma/fieldmesh_rx_dma axi_dmac cells and connect them to the bridge byte ports",
    )
    parser.add_argument(
        "--rf-engine-overlay",
        action="store_true",
        help="also add non-transmitting fieldmesh_bpsk_symbolizer and IQ TX guard cells behind the sidecar DMA/bridge TX packet path",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = apply_patch(
        args.repo_root.resolve(),
        args.hdl_tree.resolve(),
        args.variant_name,
        args.apply,
        args.control_overlay,
        args.bridge_overlay,
        args.dma_overlay,
        args.rf_engine_overlay,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
