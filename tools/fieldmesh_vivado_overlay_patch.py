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
BD_RING_BEGIN = "# FieldMesh firmware ring overlay: begin"
BD_RING_END = "# FieldMesh firmware ring overlay: end"
BD_DMA_BEGIN = "# FieldMesh sidecar DMA overlay: begin"
BD_DMA_END = "# FieldMesh sidecar DMA overlay: end"
BD_RF_ENGINE_BEGIN = "# FieldMesh RF packet engine overlay: begin"
BD_RF_ENGINE_END = "# FieldMesh RF packet engine overlay: end"
PROJECT_THREAD_CAP_BEGIN = "# FieldMesh Vivado thread cap: begin"
PROJECT_THREAD_CAP_END = "# FieldMesh Vivado thread cap: end"
BD_GNSS_UART_BEGIN = "# FieldMesh GNSS UART EMIO overlay: begin"
BD_GNSS_UART_END = "# FieldMesh GNSS UART EMIO overlay: end"
BD_GNSS_PPS_BEGIN = "# FieldMesh GNSS PPS EMIO overlay: begin"
BD_GNSS_PPS_END = "# FieldMesh GNSS PPS EMIO overlay: end"
RF_ENGINE_XDC = "constraints/fieldmesh_axis_async_fifo_cdc.xdc"
GNSS_UART_XDC_REL_TEMPLATE = "fieldmesh/fieldmesh_gnss_uart_{variant}.xdc"
GNSS_PPS_XDC_REL_TEMPLATE = "fieldmesh/fieldmesh_gnss_pps_{variant}.xdc"
GNSS_UART_XDC = {
    "z203": """# FieldMesh GNSS UART EMIO constraints for SDR-Z203.
# Source evidence: vendor gps_transfer example routes UART_0_rxd/UART_0_txd
# to K21/L21 with LVCMOS18. Use only on matching Z203 hardware.
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS18} [get_ports gnss_uart0_rxd]
set_property -dict {PACKAGE_PIN L21 IOSTANDARD LVCMOS18} [get_ports gnss_uart0_txd]
""",
    "z103": """# FieldMesh GNSS UART EMIO constraints for SDR-Z103.
# Source evidence: SDR-Z103 schematic text extraction maps GPS_TXD/GPS_RXD
# to Zynq package pins A20/B19 in bank 35. Use only on matching Z103 hardware.
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS18} [get_ports gnss_uart0_rxd]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD LVCMOS18} [get_ports gnss_uart0_txd]
""",
}
GNSS_PPS_XDC = {
    "z203": """# FieldMesh GNSS PPS EMIO constraint for SDR-Z203.
# Source evidence: SDR-Z203 schematic text extraction maps GPS_PPS to Zynq
# package pin M21 in bank 34. Use only on matching Z203 hardware.
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS18} [get_ports gnss_pps]
""",
    "z103": """# FieldMesh GNSS PPS EMIO constraint for SDR-Z103.
# Source evidence: SDR-Z103 schematic text extraction maps GPS_PPS to Zynq
# package pin B20 in bank 35. Use only on matching Z103 hardware.
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS18} [get_ports gnss_pps]
""",
}


def gnss_xdc(variant_name: str, kind: str) -> tuple[str, str]:
    if kind == "uart":
        table = GNSS_UART_XDC
        template = GNSS_UART_XDC_REL_TEMPLATE
    elif kind == "pps":
        table = GNSS_PPS_XDC
        template = GNSS_PPS_XDC_REL_TEMPLATE
    else:
        raise ValueError(kind)
    try:
        return template.format(variant=variant_name), table[variant_name]
    except KeyError as exc:
        raise SystemExit(f"{kind} GNSS EMIO has verified pins only for z203/z103, not {variant_name}") from exc


def rel_rtl_name(rtl_path: str) -> str:
    return f"fieldmesh/{Path(rtl_path).name}"


def sidecar_block(plan: dict, name: str) -> dict:
    try:
        return next(block for block in plan["sidecar_blocks"] if block["name"] == name)
    except StopIteration as exc:
        raise SystemExit(f"sidecar plan missing {name}") from exc


def patch_system_project(text: str, rel_files: list[str], rel_xdc_files: list[str]) -> tuple[str, bool]:
    changed = False
    if PROJECT_THREAD_CAP_BEGIN not in text:
        thread_cap = "\n".join(
            [
                PROJECT_THREAD_CAP_BEGIN,
                "if {[info exists ::env(FIELDMESH_VIVADO_MAX_THREADS)]} {",
                "  set_param general.maxThreads $::env(FIELDMESH_VIVADO_MAX_THREADS)",
                "}",
                PROJECT_THREAD_CAP_END,
                "",
            ]
        )
        text = thread_cap + text
        changed = True

    all_project_files = rel_files + rel_xdc_files
    missing_project_files = [rel for rel in all_project_files if f'"{rel}"' not in text]
    if not missing_project_files:
        return text, changed

    lines = text.splitlines()
    marker = '  "$ad_hdl_dir/library/common/ad_iobuf.v"]'
    if marker in lines:
        idx = lines.index(marker)
        new_lines = lines[:idx]
        new_lines.append('  "$ad_hdl_dir/library/common/ad_iobuf.v" \\')
        for rel in missing_project_files[:-1]:
            new_lines.append(f'  "{rel}" \\')
        new_lines.append(f'  "{missing_project_files[-1]}"]')
        new_lines.extend(lines[idx + 1 :])
        return "\n".join(new_lines) + "\n", True

    try:
        idx = next(
            index
            for index, line in reversed(list(enumerate(lines)))
            if line.strip().endswith("]") and line.strip().startswith('"')
        )
    except StopIteration as exc:
        raise SystemExit("system_project.tcl: expected project file list terminator not found") from exc

    new_lines = lines[:idx]
    new_lines.append(lines[idx].replace('"]', '" \\'))
    for rel in missing_project_files[:-1]:
        new_lines.append(f'  "{rel}" \\')
    new_lines.append(f'  "{missing_project_files[-1]}"]')
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


def render_control_overlay(
    plan: dict,
    rf_guard_defaults: bool = True,
    fw_dma_defaults: bool = True,
) -> str:
    ctrl = sidecar_block(plan, "fieldmesh_ctrl")
    rf_guard_tieoffs = ""
    if rf_guard_defaults:
        rf_guard_tieoffs = """ad_connect GND fieldmesh_ctrl/rf_guard_pass_sample_count
ad_connect GND fieldmesh_ctrl/rf_guard_pass_packet_count
ad_connect GND fieldmesh_ctrl/rf_guard_blocked_cycle_count
ad_connect GND fieldmesh_ctrl/rf_guard_drop_late_sample_count
ad_connect GND fieldmesh_ctrl/rf_guard_drop_late_packet_count
ad_connect GND fieldmesh_ctrl/rf_guard_fault
ad_connect GND fieldmesh_ctrl/rf_dac_sample_count
ad_connect GND fieldmesh_ctrl/rf_dac_packet_count
ad_connect GND fieldmesh_ctrl/rf_dac_underflow_count
ad_connect GND fieldmesh_ctrl/rf_dac_active
"""
    fw_dma_tieoffs = ""
    if fw_dma_defaults:
        fw_dma_tieoffs = """ad_connect GND fieldmesh_ctrl/fw_dma_mac_scheduler_active
ad_connect GND fieldmesh_ctrl/fw_dma_pump_done
ad_connect GND fieldmesh_ctrl/fw_dma_pump_drained_empty
ad_connect GND fieldmesh_ctrl/fw_dma_pump_budget_exhausted
ad_connect GND fieldmesh_ctrl/fw_dma_service_accepted
ad_connect GND fieldmesh_ctrl/fw_dma_service_queued_count
ad_connect GND fieldmesh_ctrl/fw_dma_service_selected_word
ad_connect GND fieldmesh_ctrl/fw_dma_tx_parser_packet_count
ad_connect GND fieldmesh_ctrl/fw_dma_tx_parser_byte_count
ad_connect GND fieldmesh_ctrl/fw_dma_tx_parser_drop_count
ad_connect GND fieldmesh_ctrl/fw_dma_tx_parser_fault
ad_connect GND fieldmesh_ctrl/fw_dma_ingress_packet_count
ad_connect GND fieldmesh_ctrl/fw_dma_ingress_byte_count
ad_connect GND fieldmesh_ctrl/fw_dma_ingress_desc_publish_count
ad_connect GND fieldmesh_ctrl/fw_dma_ingress_drop_count
ad_connect GND fieldmesh_ctrl/fw_dma_ingress_fault
ad_connect GND fieldmesh_ctrl/fw_dma_egress_packet_count
ad_connect GND fieldmesh_ctrl/fw_dma_egress_byte_count
ad_connect GND fieldmesh_ctrl/fw_dma_egress_drop_count
ad_connect GND fieldmesh_ctrl/fw_dma_egress_fault
ad_connect GND fieldmesh_ctrl/fw_dma_mac_tick_count
ad_connect GND fieldmesh_ctrl/fw_dma_mac_pump_start_count
ad_connect GND fieldmesh_ctrl/fw_dma_mac_pump_done_count
ad_connect GND fieldmesh_ctrl/fw_dma_bram_crc_error_count
ad_connect GND fieldmesh_ctrl/fw_dma_bram_bounds_error_count
ad_connect GND fieldmesh_ctrl/fw_dma_bram_error_count
"""
    return f"""
{BD_CTRL_BEGIN}
create_bd_cell -type module -reference fieldmesh_sidecar_ctrl_axi_lite fieldmesh_ctrl
ad_connect sys_cpu_clk fieldmesh_ctrl/s_axi_aclk
ad_connect sys_cpu_resetn fieldmesh_ctrl/s_axi_aresetn
{rf_guard_tieoffs.rstrip()}
{fw_dma_tieoffs.rstrip()}
ad_cpu_interconnect {ctrl["address"]} fieldmesh_ctrl
ad_cpu_interrupt {ctrl["irq"]} fieldmesh_ctrl/irq
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


def render_ring_overlay(plan: dict, variant_name: str) -> str:
    ring = sidecar_block(plan, "fieldmesh_ring")
    service_parameter = ""
    if variant_name == "z103":
        service_parameter = (
            "set_property -dict [list CONFIG.ENABLE_PL_SERVICE {0}] "
            "[get_bd_cells fieldmesh_ring]\n"
        )
    return f"""
{BD_RING_BEGIN}
create_bd_cell -type module -reference fieldmesh_firmware_ring_axi_lite fieldmesh_ring
{service_parameter.rstrip()}
ad_connect sys_cpu_clk fieldmesh_ring/s_axi_aclk
ad_connect sys_cpu_resetn fieldmesh_ring/s_axi_aresetn
ad_cpu_interconnect {ring["address"]} fieldmesh_ring
ad_cpu_interrupt {ring["irq"]} fieldmesh_ring/irq
{BD_RING_END}
"""


def render_dma_overlay(plan: dict, use_firmware_endpoint: bool, rf_engine_endpoint: bool = False) -> str:
    tx_dma = sidecar_block(plan, "fieldmesh_tx_dma")
    rx_dma = sidecar_block(plan, "fieldmesh_rx_dma")
    if use_firmware_endpoint:
        rf_broadcast = ""
        if rf_engine_endpoint:
            rf_broadcast = """
create_bd_cell -type module -reference fieldmesh_axis_byte_broadcast2 fieldmesh_fw_dma_rf_broadcast
ad_connect sys_cpu_clk fieldmesh_fw_dma_rf_broadcast/clk
ad_connect sys_cpu_reset fieldmesh_fw_dma_rf_broadcast/rst
ad_connect VCC fieldmesh_fw_dma_rf_broadcast/enable
ad_connect fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_fw_dma_rf_broadcast/s_axis
ad_connect fieldmesh_fw_dma_rf_broadcast/m0_axis fieldmesh_axis16_adapter/s_axis8
"""
        packet_path = """
create_bd_cell -type module -reference fieldmesh_firmware_axis_dma_endpoint fieldmesh_fw_dma_endpoint
set_property -dict [list CONFIG.AUTO_EGRESS {1}] [get_bd_cells fieldmesh_fw_dma_endpoint]
ad_connect sys_cpu_clk fieldmesh_fw_dma_endpoint/clk
ad_connect sys_cpu_reset fieldmesh_fw_dma_endpoint/rst
ad_connect fieldmesh_ctrl/fw_dma_enable fieldmesh_fw_dma_endpoint/enable
ad_connect fieldmesh_ctrl/fw_dma_ingress_enable fieldmesh_fw_dma_endpoint/ingress_enable
ad_connect fieldmesh_ctrl/fw_dma_egress_enable fieldmesh_fw_dma_endpoint/egress_enable
ad_connect GND fieldmesh_fw_dma_endpoint/egress_start
ad_connect GND fieldmesh_fw_dma_endpoint/egress_start_slot
ad_connect fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index
ad_connect fieldmesh_ctrl/fw_dma_mcs fieldmesh_fw_dma_endpoint/mcs
ad_connect fieldmesh_ctrl/fw_dma_retry_budget fieldmesh_fw_dma_endpoint/retry_budget
ad_connect fieldmesh_ctrl/fw_dma_descriptor_flags fieldmesh_fw_dma_endpoint/descriptor_flags
ad_connect fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed
ad_connect fieldmesh_ctrl/fw_dma_mac_scheduler_enable fieldmesh_fw_dma_endpoint/mac_scheduler_enable
ad_connect fieldmesh_ctrl/fw_dma_mac_tick_enable fieldmesh_fw_dma_endpoint/mac_tick
ad_connect fieldmesh_ctrl/fw_dma_mac_stop fieldmesh_fw_dma_endpoint/mac_stop
ad_connect fieldmesh_ctrl/fw_dma_mac_service_budget fieldmesh_fw_dma_endpoint/mac_service_budget
ad_connect fieldmesh_fw_dma_endpoint/mac_scheduler_active fieldmesh_ctrl/fw_dma_mac_scheduler_active
ad_connect fieldmesh_fw_dma_endpoint/pump_done fieldmesh_ctrl/fw_dma_pump_done
ad_connect fieldmesh_fw_dma_endpoint/pump_drained_empty fieldmesh_ctrl/fw_dma_pump_drained_empty
ad_connect fieldmesh_fw_dma_endpoint/pump_budget_exhausted fieldmesh_ctrl/fw_dma_pump_budget_exhausted
ad_connect fieldmesh_fw_dma_endpoint/service_accepted fieldmesh_ctrl/fw_dma_service_accepted
ad_connect fieldmesh_fw_dma_endpoint/service_queued_count fieldmesh_ctrl/fw_dma_service_queued_count
ad_connect fieldmesh_fw_dma_endpoint/service_selected_word fieldmesh_ctrl/fw_dma_service_selected_word
ad_connect fieldmesh_fw_dma_endpoint/tx_parser_packet_count fieldmesh_ctrl/fw_dma_tx_parser_packet_count
ad_connect fieldmesh_fw_dma_endpoint/tx_parser_byte_count fieldmesh_ctrl/fw_dma_tx_parser_byte_count
ad_connect fieldmesh_fw_dma_endpoint/tx_parser_drop_count fieldmesh_ctrl/fw_dma_tx_parser_drop_count
ad_connect fieldmesh_fw_dma_endpoint/tx_parser_fault fieldmesh_ctrl/fw_dma_tx_parser_fault
ad_connect fieldmesh_fw_dma_endpoint/ingress_packet_count fieldmesh_ctrl/fw_dma_ingress_packet_count
ad_connect fieldmesh_fw_dma_endpoint/ingress_byte_count fieldmesh_ctrl/fw_dma_ingress_byte_count
ad_connect fieldmesh_fw_dma_endpoint/ingress_desc_publish_count fieldmesh_ctrl/fw_dma_ingress_desc_publish_count
ad_connect fieldmesh_fw_dma_endpoint/ingress_drop_count fieldmesh_ctrl/fw_dma_ingress_drop_count
ad_connect fieldmesh_fw_dma_endpoint/ingress_fault fieldmesh_ctrl/fw_dma_ingress_fault
ad_connect fieldmesh_fw_dma_endpoint/egress_packet_count fieldmesh_ctrl/fw_dma_egress_packet_count
ad_connect fieldmesh_fw_dma_endpoint/egress_byte_count fieldmesh_ctrl/fw_dma_egress_byte_count
ad_connect fieldmesh_fw_dma_endpoint/egress_drop_count fieldmesh_ctrl/fw_dma_egress_drop_count
ad_connect fieldmesh_fw_dma_endpoint/egress_fault fieldmesh_ctrl/fw_dma_egress_fault
ad_connect fieldmesh_fw_dma_endpoint/mac_tick_count fieldmesh_ctrl/fw_dma_mac_tick_count
ad_connect fieldmesh_fw_dma_endpoint/mac_pump_start_count fieldmesh_ctrl/fw_dma_mac_pump_start_count
ad_connect fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count
ad_connect fieldmesh_fw_dma_endpoint/bram_crc_error_count fieldmesh_ctrl/fw_dma_bram_crc_error_count
ad_connect fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count
ad_connect fieldmesh_fw_dma_endpoint/bram_error_count fieldmesh_ctrl/fw_dma_bram_error_count

ad_connect fieldmesh_tx_dma/m_axis fieldmesh_axis16_adapter/s_axis16
ad_connect fieldmesh_axis16_adapter/m_axis8 fieldmesh_fw_dma_endpoint/s_tx_dma
__FIELDMESH_FW_DMA_RX_ROUTE__
ad_connect fieldmesh_axis16_adapter/m_axis16 fieldmesh_rx_dma/s_axis
"""
        packet_path = packet_path.replace(
            "__FIELDMESH_FW_DMA_RX_ROUTE__",
            (
                rf_broadcast.rstrip()
                if rf_engine_endpoint
                else "ad_connect fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_axis16_adapter/s_axis8"
            ),
        )
    else:
        packet_path = """
ad_connect fieldmesh_tx_dma/m_axis fieldmesh_axis16_adapter/s_axis16
ad_connect fieldmesh_axis16_adapter/m_axis8 fieldmesh_axis_bridge/s_tx_axis
ad_connect fieldmesh_axis_bridge/m_rx_axis fieldmesh_axis16_adapter/s_axis8
ad_connect fieldmesh_axis16_adapter/m_axis16 fieldmesh_rx_dma/s_axis
"""
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
{packet_path.rstrip()}

ad_cpu_interconnect {tx_dma["address"]} fieldmesh_tx_dma
ad_cpu_interconnect {rx_dma["address"]} fieldmesh_rx_dma

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

ad_cpu_interrupt {tx_dma["irq"]} fieldmesh_tx_dma/irq
ad_cpu_interrupt {rx_dma["irq"]} fieldmesh_rx_dma/irq
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
ad_connect fieldmesh_ctrl/rf_tx_enable fieldmesh_iq_tx_guard/tx_enable
ad_connect fieldmesh_ctrl/rf_tx_armed fieldmesh_iq_tx_guard/tx_armed
ad_connect fieldmesh_ctrl/rf_schedule_enable fieldmesh_iq_tx_guard/schedule_enable
ad_connect fieldmesh_ctrl/rf_current_epoch fieldmesh_iq_tx_guard/current_epoch
ad_connect fieldmesh_ctrl/rf_current_slot fieldmesh_iq_tx_guard/current_slot
ad_connect fieldmesh_ctrl/rf_tx_epoch fieldmesh_iq_tx_guard/tx_epoch
ad_connect fieldmesh_ctrl/rf_tx_slot fieldmesh_iq_tx_guard/tx_slot
ad_connect fieldmesh_iq_tx_guard/pass_sample_count fieldmesh_ctrl/rf_guard_pass_sample_count
ad_connect fieldmesh_iq_tx_guard/pass_packet_count fieldmesh_ctrl/rf_guard_pass_packet_count
ad_connect fieldmesh_iq_tx_guard/blocked_cycle_count fieldmesh_ctrl/rf_guard_blocked_cycle_count
ad_connect fieldmesh_iq_tx_guard/drop_late_sample_count fieldmesh_ctrl/rf_guard_drop_late_sample_count
ad_connect fieldmesh_iq_tx_guard/drop_late_packet_count fieldmesh_ctrl/rf_guard_drop_late_packet_count
ad_connect fieldmesh_iq_tx_guard/fault fieldmesh_ctrl/rf_guard_fault

ad_connect fieldmesh_fw_dma_rf_broadcast/m1_axis fieldmesh_bpsk_symbolizer/s_axis

# The symbolizer and TX guard are BD-visible here, and the guard is controlled
# by the existing sidecar AXI-lite control window. Packet bytes now come from
# the descriptor-validated firmware-DMA endpoint egress stream instead of the
# older sidecar bridge packet port. The guard still resets unarmed, and its IQ
# output is parked behind the RF packet-engine boundary. No IIO buffer, RF
# tuning, or TX-enable driver is connected by this overlay.
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tvalid fieldmesh_iq_tx_guard/s_axis_tvalid
ad_connect fieldmesh_iq_tx_guard/s_axis_tready fieldmesh_bpsk_symbolizer/m_axis_tready
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata
ad_connect fieldmesh_bpsk_symbolizer/m_axis_tlast fieldmesh_iq_tx_guard/s_axis_tlast

create_bd_cell -type module -reference fieldmesh_axis_async_fifo fieldmesh_iq_tx_cdc
ad_connect sys_cpu_clk fieldmesh_iq_tx_cdc/s_clk
ad_connect sys_cpu_reset fieldmesh_iq_tx_cdc/s_rst
ad_connect axi_ad9361/l_clk fieldmesh_iq_tx_cdc/m_clk
ad_connect axi_ad9361/rst fieldmesh_iq_tx_cdc/m_rst
ad_connect VCC fieldmesh_iq_tx_cdc/enable
ad_connect fieldmesh_iq_tx_guard/m_axis_tvalid fieldmesh_iq_tx_cdc/s_axis_tvalid
ad_connect fieldmesh_iq_tx_cdc/s_axis_tready fieldmesh_iq_tx_guard/m_axis_tready
ad_connect fieldmesh_iq_tx_guard/m_axis_tdata fieldmesh_iq_tx_cdc/s_axis_tdata
ad_connect fieldmesh_iq_tx_guard/m_axis_tlast fieldmesh_iq_tx_cdc/s_axis_tlast

create_bd_cell -type module -reference fieldmesh_iq_dac_driver fieldmesh_iq_dac_driver
ad_connect axi_ad9361/l_clk fieldmesh_iq_dac_driver/clk
ad_connect axi_ad9361/rst fieldmesh_iq_dac_driver/rst
ad_connect VCC fieldmesh_iq_dac_driver/enable
ad_connect fieldmesh_ctrl/rf_source_select fieldmesh_iq_dac_driver/select_fieldmesh
ad_connect axi_ad9361/dac_valid_i0 fieldmesh_iq_dac_driver/i_tick
ad_connect axi_ad9361/dac_valid_q0 fieldmesh_iq_dac_driver/q_tick
ad_connect tx_fir_interpolator/enable_out_0 fieldmesh_iq_dac_driver/i_gate
ad_connect tx_fir_interpolator/enable_out_1 fieldmesh_iq_dac_driver/q_gate
ad_connect tx_upack/fifo_rd_data_0 fieldmesh_iq_dac_driver/vnd_i_sample
ad_connect tx_upack/fifo_rd_data_1 fieldmesh_iq_dac_driver/vnd_q_sample
ad_connect fieldmesh_iq_tx_cdc/m_axis_tvalid fieldmesh_iq_dac_driver/s_axis_tvalid
ad_connect fieldmesh_iq_dac_driver/s_axis_tready fieldmesh_iq_tx_cdc/m_axis_tready
ad_connect fieldmesh_iq_tx_cdc/m_axis_tdata fieldmesh_iq_dac_driver/s_axis_tdata
ad_connect fieldmesh_iq_tx_cdc/m_axis_tlast fieldmesh_iq_dac_driver/s_axis_tlast
ad_connect fieldmesh_iq_dac_driver/sample_count fieldmesh_ctrl/rf_dac_sample_count
ad_connect fieldmesh_iq_dac_driver/packet_count fieldmesh_ctrl/rf_dac_packet_count
ad_connect fieldmesh_iq_dac_driver/underflow_count fieldmesh_ctrl/rf_dac_underflow_count
ad_connect fieldmesh_iq_dac_driver/active fieldmesh_ctrl/rf_dac_active

proc fieldmesh_disconnect_pin {{pin_name}} {{
  set pin [get_bd_pins -quiet $pin_name]
  if {{[llength $pin] != 1}} {{
    error "expected one pin to disconnect: $pin_name"
  }}
  foreach net [get_bd_nets -quiet -of_objects $pin] {{
    disconnect_bd_net $net $pin
  }}
}}

fieldmesh_disconnect_pin tx_fir_interpolator/data_in_0
fieldmesh_disconnect_pin tx_fir_interpolator/data_in_1
fieldmesh_disconnect_pin tx_upack/enable_0
fieldmesh_disconnect_pin tx_upack/enable_1

ad_connect fieldmesh_iq_dac_driver/out_i_sample tx_fir_interpolator/data_in_0
ad_connect fieldmesh_iq_dac_driver/out_q_sample tx_fir_interpolator/data_in_1
ad_connect fieldmesh_iq_dac_driver/upack_enable_i tx_upack/enable_0
ad_connect fieldmesh_iq_dac_driver/upack_enable_q tx_upack/enable_1
{BD_RF_ENGINE_END}
"""


def render_gnss_uart_overlay() -> str:
    return f"""
{BD_GNSS_UART_BEGIN}
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 UART_0
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_PERIPHERAL_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_UART0_IO {{EMIO}}
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_GRP_FULL_ENABLE 0
ad_ip_parameter sys_ps7 CONFIG.PCW_UART0_BAUD_RATE {{9600}}
ad_ip_parameter sys_ps7 CONFIG.PCW_UART_PERIPHERAL_VALID 1
ad_ip_parameter sys_ps7 CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {{100}}
ad_connect sys_ps7/UART_0 UART_0
{BD_GNSS_UART_END}
"""


def render_gnss_pps_overlay() -> str:
    return f"""
{BD_GNSS_PPS_BEGIN}
ad_ip_parameter sys_ps7 CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE 1
ad_ip_parameter sys_ps7 CONFIG.PCW_GPIO_EMIO_GPIO_IO 18
{BD_GNSS_PPS_END}
"""


def patch_system_bd(
    text: str,
    plan: dict,
    variant_name: str,
    control_overlay: bool,
    bridge_overlay: bool,
    dma_overlay: bool,
    rf_engine_overlay: bool,
    gnss_uart_emio: bool,
    gnss_pps_emio: bool,
) -> tuple[str, bool]:
    if (
        not control_overlay
        and not bridge_overlay
        and not dma_overlay
        and not rf_engine_overlay
        and not gnss_uart_emio
        and not gnss_pps_emio
    ):
        return text, False
    if rf_engine_overlay:
        dma_overlay = True
    if dma_overlay:
        control_overlay = True
        bridge_overlay = True
    ring_overlay = control_overlay
    blocks = []
    if BD_FILES_BEGIN not in text:
        blocks.append(render_bd_files_overlay())
    ctrl = sidecar_block(plan, "fieldmesh_ctrl")
    if f'ad_cpu_interconnect {ctrl["address"]}' in text or "fieldmesh_ctrl/irq" in text:
        if BD_CTRL_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh control overlay appears partially present")
    if "fieldmesh_axis_bridge" in text:
        if BD_BRIDGE_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh bridge overlay appears partially present")
        if dma_overlay and BD_DMA_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh bridge overlay is already parked; start from a clean copied HDL tree for --dma-overlay")
    if "fieldmesh_ring" in text:
        if BD_RING_BEGIN not in text:
            raise SystemExit("system_bd.tcl: FieldMesh firmware ring overlay appears partially present")
    if (
        "fieldmesh_tx_dma" in text
        or "fieldmesh_rx_dma" in text
        or "fieldmesh_fw_dma_endpoint" in text
    ) and BD_DMA_BEGIN not in text:
        raise SystemExit("system_bd.tcl: FieldMesh DMA overlay appears partially present")
    if (
        "fieldmesh_bpsk_symbolizer" in text
        or "fieldmesh_iq_tx_guard" in text
    ) and BD_RF_ENGINE_BEGIN not in text:
        raise SystemExit("system_bd.tcl: FieldMesh RF packet engine overlay appears partially present")
    if "sys_ps7/UART_0" in text and BD_GNSS_UART_BEGIN not in text:
        raise SystemExit("system_bd.tcl: GNSS UART overlay appears partially present")
    if "CONFIG.PCW_GPIO_EMIO_GPIO_IO 18" in text and BD_GNSS_PPS_BEGIN not in text:
        raise SystemExit("system_bd.tcl: GNSS PPS EMIO overlay appears partially present")
    if control_overlay and BD_CTRL_BEGIN not in text:
        if "ad_cpu_interconnect 0x7C420000 axi_ad9361_dac_dma" not in text:
            raise SystemExit("system_bd.tcl: expected ADI DMA interconnect anchor not found")
        if "ad_cpu_interrupt ps-12 mb-12 axi_ad9361_dac_dma/irq" not in text:
            raise SystemExit("system_bd.tcl: expected ADI DMA interrupt anchor not found")
        blocks.append(
            render_control_overlay(
                plan,
                rf_guard_defaults=not rf_engine_overlay,
                fw_dma_defaults=not dma_overlay,
            )
        )
    if bridge_overlay and BD_BRIDGE_BEGIN not in text:
        blocks.append(
            render_bridge_overlay(
                park_byte_ports=dma_overlay or not rf_engine_overlay,
                rf_engine_overlay=rf_engine_overlay,
            )
        )
    if ring_overlay and BD_RING_BEGIN not in text:
        blocks.append(render_ring_overlay(plan, variant_name))
    if dma_overlay and BD_DMA_BEGIN not in text:
        blocks.append(render_dma_overlay(plan, use_firmware_endpoint=True, rf_engine_endpoint=rf_engine_overlay))
    if rf_engine_overlay and BD_RF_ENGINE_BEGIN not in text:
        blocks.append(render_rf_engine_overlay())
    if gnss_uart_emio and BD_GNSS_UART_BEGIN not in text:
        blocks.append(render_gnss_uart_overlay())
    if gnss_pps_emio and BD_GNSS_PPS_BEGIN not in text:
        blocks.append(render_gnss_pps_overlay())
    if not blocks:
        return text, False
    return text.rstrip() + "".join(blocks) + "\n", True


def patch_system_top(text: str, gnss_uart_emio: bool, gnss_pps_emio: bool) -> tuple[str, bool]:
    if not gnss_uart_emio and not gnss_pps_emio:
        return text, False
    changed = False
    if gnss_uart_emio and ("gnss_uart0_rxd" not in text and "gnss_uart0_txd" not in text):
        port_marker = "  input           spi_miso\n  );"
        if port_marker not in text:
            raise SystemExit("system_top.v: expected spi_miso port anchor not found")
        text = text.replace(
            port_marker,
            "  input           spi_miso,\n"
            "  input           gnss_uart0_rxd,\n"
            "  output          gnss_uart0_txd\n"
            "  );",
            1,
        )
        inst_marker = "    .gpio_t (gpio_t),\n"
        if inst_marker not in text:
            raise SystemExit("system_top.v: expected system_wrapper gpio_t anchor not found")
        text = text.replace(
            inst_marker,
            "    .gpio_t (gpio_t),\n"
            "    .UART_0_rxd (gnss_uart0_rxd),\n"
            "    .UART_0_txd (gnss_uart0_txd),\n",
            1,
        )
        changed = True
    if gnss_pps_emio and "gnss_pps" not in text:
        port_marker = "  input           spi_miso"
        if port_marker not in text:
            raise SystemExit("system_top.v: expected spi_miso port anchor not found")
        text = text.replace(port_marker, "  input           gnss_pps,\n  input           spi_miso", 1)
        text = text.replace("wire    [16:0]  gpio_i;", "wire    [17:0]  gpio_i;", 1)
        text = text.replace("wire    [16:0]  gpio_o;", "wire    [17:0]  gpio_o;", 1)
        text = text.replace("wire    [16:0]  gpio_t;", "wire    [17:0]  gpio_t;", 1)
        assign_marker = "  assign gpio_i[16:14] = gpio_o[16:14];"
        if assign_marker not in text:
            raise SystemExit("system_top.v: expected GPIO tieoff anchor not found")
        text = text.replace(
            assign_marker,
            "  assign gpio_i[16:14] = gpio_o[16:14];\n"
            "  assign gpio_i[17] = gnss_pps;",
            1,
        )
        changed = True
    return text, changed


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
    gnss_uart_emio: bool,
    gnss_pps_emio: bool,
) -> dict:
    if rf_engine_overlay:
        dma_overlay = True
    if dma_overlay:
        control_overlay = True
        bridge_overlay = True

    project_dir = hdl_tree / "projects" / "pluto"
    system_bd = project_dir / "system_bd.tcl"
    system_project = project_dir / "system_project.tcl"
    system_top = project_dir / "system_top.v"
    makefile = project_dir / "Makefile"

    for required in (system_bd, system_project, system_top, makefile):
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

    rel_xdc_files = [rel_rtl_name(RF_ENGINE_XDC)] if rf_engine_overlay else []
    copied_xdc_files = []
    for src_rel, dst_rel in zip([RF_ENGINE_XDC] if rf_engine_overlay else [], rel_xdc_files, strict=True):
        src = repo_root / src_rel
        dst = project_dir / dst_rel
        copied_xdc_files.append(str(dst))
        if apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    if gnss_uart_emio:
        uart_xdc_rel, uart_xdc_text = gnss_xdc(variant_name, "uart")
        copied_xdc_files.append(str(project_dir / uart_xdc_rel))
        if apply:
            gnss_xdc_path = project_dir / uart_xdc_rel
            gnss_xdc_path.parent.mkdir(parents=True, exist_ok=True)
            gnss_xdc_path.write_text(uart_xdc_text)
        rel_xdc_files.append(uart_xdc_rel)
    if gnss_pps_emio:
        pps_xdc_rel, pps_xdc_text = gnss_xdc(variant_name, "pps")
        copied_xdc_files.append(str(project_dir / pps_xdc_rel))
        if apply:
            pps_xdc_path = project_dir / pps_xdc_rel
            pps_xdc_path.parent.mkdir(parents=True, exist_ok=True)
            pps_xdc_path.write_text(pps_xdc_text)
        rel_xdc_files.append(pps_xdc_rel)

    project_text = system_project.read_text()
    patched_project, project_changed = patch_system_project(project_text, rel_files, rel_xdc_files)
    make_text = makefile.read_text()
    patched_make, make_changed = patch_makefile(make_text, rel_files)
    system_top_text = system_top.read_text()
    patched_system_top, system_top_changed = patch_system_top(system_top_text, gnss_uart_emio, gnss_pps_emio)
    system_bd_text = system_bd.read_text()
    patched_system_bd, system_bd_changed = patch_system_bd(
        system_bd_text,
        plan,
        variant_name,
        control_overlay,
        bridge_overlay,
        dma_overlay,
        rf_engine_overlay,
        gnss_uart_emio,
        gnss_pps_emio,
    )

    if apply:
        if project_changed:
            system_project.write_text(patched_project)
        if make_changed:
            makefile.write_text(patched_make)
        if system_top_changed:
            system_top.write_text(patched_system_top)
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
        "gnss_uart_emio": gnss_uart_emio,
        "gnss_pps_emio": gnss_pps_emio,
        "variant": variant_name,
        "hdl_tree": str(hdl_tree),
        "system_bd": str(system_bd),
        "system_bd_changed": system_bd_changed,
        "system_project_changed": project_changed,
        "system_top_changed": system_top_changed,
        "makefile_changed": make_changed,
        "copied_rtl_files": copied_files,
        "copied_xdc_files": copied_xdc_files,
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
        help="also add fieldmesh_tx_dma/fieldmesh_rx_dma axi_dmac cells and connect them to the firmware DMA endpoint",
    )
    parser.add_argument(
        "--rf-engine-overlay",
        action="store_true",
        help="also add non-transmitting fieldmesh_bpsk_symbolizer and IQ TX guard cells behind the sidecar DMA/bridge TX packet path",
    )
    parser.add_argument(
        "--gnss-uart-emio",
        action="store_true",
        help="also expose PS UART0 over EMIO as GNSS NMEA using variant-specific constraints",
    )
    parser.add_argument(
        "--gnss-pps-emio",
        action="store_true",
        help="also expose variant GPS_PPS as PS GPIO EMIO bit 17 for pps-gpio",
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
        args.gnss_uart_emio,
        args.gnss_pps_emio,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
