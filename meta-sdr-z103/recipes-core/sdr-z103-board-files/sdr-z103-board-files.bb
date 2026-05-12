SUMMARY = "SDR-Z103 board configuration files"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://COPYING.MIT;md5=e9cc713456dd32371d24130fc427ffa9"

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

    install -d ${D}${sysconfdir}/sdr-z103
    install -m 0644 ${WORKDIR}/motd ${D}${sysconfdir}/sdr-z103/motd

    install -d ${D}/etc
    install -m 0644 ${WORKDIR}/device_config ${D}/etc/device_config
}

FILES:${PN} = " \
    ${sysconfdir}/device_config \
    ${sysconfdir}/fw_env.config \
    ${sysconfdir}/sdr-z103/motd \
"
