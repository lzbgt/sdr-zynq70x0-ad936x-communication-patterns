SUMMARY = "FieldMesh guarded RF runtime tools"
DESCRIPTION = "Guarded board-side helpers for conducted/shielded FieldMesh RF TX-enable tests."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FIELDMESH_REPO_ROOT = "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '..', '..', '..'))}"

SRC_URI = " \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_firmware_abi.h \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_firmware_dma_ctrl.h \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-common.sh \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-safe-tune \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-tx-enable \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-tx-disable \
"

S = "${WORKDIR}"

RDEPENDS:${PN} += "libiio-tests"

do_compile() {
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra ${LDFLAGS} \
        -I${WORKDIR}${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${WORKDIR}${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c \
        -o fieldmesh-ctrl-write
}

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${libexecdir}/fieldmesh
    install -m 0755 ${B}/fieldmesh-ctrl-write ${D}${bindir}/fieldmesh-ctrl-write
    install -m 0755 ${WORKDIR}${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-safe-tune ${D}${bindir}/fieldmesh-radio-safe-tune
    install -m 0755 ${WORKDIR}${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-tx-enable ${D}${bindir}/fieldmesh-radio-tx-enable
    install -m 0755 ${WORKDIR}${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-tx-disable ${D}${bindir}/fieldmesh-radio-tx-disable
    install -m 0644 ${WORKDIR}${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-rf-tools/fieldmesh-radio-common.sh ${D}${libexecdir}/fieldmesh/fieldmesh-radio-common.sh
}
