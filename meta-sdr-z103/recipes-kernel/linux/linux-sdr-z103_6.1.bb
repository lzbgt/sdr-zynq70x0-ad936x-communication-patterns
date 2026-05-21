SUMMARY = "Vendor Linux kernel for SDR-Z103"
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel externalsrc

EXTERNALSRC ?= "${SDR_Z103_VENDOR_FW}/linux"
EXTERNALSRC_BUILD ?= "${WORKDIR}/linux-build"

COMPATIBLE_MACHINE = "(sdr-z103-zynq7|fm-z103)"

KBUILD_DEFCONFIG = "zynq_pluto_defconfig"
KERNEL_DEVICETREE = "zynq-pluto-sdr.dtb"

PV = "6.1+vendor"

do_configure:prepend() {
    python3 - <<'PY'
from pathlib import Path

path = Path("${S}") / "drivers/uio/uio_pdrv_genirq.c"
text = path.read_text(encoding="utf-8")
old = 'static struct of_device_id uio_of_genirq_match[] = {\n\t{ /* This is filled with module_parm */ },'
new = 'static struct of_device_id uio_of_genirq_match[] = {\n\t{ .compatible = "generic-uio" },'
if old in text:
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
elif new not in text:
    raise SystemExit("uio_pdrv_genirq generic-uio default hook not found")
PY
    install -m 0644 ${S}/arch/arm/configs/zynq_pluto_defconfig ${B}/.config
}

do_configure:append() {
    ${S}/scripts/config --file ${B}/.config --enable TUN
    ${S}/scripts/config --file ${B}/.config --enable UIO
    ${S}/scripts/config --file ${B}/.config --enable UIO_PDRV_GENIRQ
    ${S}/scripts/config --file ${B}/.config --enable PPS_CLIENT_GPIO
    oe_runmake -C ${S} O=${B} olddefconfig
}
