SUMMARY = "FieldMesh SDK socket demo tools"
DESCRIPTION = "Portable C SDK demos for FieldMesh AP, peer, and RTLS state over IP transports."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FIELDMESH_REPO_ROOT = "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '..', '..', '..'))}"

SRC_URI = " \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c;subdir=fieldmesh-sdk/src \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_sdk.h;subdir=fieldmesh-sdk/include \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_state_daemon_demo.c;subdir=fieldmesh-sdk/examples \
"

S = "${WORKDIR}/fieldmesh-sdk"

do_compile() {
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_state_daemon_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-state-daemon-demo
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/fieldmesh-state-daemon-demo ${D}${bindir}/fieldmesh-state-daemon-demo
}
