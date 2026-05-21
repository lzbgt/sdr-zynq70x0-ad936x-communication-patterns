SUMMARY = "FieldMesh SDK socket demo tools"
DESCRIPTION = "Portable C SDK demos for FieldMesh AP, join, stream, peer, and RTLS state over IP transports."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FIELDMESH_REPO_ROOT = "${@os.path.abspath(os.path.join(d.getVar('THISDIR'), '..', '..', '..'))}"

SRC_URI = " \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c;subdir=fieldmesh-sdk/src \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_sdk.h;subdir=fieldmesh-sdk/include \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/include/fieldmesh_firmware_abi.h;subdir=fieldmesh-sdk/include \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_camera_stream_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_device_iio_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_firmware_abi_probe.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_mac_frame_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_gnss_nmea_reporter.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_native_ip_socket_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmeshctl_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_state_daemon_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_swarm_adapter_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_tun_gateway_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_tun_packetizer_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_two_pc_flow_demo.c;subdir=fieldmesh-sdk/examples \
    file://${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-state-daemon/fieldmesh-state-daemon-init;subdir=fieldmesh-sdk/init \
"

S = "${WORKDIR}/fieldmesh-sdk"

do_compile() {
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_camera_stream_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-camera-stream-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_device_iio_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-device-iio-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_firmware_abi_probe.c \
        ${LDFLAGS} \
        -o fieldmesh-firmware-abi-probe
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_mac_frame_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-mac-frame-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_gnss_nmea_reporter.c \
        ${LDFLAGS} \
        -o fieldmesh-gnss-nmea-reporter
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_native_ip_socket_demo.c \
        ${LDFLAGS} \
        -o fieldmesh-native-ip-socket-demo
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
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_tun_packetizer_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-tun-packetizer-demo
    ${CC} ${CFLAGS} -std=c99 -Wall -Wextra \
        -I${S}/include${FIELDMESH_REPO_ROOT}/sdk/c/include \
        ${S}/examples${FIELDMESH_REPO_ROOT}/sdk/c/examples/fieldmesh_two_pc_flow_demo.c \
        ${S}/src${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c \
        ${LDFLAGS} \
        -o fieldmesh-two-pc-flow-demo
}

do_install() {
    install -d ${D}${bindir} ${D}${sysconfdir}/init.d ${D}${sysconfdir}/rcS.d
    install -m 0755 ${B}/fieldmesh-camera-stream-demo ${D}${bindir}/fieldmesh-camera-stream-demo
    install -m 0755 ${B}/fieldmesh-device-iio-demo ${D}${bindir}/fieldmesh-device-iio-demo
    install -m 0755 ${B}/fieldmesh-firmware-abi-probe ${D}${bindir}/fieldmesh-firmware-abi-probe
    install -m 0755 ${B}/fieldmesh-mac-frame-demo ${D}${bindir}/fieldmesh-mac-frame-demo
    install -m 0755 ${B}/fieldmesh-gnss-nmea-reporter ${D}${bindir}/fieldmesh-gnss-nmea-reporter
    install -m 0755 ${B}/fieldmesh-native-ip-socket-demo ${D}${bindir}/fieldmesh-native-ip-socket-demo
    install -m 0755 ${B}/fieldmeshctl ${D}${bindir}/fieldmeshctl
    install -m 0755 ${B}/fieldmesh-state-daemon-demo ${D}${bindir}/fieldmesh-state-daemon-demo
    install -m 0755 ${B}/fieldmesh-swarm-adapter-demo ${D}${bindir}/fieldmesh-swarm-adapter-demo
    install -m 0755 ${B}/fieldmesh-tun-gateway-demo ${D}${bindir}/fieldmesh-tun-gateway-demo
    install -m 0755 ${B}/fieldmesh-tun-packetizer-demo ${D}${bindir}/fieldmesh-tun-packetizer-demo
    install -m 0755 ${B}/fieldmesh-two-pc-flow-demo ${D}${bindir}/fieldmesh-two-pc-flow-demo
    install -m 0755 ${S}/init${FIELDMESH_REPO_ROOT}/runtime/fieldmesh-state-daemon/fieldmesh-state-daemon-init ${D}${sysconfdir}/init.d/S55fieldmesh-state-daemon
    ln -sf ../init.d/S55fieldmesh-state-daemon ${D}${sysconfdir}/rcS.d/S55fieldmesh-state-daemon
}
