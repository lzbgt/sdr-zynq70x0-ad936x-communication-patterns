SUMMARY = "SDR-Z203 board configuration files"
LICENSE = "MIT"

SRC_URI = " \
    file://device_config \
    file://fw_env.config \
    file://motd \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${WORKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config
    install -m 0644 ${WORKDIR}/motd ${D}${sysconfdir}/motd

    install -d ${D}/etc
    install -m 0644 ${WORKDIR}/device_config ${D}/etc/device_config
}

FILES:${PN} = " \
    ${sysconfdir}/device_config \
    ${sysconfdir}/fw_env.config \
    ${sysconfdir}/motd \
"

