#!/usr/bin/env python3
"""Generate and validate FieldMesh sidecar devicetree fragments."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any


SIDECAR_DTSI = """// SPDX-License-Identifier: GPL-2.0
/*
 * FieldMesh sidecar packet-DMA devicetree fragment.
 *
 * Include this only with a bitstream that contains fieldmesh_ctrl,
 * fieldmesh_tx_dma, fieldmesh_rx_dma, the sidecar byte-pipe bridge, and the
 * first-party firmware ring aperture.
 */

&fpga_axi {
	fieldmesh_ctrl: fieldmesh-ctrl@43c00000 {
		compatible = "fieldmesh,sidecar-ctrl-1.0";
		reg = <0x43c00000 0x10000>;
		interrupts = <0 55 IRQ_TYPE_LEVEL_HIGH>;
		clocks = <&clkc 16>;
		status = "okay";
	};

	fieldmesh_tx_dma: dma@43c10000 {
		compatible = "adi,axi-dmac-1.00.a";
		reg = <0x43c10000 0x10000>;
		#dma-cells = <1>;
		interrupts = <0 53 IRQ_TYPE_LEVEL_HIGH>;
		clocks = <&clkc 16>;
		status = "okay";

		adi,channels {
			#size-cells = <0>;
			#address-cells = <1>;

			dma-channel@0 {
				reg = <0>;
				adi,source-bus-width = <64>;
				adi,source-bus-type = <0>;
				adi,destination-bus-width = <16>;
				adi,destination-bus-type = <1>;
			};
		};
	};

	fieldmesh_rx_dma: dma@43c20000 {
		compatible = "adi,axi-dmac-1.00.a";
		reg = <0x43c20000 0x10000>;
		#dma-cells = <1>;
		interrupts = <0 54 IRQ_TYPE_LEVEL_HIGH>;
		clocks = <&clkc 16>;
		status = "okay";

		adi,channels {
			#size-cells = <0>;
			#address-cells = <1>;

			dma-channel@0 {
				reg = <0>;
				adi,source-bus-width = <16>;
				adi,source-bus-type = <1>;
				adi,destination-bus-width = <64>;
				adi,destination-bus-type = <0>;
			};
		};
	};

	fieldmesh_ring: fieldmesh-ring@43c30000 {
		compatible = "fieldmesh,firmware-ring-1.0", "generic-uio";
		reg = <0x43c30000 0x10000>;
		interrupts = <0 52 IRQ_TYPE_LEVEL_HIGH>;
		clocks = <&clkc 16>;
		linux,uio-name = "fieldmesh-ring";
		fieldmesh,ring-slots = <8>;
		fieldmesh,packet-arena-bytes = <4096>;
		fieldmesh,packet-stride = <256>;
		fieldmesh,layout-version = <1>;
		status = "okay";
	};

	fieldmesh_packet: fieldmesh-packet {
		compatible = "fieldmesh,packet-sidecar-1.0";
		fieldmesh-ctrl = <&fieldmesh_ctrl>;
		fieldmesh-ring = <&fieldmesh_ring>;
		dmas = <&fieldmesh_tx_dma 0>, <&fieldmesh_rx_dma 0>;
		dma-names = "tx", "rx";
		status = "okay";
	};
};
"""

GNSS_UART_EMIO_DTSI = """// SPDX-License-Identifier: GPL-2.0
/*
 * FieldMesh GNSS UART devicetree fragment.
 *
 * Include this only with a bitstream/PS7 configuration that routes PS UART0
 * through EMIO to the board GNSS NMEA pins. UART1 remains the Linux console.
 */

/ {
	aliases {
		serial1 = &uart0;
	};
};

&uart0 {
	status = "okay";
	current-speed = <9600>;
	fieldmesh,gnss-nmea;
};
"""

GNSS_PPS_EMIO_DTSI = """// SPDX-License-Identifier: GPL-2.0
/*
 * FieldMesh GNSS PPS devicetree fragment.
 *
 * Include this only with a bitstream/PS7 configuration that routes the board
 * GPS_PPS signal into PS GPIO EMIO bit 17. Zynq GPIO numbering maps EMIO bit 17
 * to Linux GPIO 71 because EMIO starts at GPIO 54. The matching bitstream must
 * constrain that EMIO input to the variant-specific GPS_PPS package pin.
 */

/ {
	fieldmesh_gnss_pps: fieldmesh-gnss-pps {
		compatible = "pps-gpio";
		gpios = <&gpio0 71 0>;
		status = "okay";
		fieldmesh,gnss-pps;
	};
};
"""


def parse_variant(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("variant must be NAME=LINUX_ROOT")
    name, path = value.split("=", 1)
    if not name:
        raise argparse.ArgumentTypeError("variant name is empty")
    return name, Path(path)


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def write_merged_dts(
    linux_root: Path,
    out_dir: Path,
    variant: str,
    enable_gnss_uart_emio: bool,
    enable_gnss_pps_emio: bool,
) -> tuple[Path, Path]:
    dts_dir = linux_root / "arch" / "arm" / "boot" / "dts"
    base_dts = dts_dir / "zynq-pluto-sdr.dts"
    if not base_dts.is_file():
        raise SystemExit(f"{base_dts}: not found")

    fragment = out_dir / "fieldmesh-sidecar.dtsi"
    gnss_fragment = out_dir / "fieldmesh-gnss-uart-emio.dtsi"
    pps_fragment = out_dir / "fieldmesh-gnss-pps-emio.dtsi"
    merged = out_dir / f"{variant}-zynq-pluto-sdr-fieldmesh.dts"
    fragment.write_text(SIDECAR_DTSI)
    if enable_gnss_uart_emio:
        gnss_fragment.write_text(GNSS_UART_EMIO_DTSI)
    if enable_gnss_pps_emio:
        pps_fragment.write_text(GNSS_PPS_EMIO_DTSI)

    text = base_dts.read_text()
    include = '#include "zynq-pluto-sdr.dtsi"'
    if include not in text:
        raise SystemExit(f"{base_dts}: expected {include!r} not found")
    extra_includes = ['#include "fieldmesh-sidecar.dtsi"']
    if enable_gnss_uart_emio:
        extra_includes.append('#include "fieldmesh-gnss-uart-emio.dtsi"')
    if enable_gnss_pps_emio:
        extra_includes.append('#include "fieldmesh-gnss-pps-emio.dtsi"')
    text = text.replace(include, include + "\n" + "\n".join(extra_includes), 1)
    merged.write_text(text)
    return fragment, merged


def compile_dts(linux_root: Path, dts: Path, dtb: Path) -> None:
    include_root = linux_root / "include"
    dts_dir = linux_root / "arch" / "arm" / "boot" / "dts"
    with tempfile.NamedTemporaryFile("w+", suffix=".pp.dts", delete=False) as tmp:
        pp = Path(tmp.name)
    try:
        cpp = [
            "cpp",
            "-nostdinc",
            "-undef",
            "-x",
            "assembler-with-cpp",
            "-I",
            str(dts.parent),
            "-I",
            str(dts_dir),
            "-I",
            str(include_root),
            str(dts),
        ]
        processed = run(cpp)
        pp.write_text(processed.stdout)
        run(["dtc", "-I", "dts", "-O", "dtb", "-o", str(dtb), str(pp)])
    finally:
        pp.unlink(missing_ok=True)


def decompile_dtb(dtb: Path) -> str:
    return run(["dtc", "-I", "dtb", "-O", "dts", str(dtb)]).stdout


def check_decompiled(text: str) -> dict[str, Any]:
    required = {
        "fieldmesh_ctrl_node": "fieldmesh-ctrl@43c00000",
        "fieldmesh_tx_dma_node": "dma@43c10000",
        "fieldmesh_rx_dma_node": "dma@43c20000",
        "fieldmesh_ring_node": "fieldmesh-ring@43c30000",
        "fieldmesh_packet_node": "fieldmesh-packet",
        "fieldmesh_ctrl_compatible": 'compatible = "fieldmesh,sidecar-ctrl-1.0"',
        "fieldmesh_ring_compatible": 'compatible = "fieldmesh,firmware-ring-1.0", "generic-uio"',
        "fieldmesh_packet_compatible": 'compatible = "fieldmesh,packet-sidecar-1.0"',
        "axi_dmac_compatible": 'compatible = "adi,axi-dmac-1.00.a"',
        "tx_dma_reg": "reg = <0x43c10000 0x10000>",
        "rx_dma_reg": "reg = <0x43c20000 0x10000>",
        "ring_reg": "reg = <0x43c30000 0x10000>",
        "ctrl_irq": "interrupts = <0x00 0x37 0x04>",
        "tx_irq": "interrupts = <0x00 0x35 0x04>",
        "rx_irq": "interrupts = <0x00 0x36 0x04>",
        "ring_irq": "interrupts = <0x00 0x34 0x04>",
        "ring_slots": "fieldmesh,ring-slots = <0x08>",
        "ring_packet_arena": "fieldmesh,packet-arena-bytes = <0x1000>",
        "ring_packet_stride": "fieldmesh,packet-stride = <0x100>",
        "stream_width": "adi,destination-bus-width = <0x10>",
    }
    checks = {name: needle in text for name, needle in required.items()}
    return {"ok": all(checks.values()), "checks": checks}


def _node_blocks(text: str, node_prefix: str) -> list[tuple[str, str]]:
    pattern = re.compile(rf"^\s*({re.escape(node_prefix)}@[0-9a-fA-F]+)\s*\{{(.*?)^\s*\}};", re.MULTILINE | re.DOTALL)
    return [(match.group(1), match.group(2)) for match in pattern.finditer(text)]


def _status_okay(body: str) -> bool:
    status = re.search(r'status\s*=\s*"([^"]+)"', body)
    return status is None or status.group(1) == "okay"


def _console_serial_addresses(text: str) -> set[str]:
    addresses: set[str] = set()
    for match in re.finditer(r'stdout-path\s*=\s*"[^"]*[@/]([eE][0-9a-fA-F]+)', text):
        addresses.add(match.group(1).lower())
    for match in re.finditer(r'serial0\s*=\s*"[^"]*serial@([0-9a-fA-F]+)"', text):
        addresses.add(match.group(1).lower())
    for match in re.finditer(r"console=ttyPS0", text):
        # Z203/Z103 images map ttyPS0 to PS UART1 at 0xe0001000.
        addresses.add("e0001000")
    return addresses


def check_gnss_exposure(text: str | None, require_uart: bool, require_pps: bool) -> dict[str, Any]:
    if text is None:
        blockers = []
        if require_uart:
            blockers.append("gnss_uart_decompile_unavailable")
        if require_pps:
            blockers.append("gnss_pps_decompile_unavailable")
        return {
            "ok": not blockers,
            "required": {"uart": require_uart, "pps": require_pps},
            "checks": {
                "non_console_uart_present": False,
                "pps_present": False,
                "decompiled_dtb_available": False,
            },
            "candidates": {"serial": [], "pps": []},
            "blockers": blockers,
        }

    console_addresses = _console_serial_addresses(text)
    serial_candidates = []
    for node, body in _node_blocks(text, "serial"):
        address = node.split("@", 1)[1].lower()
        compatible = re.search(r'compatible\s*=\s*([^;]+);', body)
        row = {
            "node": node,
            "address": address,
            "status_okay": _status_okay(body),
            "console": address in console_addresses,
            "compatible": compatible.group(1).strip() if compatible else "",
        }
        row["gnss_candidate"] = (
            row["status_okay"]
            and not row["console"]
            and any(token in row["compatible"] for token in ("xlnx,xuartps", "cdns,uart", "xlnx,xps-uartlite", "ns16550"))
        )
        serial_candidates.append(row)

    pps_candidates = []
    for node_prefix in ("pps", "fieldmesh-gnss-pps", "gnss-pps"):
        for node, body in _node_blocks(text, node_prefix):
            pps_candidates.append({"node": node, "status_okay": _status_okay(body)})
    pps_marker_present = any(token in text for token in ('compatible = "pps-gpio"', "fieldmesh,gnss-pps", "GPS_PPS", "gps-pps"))
    non_console_uart_present = any(row["gnss_candidate"] for row in serial_candidates)
    pps_present = pps_marker_present or any(row["status_okay"] for row in pps_candidates)

    blockers = []
    if require_uart and not non_console_uart_present:
        blockers.append("gnss_uart_not_exposed_in_devicetree")
    if require_pps and not pps_present:
        blockers.append("gnss_pps_not_exposed_in_devicetree")
    return {
        "ok": not blockers,
        "required": {"uart": require_uart, "pps": require_pps},
        "checks": {
            "non_console_uart_present": non_console_uart_present,
            "pps_present": pps_present,
            "decompiled_dtb_available": True,
        },
        "candidates": {"serial": serial_candidates, "pps": pps_candidates},
        "blockers": blockers,
    }


def build_variant(
    name: str,
    linux_root: Path,
    out_root: Path,
    compile_dt: bool,
    require_gnss_uart: bool,
    require_gnss_pps: bool,
    enable_gnss_uart_emio: bool,
    enable_gnss_pps_emio: bool,
) -> dict[str, Any]:
    out_dir = out_root / name
    out_dir.mkdir(parents=True, exist_ok=True)
    fragment, merged = write_merged_dts(
        linux_root,
        out_dir,
        name,
        enable_gnss_uart_emio,
        enable_gnss_pps_emio,
    )
    row: dict[str, Any] = {
        "variant": name,
        "linux_root": str(linux_root),
        "fragment": str(fragment),
        "merged_dts": str(merged),
        "dtb": None,
        "gnss_uart_emio_enabled": enable_gnss_uart_emio,
        "gnss_pps_emio_enabled": enable_gnss_pps_emio,
        "check": {"ok": True, "checks": {}},
        "gnss_exposure": check_gnss_exposure(None, require_gnss_uart, require_gnss_pps),
    }
    if compile_dt:
        dtb = out_dir / f"{name}-zynq-pluto-sdr-fieldmesh.dtb"
        compile_dts(linux_root, merged, dtb)
        row["dtb"] = str(dtb)
        decompiled = decompile_dtb(dtb)
        row["check"] = check_decompiled(decompiled)
        row["gnss_exposure"] = check_gnss_exposure(decompiled, require_gnss_uart, require_gnss_pps)
    return row


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variant",
        action="append",
        type=parse_variant,
        required=True,
        metavar="NAME=LINUX_ROOT",
        help="variant name and extracted Linux source root; repeat for comparisons",
    )
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/devicetree-plan"))
    parser.add_argument("--no-compile", action="store_true", help="only write DTS/DTSI files")
    parser.add_argument(
        "--require-gnss-uart",
        action="store_true",
        help="fail unless the compiled DTB exposes an enabled non-console GNSS-capable UART",
    )
    parser.add_argument(
        "--require-gnss-pps",
        action="store_true",
        help="fail unless the compiled DTB exposes a PPS node/marker for GNSS timing",
    )
    parser.add_argument(
        "--enable-gnss-uart-emio",
        action="store_true",
        help="include the PS UART0 EMIO GNSS fragment; use only with a matching bitstream/PS7 config",
    )
    parser.add_argument(
        "--enable-gnss-pps-emio",
        action="store_true",
        help="include the GPS_PPS-to-EMIO GPIO PPS fragment; use only with a matching variant bitstream/PS7 config",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = [
        build_variant(
            name,
            path,
            args.out_dir,
            not args.no_compile,
            args.require_gnss_uart,
            args.require_gnss_pps,
            args.enable_gnss_uart_emio,
            args.enable_gnss_pps_emio,
        )
        for name, path in args.variant
    ]
    result = {
        "event": "fieldmesh_devicetree_plan",
        "ok": all(row["check"]["ok"] and row["gnss_exposure"]["ok"] for row in rows),
        "variants": rows,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
