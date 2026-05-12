#!/usr/bin/env python3
"""Generate and validate FieldMesh sidecar devicetree fragments."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any


SIDECAR_DTSI = """// SPDX-License-Identifier: GPL-2.0
/*
 * FieldMesh sidecar packet-DMA devicetree fragment.
 *
 * Include this only with a bitstream that contains fieldmesh_ctrl,
 * fieldmesh_tx_dma, fieldmesh_rx_dma, and the sidecar byte-pipe bridge.
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

	fieldmesh_packet: fieldmesh-packet {
		compatible = "fieldmesh,packet-sidecar-1.0";
		fieldmesh-ctrl = <&fieldmesh_ctrl>;
		dmas = <&fieldmesh_tx_dma 0>, <&fieldmesh_rx_dma 0>;
		dma-names = "tx", "rx";
		status = "okay";
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


def write_merged_dts(linux_root: Path, out_dir: Path, variant: str) -> tuple[Path, Path]:
    dts_dir = linux_root / "arch" / "arm" / "boot" / "dts"
    base_dts = dts_dir / "zynq-pluto-sdr.dts"
    if not base_dts.is_file():
        raise SystemExit(f"{base_dts}: not found")

    fragment = out_dir / "fieldmesh-sidecar.dtsi"
    merged = out_dir / f"{variant}-zynq-pluto-sdr-fieldmesh.dts"
    fragment.write_text(SIDECAR_DTSI)

    text = base_dts.read_text()
    include = '#include "zynq-pluto-sdr.dtsi"'
    if include not in text:
        raise SystemExit(f"{base_dts}: expected {include!r} not found")
    text = text.replace(include, include + '\n#include "fieldmesh-sidecar.dtsi"', 1)
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
        "fieldmesh_packet_node": "fieldmesh-packet",
        "fieldmesh_ctrl_compatible": 'compatible = "fieldmesh,sidecar-ctrl-1.0"',
        "fieldmesh_packet_compatible": 'compatible = "fieldmesh,packet-sidecar-1.0"',
        "axi_dmac_compatible": 'compatible = "adi,axi-dmac-1.00.a"',
        "tx_dma_reg": "reg = <0x43c10000 0x10000>",
        "rx_dma_reg": "reg = <0x43c20000 0x10000>",
        "ctrl_irq": "interrupts = <0x00 0x37 0x04>",
        "tx_irq": "interrupts = <0x00 0x35 0x04>",
        "rx_irq": "interrupts = <0x00 0x36 0x04>",
        "stream_width": "adi,destination-bus-width = <0x10>",
    }
    checks = {name: needle in text for name, needle in required.items()}
    return {"ok": all(checks.values()), "checks": checks}


def build_variant(name: str, linux_root: Path, out_root: Path, compile_dt: bool) -> dict[str, Any]:
    out_dir = out_root / name
    out_dir.mkdir(parents=True, exist_ok=True)
    fragment, merged = write_merged_dts(linux_root, out_dir, name)
    row: dict[str, Any] = {
        "variant": name,
        "linux_root": str(linux_root),
        "fragment": str(fragment),
        "merged_dts": str(merged),
        "dtb": None,
        "check": {"ok": True, "checks": {}},
    }
    if compile_dt:
        dtb = out_dir / f"{name}-zynq-pluto-sdr-fieldmesh.dtb"
        compile_dts(linux_root, merged, dtb)
        row["dtb"] = str(dtb)
        row["check"] = check_decompiled(decompile_dtb(dtb))
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = [build_variant(name, path, args.out_dir, not args.no_compile) for name, path in args.variant]
    result = {
        "event": "fieldmesh_devicetree_plan",
        "ok": all(row["check"]["ok"] for row in rows),
        "variants": rows,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
