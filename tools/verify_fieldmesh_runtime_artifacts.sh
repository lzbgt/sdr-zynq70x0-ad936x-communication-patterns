#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-all}"

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "Missing required file: $1" >&2
        exit 1
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

verify_variant() {
    local name="$1"
    local machine
    local image
    local build_name
    local package_dir
    local jtag_dir
    local dtb
    local rootfs_tar
    local rootfs_cpio
    local strings_out
    local ctl_strings_out
    local daemon_strings_out
    local swarm_adapter_strings_out
    local tun_gateway_strings_out
    local two_pc_strings_out

    case "$name" in
        z203)
            machine="sdr-z203-zynq7"
            image="sdr-z203-arm-image"
            build_name="sdr-z203-arm"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z203"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z203"
            dtb="$package_dir/devicetree/z203/z203-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        z103)
            machine="sdr-z103-zynq7"
            image="sdr-z103-arm-image"
            build_name="sdr-z103-arm"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z103"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z103"
            dtb="$package_dir/devicetree/z103/z103-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        *)
            echo "usage: $0 [all|z203|z103]" >&2
            exit 2
            ;;
    esac

    rootfs_tar="$repo_root/yocto/builds/$build_name/tmp/deploy/images/$machine/$image-$machine.rootfs.tar.gz"
    rootfs_cpio="$repo_root/yocto/builds/$build_name/tmp/deploy/images/$machine/$image-$machine.rootfs.cpio.gz"

    require_file "$rootfs_tar"
    require_file "$rootfs_cpio"
    require_file "$package_dir/fit-work/build/pluto.frm"
    require_file "$package_dir/fit-work/build/pluto.itb"
    require_file "$dtb"
    require_file "$jtag_dir/SHA256SUMS"
    require_file "$jtag_dir/boot/uImage"
    require_file "$jtag_dir/boot/uramdisk.image.gz"
    require_file "$jtag_dir/boot/devicetree.dtb"

    strings_out="$(mktemp)"
    device_iio_strings_out="$(mktemp)"
    ctl_strings_out="$(mktemp)"
    daemon_strings_out="$(mktemp)"
    swarm_adapter_strings_out="$(mktemp)"
    tun_gateway_strings_out="$(mktemp)"
    tun_packetizer_strings_out="$(mktemp)"
    two_pc_strings_out="$(mktemp)"
    trap 'rm -f "$strings_out" "$device_iio_strings_out" "$ctl_strings_out" "$daemon_strings_out" "$swarm_adapter_strings_out" "$tun_gateway_strings_out" "$tun_packetizer_strings_out" "$two_pc_strings_out"' RETURN
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-udp-probe | strings > "$strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-device-iio-demo | strings > "$device_iio_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmeshctl | strings > "$ctl_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-state-daemon-demo | strings > "$daemon_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-swarm-adapter-demo | strings > "$swarm_adapter_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-tun-gateway-demo | strings > "$tun_gateway_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-tun-packetizer-demo | strings > "$tun_packetizer_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-two-pc-flow-demo | strings > "$two_pc_strings_out"

    for token in adaptive-listen advertise ap-elect rtls-estimate dt-scan ctrl-scan dma-scan dma-plan dma-smoke iio-scan iio-plan pl-replay; do
        if ! grep -qxF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe role in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in udp-command user_command; do
        if ! grep -qF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe command path in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in 020000000203 020000000103; do
        if ! grep -qF "$token" "$strings_out"; then
            echo "Missing FieldMesh compact device EUI in $name probe: $token" >&2
            exit 1
        fi
    done
    for stale in z203-hub z103-endpoint z103-a z103-b z203-relay; do
        if grep -qF "$stale" "$strings_out"; then
            echo "Stale role-derived node identifier in $name probe: $stale" >&2
            exit 1
        fi
    done
    for token in \
        sdk_device_iio_profile \
        sdk_device_iio_plan \
        sdk_device_iio_live_plan \
        local_iio_device \
        host_eth_ip; do
        if ! grep -qF "$token" "$device_iio_strings_out"; then
            echo "Missing fieldmesh-device-iio-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        fieldmeshctl_profile_show \
        fieldmeshctl_profile_validate \
        fieldmeshctl_profile_apply \
        fieldmeshctl_profile_rollback \
        usb_device_ip \
        device_eui \
        persist_requested; do
        if ! grep -qF "$token" "$ctl_strings_out"; then
            echo "Missing fieldmeshctl token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        FIELDMESH_AP_BROWSE \
        FIELDMESH_AP_ELECT \
        FIELDMESH_AP_JOIN \
        FIELDMESH_STATE_PEERS \
        FIELDMESH_STATE_RTLS \
        FIELDMESH_SWARM_ADAPTER \
        FIELDMESH_RF_PACKET_ENGINE \
        FIELDMESH_TUN_FD_PUMP \
        FIELDMESH_TUN_DEV_PUMP \
        FIELDMESH_TUN_PLAN \
        FIELDMESH_TUN_APPLY_VALIDATE \
        FIELDMESH_TUN_APPLY_COMMIT \
        FIELDMESH_DEVICE_IIO_PLAN \
        sdk_daemon_ap_browse \
        sdk_daemon_ap_election \
        sdk_daemon_join_state \
        sdk_daemon_peer_state \
        sdk_daemon_rtls_state \
        sdk_daemon_swarm_adapter \
        sdk_daemon_rf_packet_engine \
        sdk_daemon_tun_fd_pump \
        sdk_daemon_tun_device_pump_guard \
        posix_pipe_fd \
        /dev/net/tun \
        requires_allow_live_tun_read \
        requires_existing_swarm0 \
        fieldmesh_rf_packet_engine \
        queued_to_rf_engine \
        uses_sidecar_dma \
        sdk_daemon_tun_plan \
        sdk_daemon_tun_apply \
        sdk_daemon_tun_apply_rejected \
        sdk_daemon_iio_bridge_plan \
        020000000203 \
        020000000103; do
        if ! grep -qF "$token" "$daemon_strings_out"; then
            echo "Missing fieldmesh-state-daemon-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        sdk_swarm_adapter_open \
        sdk_swarm_adapter_tx \
        sdk_swarm_adapter_rx \
        sdk_swarm_adapter_summary \
        swarm0 \
        packet_stream \
        tun_mvp_target; do
        if ! grep -qF "$token" "$swarm_adapter_strings_out"; then
            echo "Missing fieldmesh-swarm-adapter-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        sdk_tun_gateway_plan \
        sdk_tun_gateway_command \
        sdk_tun_gateway_apply \
        sdk_tun_gateway_rollback_command \
        swarm0 \
        creates_tun_on_board \
        writes_network \
        uses_inter_board_ip_routing \
        020000000103; do
        if ! grep -qF "$token" "$tun_gateway_strings_out"; then
            echo "Missing fieldmesh-tun-gateway-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        sdk_tun_packetizer_open \
        sdk_tun_packetizer_packet \
        sdk_tun_packetizer_summary \
        tun_ip_packet_stream \
        fieldmesh_rf_packet_engine \
        queued_to_sidecar \
        queued_to_rf_engine \
        uses_sidecar_dma \
        control_daemon \
        telemetry_mavlink \
        video_base_rtp \
        video_enhancement_rtp \
        bulk_tcp; do
        if ! grep -qF "$token" "$tun_packetizer_strings_out"; then
            echo "Missing fieldmesh-tun-packetizer-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        sdk_two_pc_ap_seen \
        sdk_two_pc_ap_elected \
        sdk_two_pc_join_accepted \
        sdk_two_pc_stream_opened \
        sdk_two_pc_stream_tx \
        sdk_two_pc_endpoint_flow_complete; do
        if ! grep -qF "$token" "$two_pc_strings_out"; then
            echo "Missing fieldmesh-two-pc-flow-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done

    (cd "$jtag_dir" && sha256sum -c SHA256SUMS >/dev/null)

    if ! cmp -s "$dtb" "$jtag_dir/boot/devicetree.dtb"; then
        echo "FieldMesh package DTB and JTAG RAM-boot DTB differ for $name" >&2
        exit 1
    fi

    printf 'fieldmesh_runtime_artifacts=%s\n' "$name"
    sha256sum \
        "$rootfs_cpio" \
        "$rootfs_tar" \
        "$package_dir/fit-work/build/pluto.frm" \
        "$package_dir/fit-work/build/pluto.itb" \
        "$dtb" \
        "$jtag_dir/boot/uImage" \
        "$jtag_dir/boot/uramdisk.image.gz" \
        "$jtag_dir/boot/devicetree.dtb"
}

require_cmd tar
require_cmd strings
require_cmd sha256sum

case "$variant" in
    all)
        verify_variant z203
        verify_variant z103
        ;;
    z203|z103)
        verify_variant "$variant"
        ;;
    *)
        echo "usage: $0 [all|z203|z103]" >&2
        exit 2
        ;;
esac
