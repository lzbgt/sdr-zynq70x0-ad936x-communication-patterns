# JTAG PS-to-PL AXI Boundary

This note captures the current Linux-from-RAM over JTAG boundary. The failure is
not generic JTAG access, DDR setup, U-Boot launch, bootargs, or initramfs
selection. Those pieces have already been exercised. The remaining fault is
PS-to-PL AXI access after a JTAG-only PS/DDR/PL setup.

## Verified Pieces

- OpenOCD scans the Zynq PL and CPU TAPs through the onboard FT2232H.
- Vivado Hardware Manager and OpenOCD both load `system_top.bit` into PL.
- OpenOCD translates the generated Xilinx `ps7_init.tcl` flow and initializes
  PS clocks, MIO, DDR, and peripherals.
- OpenOCD launches rebuilt `u-boot.elf` from DDR at `0x04000000`.
- A standalone ARM UART ELF also runs from DDR over the same PS7-init path.
- The Linux RAM boot helper preloads U-Boot, `uImage`,
  `uramdisk.image.gz`, `devicetree.dtb`, and `uEnv.txt`, interrupts U-Boot,
  imports the SD-style environment, and reaches kernel initcalls.

## Current Failing Signature

The best diagnostic Linux capture uses:

```sh
CAPTURE=resources/live-captures/openocd_jtag_linux_ram_factory_initcall_debug_20260512.txt \
  BOOT_DIR=.config/sdcard-staging/factory-2r2t \
  BOOT_WAIT_SECONDS=300 \
  UBOOT_COMMAND_INTERVAL_SECONDS=0.8 \
  BOOTARGS='console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk ignore_loglevel loglevel=8 initcall_debug' \
  ./tools/run_openocd_jtag_linux_ram.sh
```

It reaches Linux and stops at:

```text
calling  axi_dmac_driver_init+0x0/0x10 @ 1
```

Direct probing confirms the lower-level boundary:

```sh
./tools/probe_openocd_pl_axi.sh
PL_LOAD_AFTER_PS7_INIT=1 ./tools/probe_openocd_pl_axi.sh
```

Both fail on the first ADI PL register read:

```text
read at 0x7c400000 with width=32 and count=1 failed
```

`0x7c400000` is the RX AXI-DMAC register window used by the ADI HDL design.

## FSBL Side-Effect Comparison

The OpenOCD path already covers the generated PS7 init and post-config writes.
In `.config/boot-artifacts/sdt/ps7_init.tcl`, `ps7_post_config_3_0` writes:

- `0xF8000900 = 0x0000000F` through mask write, enabling the PS/PL level
  shifters.
- `0xF8000240 = 0x00000000`, releasing FPGA resets.

Those are the same post-configuration effects that the generated FSBL calls
through `ps7_post_config()` after PL configuration, or in JTAG boot mode when
the devcfg status already reports `XDCFG_IXR_PCFG_DONE_MASK`.

The still-unproven difference is the complete FSBL sequencing around PL
configuration and handoff:

- `PcapLoadPartition()` enables PS-to-PL level shifters before PCAP transfer.
- The FSBL PCAP path toggles `PCFG_PROG_B`, waits for `PCFG_INIT`, transfers
  the bitstream, and waits for `PCFG_DONE`.
- In JTAG boot mode, FSBL checks devcfg `PCFG_DONE`, calls
  `ps7_post_config()`, clears its mark, locks SLCR, and exits through
  `FsblHandoffJtagExit()`.

Because both Vivado-loaded PL and OpenOCD-loaded PL still fail the direct PL AXI
read after OpenOCD PS7 init, the next useful comparison is not another Linux
bootargs variant. It is whether an FSBL-owned post-config or handoff path makes
the PL AXI windows visible before U-Boot or Linux run.

## Next Clean-DAP Experiments

Start from a physical JTAG-mode power cycle if OpenOCD reports DAP sticky or
DSCR errors. A PL AXI read fault can leave the DAP in a state that
`tools/reset_openocd_zynq_ps.sh` cannot reliably clear.

The 2026-05-12 PS-only preflight capture
`resources/live-captures/openocd_ps7_post_config_after_dscr_20260512.txt`
confirmed this gate: the JTAG chain still scanned, but the helper failed during
`JTAG_PS_SOFT_RESET` with `JTAG-DP STICKY ERROR` before any SLCR reads.

Schematic review also supports this operational boundary. The onboard FT2232H
is wired for JTAG through `ADBUS0..3` and UART through `BDBUS0..1`; the extracted
schematic does not show an FTDI-controlled `PS_SRST_B`, `PS_POR_B`, `SRST`, or
`TRST` connection. OpenOCD can reset the TAP and can request a PS reset through
DAP/SLCR while the DAP is responsive, but it is not a substitute for a
board-level power/POR reset once DAP access is sticky.

Recommended order:

1. Run `./tools/probe_openocd_jtag.sh` to confirm the chain is clean.
2. Run `./tools/probe_openocd_ps7_post_config.sh` to confirm the generated
   PS7 init and post-config writes complete and report sane SLCR values before
   touching `0x7c400000`.
3. Run `tools/run_openocd_jtag_fsbl_handoff.sh`, which loads PL before FSBL,
   runs PS7 init without pre-running `ps7_post_config` by default, starts
   `fsbl.elf` at OCM address `0x0`, and captures devcfg/SLCR state after FSBL
   has had a chance to execute its JTAG branch.
4. Probe `0x7c400000` only after the FSBL-style handoff.
5. If the AXI-DMAC read succeeds, rerun `tools/run_openocd_jtag_linux_ram.sh`.

The FSBL handoff helper intentionally leaves `PROBE_PL_AXI_AFTER_FSBL=0` by
default. Set it to `1` only when the pre/post state and serial capture show the
FSBL path reached the expected JTAG handoff.

Avoid repeated direct reads of non-responsive PL AXI addresses in the same power
session; once the DAP is sticky, subsequent evidence is mostly about the debug
fault state rather than the original fabric setup problem.
