# meta-sdr-z203

Yocto layer for the SDR-Z203 ARM-side firmware work.

This layer is intentionally focused on the processing-system firmware while the
Vivado/FPGA toolchain is still being prepared. It provides:

- `sdr-z203-zynq7`, a Cortex-A9 hard-float Zynq-7000 machine definition.
- `sdr-z203-arm-image`, a small developer image with SSH, IIO, U-Boot env tools,
  networking tools, and board identity/config files.
- `sdr-z203-pluto-runtime`, which imports the essential Pluto USB gadget,
  FunctionFS/IIO, mass-storage update, web, and recovery scripts from the
  extracted vendor firmware tree.
- `fieldmesh-udp-probe`, a small C split UDP sender/receiver for board-runtime
  FieldMesh packet smoke tests without Python.
- external-source recipes for the vendor Linux and U-Boot trees extracted under
  `src/extracted/plutosdr-fw-2r2t/plutosdr-fw`.

The layer does not store the vendor source tree. Set `SDR_Z203_VENDOR_FW` in
`conf/local.conf` if the source lives somewhere else.

Verified on WSL Arch:

- `bitbake -p`
- `bitbake sdr-z203-arm-image`
- `bitbake fieldmesh-udp-probe`
- `bitbake virtual/bootloader`
- `./tools/audit_yocto_rootfs.sh`
