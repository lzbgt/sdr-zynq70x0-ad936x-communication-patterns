FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

do_install:append() {
    install -m 0644 ${WORKDIR}/lighttpd.conf ${D}${sysconfdir}/lighttpd/lighttpd.conf
}
