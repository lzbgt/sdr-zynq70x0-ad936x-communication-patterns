# JTAG Hello Bare-Metal Example

This is the smallest local proof that a custom ARM-side application can be
built in WSL Arch and launched over the onboard FT2232 JTAG path without Linux
and without writing QSPI.

Build:

```sh
./tools/build_jtag_hello_elf.sh
```

Run while the board is powered in JTAG mode and the FT2232 is attached to WSL:

```sh
CAPTURE=resources/live-captures/openocd_jtag_hello_manual.txt \
  ./tools/run_openocd_jtag_hello.sh
```

The example links at `0x04000000`, uses UART1 at `0xe0001000`, and depends on
the run helper to initialize the Zynq PS/DDR from the generated `ps7_init.tcl`
before loading the ELF.
