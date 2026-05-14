# meta-sdr-z103

Yocto layer for the SDR-Z103 ARM-side firmware work.

This layer is intentionally focused on the processing-system firmware and keeps
SDR-Z103 outputs separate from the SDR-Z203 build. It provides:

- `fm-z103`, the concise Yocto machine alias for the Z103 1R1T board. The
  product display name is `FM-Z103`; the legacy `sdr-z103-zynq7` machine remains
  as a recipe-compatibility base.
- `sdr-z103-arm-image`, a small developer image with SSH, IIO, U-Boot env tools,
  networking tools, and board identity/config files.
- `sdr-z103-pluto-runtime`, which imports the essential Pluto USB gadget,
  FunctionFS/IIO, mass-storage update, web, and recovery scripts from the
  extracted vendor firmware tree.
- `fieldmesh-udp-probe`, a small C split UDP sender/receiver for board-runtime
  FieldMesh packet smoke tests without Python.
- external-source recipes for the vendor Linux and U-Boot trees extracted under
  `src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw`.

The layer does not store the vendor source tree. Set `SDR_Z103_VENDOR_FW` in
`conf/local.conf` if the source lives somewhere else.

The board has no verified physical Ethernet or SD-card path, so this layer
targets QSPI/FIT payload work and USB RNDIS runtime validation.

Current WSL Arch verification:

- `bitbake -p`
- `bitbake sdr-z103-arm-image`
- `bitbake fieldmesh-udp-probe`
- `bitbake virtual/bootloader`
- `tools/audit_z103_yocto_rootfs.sh`
- `tools/package_z103_yocto_pluto_frm.sh`

Runtime boot of the rebuilt Z103 Linux package on hardware is the next gate. No
Z103 QSPI partition has been written by this workflow.
