SUMMARY = "Vendor U-Boot for SDR-Z103"
SECTION = "bootloaders"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://Licenses/gpl-2.0.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263"

require recipes-bsp/u-boot/u-boot.inc

inherit externalsrc

# The vendor 2016-era tree invokes dtc directly and does not implement Yocto's
# newer optional u-boot-initial-env target.
DEPENDS += "dtc-native"

EXTERNALSRC ?= "${SDR_Z103_VENDOR_FW}/u-boot-xlnx"
EXTERNALSRC_BUILD ?= "${WORKDIR}/u-boot-build"

# Yocto's native sysroot and the host distro can both provide newer libfdt
# headers. The vendor U-Boot host tools need the matching 2016-era libfdt.h and
# libfdt_env.h, but adding the whole U-Boot include directory before system
# headers breaks host tools that include libc headers such as stdlib.h. Use a
# tiny shim include directory containing only the two vendor libfdt headers.
EXTRA_OEMAKE += 'HOSTCC="${BUILD_CC} -I${B}/host-fdt-include -O2 -pipe ${BUILD_LDFLAGS}"'

do_configure:prepend() {
    install -d "${B}/host-fdt-include"
    ln -sf "${S}/include/libfdt.h" "${B}/host-fdt-include/libfdt.h"
    ln -sf "${S}/include/libfdt_env.h" "${B}/host-fdt-include/libfdt_env.h"
}

COMPATIBLE_MACHINE = "(sdr-z103-zynq7|fm-z103)"

PROVIDES += "virtual/bootloader"

UBOOT_MACHINE = "zynq_pluto_defconfig"
UBOOT_INITIAL_ENV = ""
PV = "2026.01+vendor"
