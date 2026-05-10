SUMMARY = "Vendor U-Boot for SDR-Z203"
SECTION = "bootloaders"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://Licenses/gpl-2.0.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263"

require recipes-bsp/u-boot/u-boot.inc

inherit externalsrc

EXTERNALSRC ?= "${SDR_Z203_VENDOR_FW}/u-boot-xlnx"
EXTERNALSRC_BUILD ?= "${WORKDIR}/u-boot-build"

COMPATIBLE_MACHINE = "sdr-z203-zynq7"

PROVIDES += "virtual/bootloader"

UBOOT_MACHINE = "zynq_pluto_defconfig"
PV = "2026.01+vendor"

