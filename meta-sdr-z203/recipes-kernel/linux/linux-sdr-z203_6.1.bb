SUMMARY = "Vendor Linux kernel for SDR-Z203"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel externalsrc

EXTERNALSRC ?= "${SDR_Z203_VENDOR_FW}/linux"
EXTERNALSRC_BUILD ?= "${WORKDIR}/linux-build"

COMPATIBLE_MACHINE = "(sdr-z203-zynq7|fm-z203)"

KBUILD_DEFCONFIG = "zynq_pluto_defconfig"
KERNEL_DEVICETREE = "zynq-pluto-sdr.dtb"

PV = "6.1+vendor"

do_configure:prepend() {
    install -m 0644 ${S}/arch/arm/configs/zynq_pluto_defconfig ${B}/.config
}

do_configure:append() {
    ${S}/scripts/config --file ${B}/.config --enable TUN
    ${S}/scripts/config --file ${B}/.config --enable PPS_CLIENT_GPIO
    oe_runmake -C ${S} O=${B} olddefconfig
}
