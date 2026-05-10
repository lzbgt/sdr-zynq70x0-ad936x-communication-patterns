SUMMARY = "SDR-Z203 board configuration files"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://COPYING.MIT;md5=d4f85152a1bb147e5d339ae72270ef20"

SRC_URI = " \
    file://COPYING.MIT \
    file://device_config \
    file://fw_env.config \
    file://motd \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config

    install -d ${D}${sysconfdir}/sdr-z203
    install -m 0644 ${WORKDIR}/motd ${D}${sysconfdir}/sdr-z203/motd

    install -d ${D}/etc
    install -m 0644 ${WORKDIR}/device_config ${D}/etc/device_config
}

FILES:${PN} = " \
    ${sysconfdir}/device_config \
    ${sysconfdir}/fw_env.config \
    ${sysconfdir}/sdr-z203/motd \
"
