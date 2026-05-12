SUMMARY = "Vendor Linux kernel for SDR-Z103"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel externalsrc

EXTERNALSRC ?= "${SDR_Z103_VENDOR_FW}/linux"
EXTERNALSRC_BUILD ?= "${WORKDIR}/linux-build"

COMPATIBLE_MACHINE = "sdr-z103-zynq7"

KBUILD_DEFCONFIG:sdr-z103-zynq7 = "zynq_pluto_defconfig"
KERNEL_DEVICETREE:sdr-z103-zynq7 = "zynq-pluto-sdr.dtb"

PV = "6.1+vendor"
