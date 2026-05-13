SUMMARY = "FieldMesh SDK socket demo tools"
DESCRIPTION = "Portable C SDK demos for FieldMesh AP, join, stream, peer, and RTLS state over IP transports."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FIELDMESH_REPO_ROOT = "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '..', '..', '..'))}"

SRC_URI = " \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c;subdir=fieldmesh-sdk/src \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_sdk.h;subdir=fieldmesh-sdk/include \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_device_iio_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmeshctl_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_state_daemon_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_swarm_adapter_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_tun_gateway_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_two_pc_flow_demo.c;subdir=fieldmesh-sdk/examples \
"

S = "${WORKDIR}/fieldmesh-sdk"

do_compile() {
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_device_iio_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-device-iio-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmeshctl_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmeshctl
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_state_daemon_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-state-daemon-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_swarm_adapter_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-swarm-adapter-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_tun_gateway_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-tun-gateway-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_two_pc_flow_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-two-pc-flow-demo
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/fieldmesh-device-iio-demo ${D}${bindir}/fieldmesh-device-iio-demo
    install -m 0755 ${B}/fieldmeshctl ${D}${bindir}/fieldmeshctl
    install -m 0755 ${B}/fieldmesh-state-daemon-demo ${D}${bindir}/fieldmesh-state-daemon-demo
    install -m 0755 ${B}/fieldmesh-swarm-adapter-demo ${D}${bindir}/fieldmesh-swarm-adapter-demo
    install -m 0755 ${B}/fieldmesh-tun-gateway-demo ${D}${bindir}/fieldmesh-tun-gateway-demo
    install -m 0755 ${B}/fieldmesh-two-pc-flow-demo ${D}${bindir}/fieldmesh-two-pc-flow-demo
}
