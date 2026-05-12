SUMMARY = "FieldMesh UDP runtime probe"
DESCRIPTION = "Small C sender/receiver for FieldMesh packet and degradation trace smoke tests."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS += "libiio"

SRC_URI = "file://fieldmesh_udp_probe.c"

S = "${WORKDIR}"

do_compile() {
    ${CC} ${CFLAGS} -DFIELD_MESH_WITH_IIO ${LDFLAGS} ${WORKDIR}/fieldmesh_udp_probe.c -liio -o fieldmesh-udp-probe
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/fieldmesh-udp-probe ${D}${bindir}/fieldmesh-udp-probe
}
