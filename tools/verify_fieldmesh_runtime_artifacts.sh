#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"
variant="${1:-all}"
require_current_fw_dma_runtime="${FIELDMESH_REQUIRE_CURRENT_FW_DMA_RUNTIME:-1}"
require_current_rf_guard_runtime="${FIELDMESH_REQUIRE_CURRENT_RF_GUARD_RUNTIME:-1}"
require_current_sidecar_addr_runtime="${FIELDMESH_REQUIRE_CURRENT_SIDECAR_ADDR_RUNTIME:-1}"

case "$require_current_fw_dma_runtime" in
    0|1)
        ;;
    *)
        echo "FIELDMESH_REQUIRE_CURRENT_FW_DMA_RUNTIME must be 0 or 1" >&2
        exit 2
        ;;
esac
case "$require_current_rf_guard_runtime" in
    0|1)
        ;;
    *)
        echo "FIELDMESH_REQUIRE_CURRENT_RF_GUARD_RUNTIME must be 0 or 1" >&2
        exit 2
        ;;
esac
case "$require_current_sidecar_addr_runtime" in
    0|1)
        ;;
    *)
        echo "FIELDMESH_REQUIRE_CURRENT_SIDECAR_ADDR_RUNTIME must be 0 or 1" >&2
        exit 2
        ;;
esac

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
    local camera_stream_strings_out
    local strings_out
    local ctl_strings_out
    local daemon_strings_out
    local swarm_adapter_strings_out
    local tun_gateway_strings_out
    local two_pc_strings_out
    local packet_bridge_strings_out
    local rf_safe_tune_out
    local rf_tx_enable_out
    local rf_tx_disable_out
    local rf_common_out
    local rf_ctrl_write_out
    local freshness_env
    local freshness_artifact_env
    local freshness_args
    local fit_info_out
    local runtime_manifest
    local rootfs_md5
    local fit_ramdisk_md5

    case "$name" in
        z203)
            fieldmesh_resolve_image_paths z203 "$repo_root"
            machine="$FIELDMESH_MACHINE"
            image="$FIELDMESH_IMAGE_NAME"
            build_name="$FIELDMESH_BUILD_NAME"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z203"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z203"
            dtb="$package_dir/devicetree/z203/z203-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        z103)
            fieldmesh_resolve_image_paths z103 "$repo_root"
            machine="$FIELDMESH_MACHINE"
            image="$FIELDMESH_IMAGE_NAME"
            build_name="$FIELDMESH_BUILD_NAME"
            package_dir="$repo_root/.config/fieldmesh/runtime-package-z103"
            jtag_dir="$repo_root/.config/fieldmesh/jtag-ram-boot-z103"
            dtb="$package_dir/devicetree/z103/z103-zynq-pluto-sdr-fieldmesh.dtb"
            ;;
        *)
            echo "usage: $0 [all|z203|z103]" >&2
            exit 2
            ;;
    esac

    rootfs_tar="$FIELDMESH_ROOTFS_TAR"
    rootfs_cpio="$FIELDMESH_ROOTFS_CPIO_GZ"

    require_file "$rootfs_tar"
    require_file "$rootfs_cpio"
    require_file "$package_dir/fit-work/build/pluto.frm"
    require_file "$package_dir/fit-work/build/pluto.itb"
    runtime_manifest="$package_dir/fieldmesh_runtime_package_manifest.json"
    require_file "$runtime_manifest"
    require_file "$dtb"
    require_file "$jtag_dir/SHA256SUMS"
    require_file "$jtag_dir/boot/uImage"
    require_file "$jtag_dir/boot/uramdisk.image.gz"
    require_file "$jtag_dir/boot/devicetree.dtb"

    strings_out="$(mktemp)"
    camera_stream_strings_out="$(mktemp)"
    device_iio_strings_out="$(mktemp)"
    ctl_strings_out="$(mktemp)"
    daemon_strings_out="$(mktemp)"
    daemon_init_out="$(mktemp)"
    swarm_adapter_strings_out="$(mktemp)"
    tun_gateway_strings_out="$(mktemp)"
    tun_packetizer_strings_out="$(mktemp)"
    two_pc_strings_out="$(mktemp)"
    uio_ring_strings_out="$(mktemp)"
    packet_bridge_strings_out="$(mktemp)"
    tun_bridge_strings_out="$(mktemp)"
    mac_frame_strings_out="$(mktemp)"
    gnss_reporter_strings_out="$(mktemp)"
    rf_safe_tune_out="$(mktemp)"
    rf_tx_enable_out="$(mktemp)"
    rf_tx_disable_out="$(mktemp)"
    rf_common_out="$(mktemp)"
    rf_ctrl_write_out="$(mktemp)"
    rf_tx_backend_out="$(mktemp)"
    fit_info_out="$(mktemp)"
    trap 'rm -f "$strings_out" "$camera_stream_strings_out" "$device_iio_strings_out" "$ctl_strings_out" "$daemon_strings_out" "$daemon_init_out" "$swarm_adapter_strings_out" "$tun_gateway_strings_out" "$tun_packetizer_strings_out" "$two_pc_strings_out" "$uio_ring_strings_out" "$packet_bridge_strings_out" "$tun_bridge_strings_out" "$mac_frame_strings_out" "$gnss_reporter_strings_out" "$rf_safe_tune_out" "$rf_tx_enable_out" "$rf_tx_disable_out" "$rf_common_out" "$rf_ctrl_write_out" "$rf_tx_backend_out" "$fit_info_out"' RETURN
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-udp-probe | strings > "$strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-camera-stream-demo | strings > "$camera_stream_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-device-iio-demo | strings > "$device_iio_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmeshctl | strings > "$ctl_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-state-daemon-demo | strings > "$daemon_strings_out"
    tar -xOf "$rootfs_tar" ./etc/init.d/S55fieldmesh-state-daemon | strings > "$daemon_init_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-swarm-adapter-demo | strings > "$swarm_adapter_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-tun-gateway-demo | strings > "$tun_gateway_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-tun-packetizer-demo | strings > "$tun_packetizer_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-two-pc-flow-demo | strings > "$two_pc_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-firmware-uio-ring-probe | strings > "$uio_ring_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-firmware-packet-bridge-probe | strings > "$packet_bridge_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-firmware-tun-bridge-probe | strings > "$tun_bridge_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-mac-frame-demo | strings > "$mac_frame_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-gnss-nmea-reporter | strings > "$gnss_reporter_strings_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-radio-safe-tune | strings > "$rf_safe_tune_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-radio-tx-enable | strings > "$rf_tx_enable_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-radio-tx-disable | strings > "$rf_tx_disable_out"
    tar -xOf "$rootfs_tar" ./usr/libexec/fieldmesh/fieldmesh-radio-common.sh | strings > "$rf_common_out"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-ctrl-write | strings > "$rf_ctrl_write_out"
    tar -xOf "$rootfs_tar" ./usr/libexec/fieldmesh/fieldmesh-rf-tx-enable-backend | strings > "$rf_tx_backend_out"
    if ! tar -tf "$rootfs_tar" | awk '$0 == "./usr/bin/iperf3" { found = 1 } END { exit found ? 0 : 1 }'; then
        echo "Missing iperf3 in $name rootfs" >&2
        exit 1
    fi

    for token in adaptive-listen advertise ap-elect rtls-estimate dt-scan ctrl-scan dma-scan dma-plan dma-smoke rf-guard-scan rf-guard-apply rf-source-apply rf-guard-action-policy-self-test iio-scan iio-plan pl-replay; do
        if ! grep -qxF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe role in $name rootfs: $token" >&2
            exit 1
        fi
    done
    python3 - "$runtime_manifest" "$name" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
name = sys.argv[2]
if manifest.get("event") != "fieldmesh_runtime_package_manifest":
    raise SystemExit(f"{name}: invalid runtime package manifest: {manifest!r}")
if manifest.get("variant") != name:
    raise SystemExit(f"{name}: runtime package manifest variant mismatch: {manifest!r}")
if manifest.get("overlay") != "rf_engine":
    raise SystemExit(f"{name}: production runtime must use RF-engine overlay, not {manifest.get('overlay')!r}")
bitstream = manifest.get("bitstream") or ""
if "rf-engine-overlay-build" not in bitstream:
    raise SystemExit(f"{name}: production runtime bitstream is not from RF-engine overlay: {bitstream!r}")
for key in ("bitstream_sha256", "devicetree_sha256"):
    value = manifest.get(key)
    if not isinstance(value, str) or len(value) != 64:
        raise SystemExit(f"{name}: missing {key} in runtime package manifest: {manifest!r}")
PY

    for token in sets_ad936x_tx_enable rf_guard_apply_rollback rf_guard_scan_start rf_source_apply_rollback allow-rf-source-select readback_ok rf_page_addressable tx_done_any rf_guard_late_drop guard_apply_allowed source_select_allowed rollback_needed; do
        if ! grep -qF "$token" "$strings_out"; then
            echo "Missing fieldmesh-udp-probe RF guard token in $name rootfs: $token" >&2
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
    for token in \
        sdk_camera_stream \
        swarm0 \
        fieldmesh_rf_packet_engine \
        queued_to_rf_engine \
        uses_inter_board_ip_routing \
        control_plane_ok \
        data_plane_ok \
        020000000203 \
        020000000103; do
        if ! grep -qF "$token" "$camera_stream_strings_out"; then
            echo "Missing fieldmesh-camera-stream-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in sdk_mac_frame BLR carries_peer_name_per_frame tlv_dtype dtype_2r2t fieldmesh_ingest_mac_frame; do
        if ! grep -qF "$token" "$mac_frame_strings_out"; then
            echo "Missing fieldmesh-mac-frame-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in fieldmesh_firmware_packet_bridge_probe ipv4_to_firmware_ring read_callback_pump write_callback_drain binary_descriptors uses_json_on_air hot_path_language read_errors "--device /dev/uioN" "--loopback" "--allow-writes"; do
        if ! grep -qF -- "$token" "$packet_bridge_strings_out"; then
            echo "Missing fieldmesh-firmware-packet-bridge-probe token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in fieldmesh_firmware_uio_ring_probe "--device /dev/uioN" "--pl-service" pl_service_polls writes_packet_memory native_c_sidecar_addr_contract; do
        if ! grep -qF -- "$token" "$uio_ring_strings_out"; then
            echo "Missing fieldmesh-firmware-uio-ring-probe token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in fieldmesh_firmware_tun_bridge_probe fieldmesh_tun_read_callback_t fieldmesh_tun_write_callback_t read_callback_pump write_callback_drain firmware_owns_posix_fd swarm0_ready_boundary binary_descriptors uses_json_on_air hot_path_language read_errors "--device /dev/uioN" "--image PATH" mapped_memory sync_ok; do
        if ! grep -qF -- "$token" "$tun_bridge_strings_out"; then
            echo "Missing fieldmesh-firmware-tun-bridge-probe token in $name rootfs: $token" >&2
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
        FIELDMESH_HELLO \
        FIELDMESH_AP_BROWSE \
        FIELDMESH_AP_ELECT \
        FIELDMESH_AP_JOIN \
        FIELDMESH_STATE_PEERS \
        FIELDMESH_STATE_RTLS \
        FIELDMESH_SWARM_ADAPTER \
        FIELDMESH_RF_PACKET_ENGINE \
        FIELDMESH_RF_TX_GUARD_PLAN \
        FIELDMESH_APP_CONTROL_CAMERA \
        FIELDMESH_CAMERA_SESSION_PLAN \
        FIELDMESH_CAMERA_ADAPTATION_FEEDBACK \
        FIELDMESH_CAMERA_STREAM_CHUNK \
        FIELDMESH_ROUTE_METRICS \
        FIELDMESH_TUN_FD_PUMP \
        FIELDMESH_TUN_DEV_PUMP \
        FIELDMESH_TUN_DEV_PUMP_BURST \
        FIELDMESH_TUN_DEV_DRAIN_BURST \
        FIELDMESH_TUN_EVENT_LOOP_STEP \
        FIELDMESH_TUN_SERVICE_START \
        FIELDMESH_TUN_SERVICE_STATUS \
        FIELDMESH_TUN_SERVICE_STOP \
        FIELDMESH_TUN_PLAN \
        FIELDMESH_TUN_APPLY_VALIDATE \
        FIELDMESH_TUN_APPLY_COMMIT \
        FIELDMESH_DEVICE_IIO_PLAN \
        sdk_daemon_hello \
        sdk_daemon_ap_browse \
        sdk_daemon_ap_election \
        sdk_daemon_join_state \
        sdk_daemon_peer_state \
        sdk_daemon_rtls_state \
        sdk_daemon_rtls_position \
        sdk_daemon_rtls_report \
        sdk_daemon_route_metrics \
        sdk_daemon_swarm_adapter \
        sdk_daemon_rf_packet_engine \
        sdk_daemon_rf_tx_guard_plan \
        sdk_daemon_app_control_camera \
        sdk_daemon_camera_session_plan \
        sdk_daemon_camera_adaptation \
        sdk_daemon_camera_stream_chunk \
        fieldmesh_plan_camera_stream_session \
        fieldmesh_query_route_metrics \
        fieldmesh_adapt_camera_stream_session \
        fieldmesh_camera_stream_frame \
        root_ca_derived_certs \
        requires_mutual_auth_for_production \
        production_ready \
        infrastructure_verified_rf_phy_pending \
        planned_features_production_level \
        app_verified_real_rf \
        rf_hw \
        rf_air \
        rf_queue \
        rf_phy_tx_rx_verified \
        real_rf_phy_tx_rx_not_verified \
        supports_camera_stream_chunk \
        supports_rtls_position \
        supports_rtls_report \
        supports_native_ip_gateway \
        supports_tcp_ip_client_apps \
        native_client_ip_mode \
        routed_l3_swarm0 \
        input_checksum \
        preview_checksum \
        preview_matches \
        fieldmesh-control-camera \
        proactive_camera_streamer \
        sdk_daemon_tun_fd_pump \
        sdk_daemon_tun_device_pump_guard \
        sdk_daemon_tun_device_pump_burst_live \
        sdk_daemon_tun_device_drain_burst_guard \
        sdk_daemon_tun_device_drain_burst_live \
        sdk_daemon_tun_event_loop_step_guard \
        sdk_daemon_tun_event_loop_step_live \
        sdk_daemon_tun_service_start_guard \
        sdk_daemon_tun_service_started \
        sdk_daemon_tun_service_status \
        sdk_daemon_tun_service_stopped \
        bounded_batch \
        posix_pipe_fd \
        /dev/net/tun \
        requires_allow_live_tun_read \
        requires_allow_live_tun_write \
        requires_existing_swarm0 \
        written_to_tun \
        client_kernel_ip_stack \
        continuous_tun_event_loop \
        rf_phy_tx_rx \
        poll_loop_active \
        rf_mac_app_data_path \
        rf_frames_egressed \
        rf_frames_ingressed \
        rf_transport_mode \
        driver_queue \
        diagnostic_loopback \
        firmware_ring_supported \
        firmware_ring_enabled \
        firmware_ring_mapped \
        firmware_ring_pumped \
        firmware_ring_served \
        firmware_ring_drained \
        firmware_ring_loopback \
        ALLOW_FIRMWARE_RING_WRITES \
        /dev/uio0 \
        daemon_owned_firmware_ring \
        supports_rf_transport_driver_queue \
        supports_rf_worker \
        supports_rf_worker_phy_plan \
        supports_rf_phy_driver_bind \
        sdk_daemon_rf_worker_start \
        sdk_daemon_rf_worker_status \
        FIELDMESH_RF_SERVICE_NEXT_BURST \
        sdk_daemon_rf_service_next_burst \
        native_service_burst \
        deferred_lease_frames \
        in_burst_priority_preemption \
        in_burst_priority_preempted \
        in_burst_priority_preemption_count \
        in_burst_priority_multiplexing \
        in_burst_preempted_score \
        in_burst_deferred_head_score \
        FIELDMESH_RF_SERVICE_LOOP_TICK \
        FIELDMESH_RF_SERVICE_TRANSPORT_LOOP_TICK \
        sdk_daemon_rf_service_loop_tick \
        sdk_daemon_rf_service_transport_loop_tick \
        native_service_loop_tick \
        native_cross_daemon_transport_loop \
        native_peer_scheduler_query \
        persistent_native_transport_loop_process \
        FIELDMESH_RF_SERVICE_LOOP_START \
        sdk_daemon_rf_service_loop_start \
        FIELDMESH_RF_SERVICE_LOOP_STATUS \
        sdk_daemon_rf_service_loop_status \
        native_service_loop_worker \
        service_skipped \
        FIELDMESH_RF_SERVICE_SCHEDULER_STATUS \
        sdk_daemon_rf_service_scheduler_status \
        native_direction_scheduler \
        scheduler_score_native_c \
        native_bidirectional_rf_service_scheduler \
        FIELDMESH_RF_SERVICE_DIRECTION_DECISION \
        sdk_daemon_rf_service_direction_decision \
        native_bidirectional_direction_decision \
        service_local_first \
        yield_to_peer \
        service_order_rank \
        persistent_native_bidirectional_rf_service_loop \
        native_service_loop_worker_process \
        native_cross_daemon_transport_worker_process \
        native_rf_service_worker \
        native_rf_service_control_plane \
        service_policy_bound \
        production_iio_policy \
        adaptive_modem_profile_policy \
        adaptive_modem_profile_policy_native_c \
        fast_primary_min_raw_bitrate_bps \
        fast_primary_requires_primary_decode \
        fast_primary_rejects_modem_retry \
        fast_primary_decision \
        retry_fallback_decision \
        fast_primary_high_rate_proven \
        retry_fallback_high_rate_proven \
        adaptive_modem_profile_measured_quality_policy \
        adaptive_modem_profile_measured_quality_native_c \
        fast_primary_min_decode_attempts \
        fast_primary_max_primary_per_mille \
        fast_primary_quality_decision \
        retry_fallback_quality_decision \
        insufficient_quality_decision \
        FIELDMESH_RF_MODEM_PROFILE_DECISION \
        sdk_daemon_rf_modem_profile_decision \
        live_rf_worker_mcs_selection \
        FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER \
        state_daemon_iio_transport_execution_worker \
        state_daemon_libiio_execution_owner \
        helper_local_libiio_execution_only \
        execution_worker_runs \
        persistent_native_rf_service_worker \
        sdk_daemon_rf_worker_phy_plan \
        sdk_daemon_rf_phy_driver_bind_validate \
        sdk_daemon_rf_phy_driver_bind_apply \
        sdk_daemon_rf_worker_stop \
        requires_sidecar_preflight \
        requires_sidecar_dma \
        requires_rf_tx_guard \
        requires_rf_dac_source_select \
        rf_dac_source_select_passed \
        driver_prerequisites_ready \
        live_rf_prerequisites_ready \
        rf_phy_driver_tx_rx \
        daemon_owned_worker \
        driver_queue_worker \
        sdk_daemon_rf_tx_poll \
        sdk_daemon_rf_tx_lease \
        sdk_daemon_rf_tx_lease_batch \
        sdk_daemon_rf_tx_ack \
        sdk_daemon_rf_tx_ack_batch \
        rf_tx_queue_duplicate_drops \
        sdk_daemon_rf_rx_ingest \
        fieldmesh_rf_packet_engine \
        queued_to_rf_engine \
        uses_sidecar_dma \
        sdk_daemon_tun_plan \
        sdk_daemon_tun_apply \
        sdk_daemon_tun_apply_rejected \
        sdk_daemon_iio_bridge_plan \
        sdk_daemon_rtls_clear \
        has_gnss_position \
        live_gnss_reporter \
        selection_mode \
        user_explicit \
        auto_election \
        dst_device_eui \
        020000000203 \
        020000000103; do
        if ! grep -qF "$token" "$daemon_strings_out"; then
            echo "Missing fieldmesh-state-daemon-demo token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in fieldmesh-state-daemon-demo "serve 0.0.0.0" "55441" \
            REQUESTS=0 fieldmesh_daemon_port LOG_MAX_BYTES rotate_log_if_needed \
            GNSS_LOG_MAX_BYTES rotate_named_log_if_needed run-gnss \
            fieldmesh-gnss-nmea-reporter gnss_nmea_device gnss_nmea_max_reports \
            read_sd_boot_config read_fwenv /dev/mmcblk0p1 fieldmesh_ \
            fieldmesh_gnss_nmea_device fieldmesh_gnss_nmea_baud \
            gnss_pps_lock FIELDMESH_GNSS_NMEA_MAX_REPORTS \
            fieldmesh_gnss_reporter_skip no_gnss_nmea_device_configured \
            fieldmesh_gnss_reporter_start; do
        if ! grep -qF "$token" "$daemon_init_out"; then
            echo "Missing FieldMesh daemon init token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        fieldmesh_gnss_nmea_report \
        fieldmesh_gnss_nmea_status \
        receiver_warning \
        gnss_receiver_io_overvoltage \
        FIELDMESH_RTLS_REPORT \
        '"ok":true' \
        gnss_no_satellites_visible \
        gps_lat_e7 \
        gps_lon_e7 \
        turnaround_calibrated=0 \
        report_origin=gnss_nmea_reporter; do
        if ! grep -qF "$token" "$gnss_reporter_strings_out"; then
            echo "Missing fieldmesh-gnss-nmea-reporter token in $name rootfs: $token" >&2
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
    for token in \
        FIELD_MESH_FIXTURE_ATTENUATION_DB \
        iio_attr \
        fieldmesh_radio_safe_tune; do
        if ! grep -qF -- "$token" "$rf_safe_tune_out"; then
            echo "Missing fieldmesh-radio-safe-tune token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        FIELD_MESH_EXECUTE_LIVE_TX \
        FIELD_MESH_ALLOW_HARDWARE_WRITES \
        FIELD_MESH_ALLOW_RF_TX \
        FIELD_MESH_FIXTURE_ID \
        FIELD_MESH_BACKEND_DRY_RUN; do
        if ! grep -qF -- "$token" "$rf_common_out"; then
            echo "Missing fieldmesh-radio-common token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        FIELD_MESH_MAX_TX_DURATION_MS \
        fieldmesh-radio-tx-disable \
        fieldmesh_radio_tx_enable; do
        if ! grep -qF -- "$token" "$rf_tx_enable_out"; then
            echo "Missing fieldmesh-radio-tx-enable token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        FIELD_MESH_ALLOW_HARDWARE_WRITES \
        -89.75 \
        fieldmesh_radio_tx_disable; do
        if ! grep -qF -- "$token" "$rf_tx_disable_out"; then
            echo "Missing fieldmesh-radio-tx-disable token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    for token in \
        fieldmesh_rf_tx_enable_backend \
        fieldmesh_rf_tx_enable_backend_request \
        --bounded-tx-enable \
        --request \
        native_iio_attr_control \
        native_rf_control \
        FIELD_MESH_BACKEND_CTRL_MEM_FILE \
        FIELD_MESH_BACKEND_CTRL_MEM_NO_WRITE \
        fieldmesh_rf_tx_enable_backend_iio_attr \
        fieldmesh_rf_tx_enable_backend_ctrl_reg \
        fieldmesh_rf_tx_enable_backend_sleep \
        --rollback \
        native_tune \
        tune_center_frequency \
        tune_sample_rate \
        tune_rf_bandwidth \
        prewrite_policy \
        select_fieldmesh_dac_source \
        source_select_readback \
        source_control_asserted \
        arm_fieldmesh_tx_guard \
        guard_arm_readback \
        guard_control_armed \
        write_suppressed \
        requires_c_rf_guard_action_policy_self_test \
        requires_native_rf_control \
        starts_rf_tx_when_executed \
        ctrl_base \
        rf_slot_epoch \
        rf_slot_index \
        preflight_assert \
        center_frequency_hz \
        sample_rate_hz \
        rf_bandwidth_hz \
        tx_attenuation_db \
        rollback_tx_attenuation_db; do
        if ! grep -qF -- "$token" "$rf_tx_backend_out"; then
            echo "Missing fieldmesh-rf-tx-enable-backend token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    if grep -qF -- "fieldmesh-radio-tx-enable failed" "$rf_tx_backend_out"; then
        echo "Packaged fieldmesh-rf-tx-enable-backend in $name still delegates to shell TX-enable" >&2
        exit 1
    fi
    for token in \
        fieldmesh-radio-tx-enable \
        fieldmesh-radio-safe-tune \
        fieldmesh-radio-tx-disable \
        fieldmesh-ctrl-write; do
        if grep -qF -- "$token" "$rf_tx_backend_out"; then
            echo "Packaged fieldmesh-rf-tx-enable-backend in $name still carries shell live-control token: $token" >&2
            exit 1
        fi
    done
    for token in \
        fieldmesh_ctrl_write \
        FIELD_MESH_EXECUTE_LIVE_TX \
        FIELD_MESH_ALLOW_HARDWARE_WRITES \
        FIELD_MESH_ALLOW_HARDWARE_READS \
        FIELD_MESH_ALLOW_FIRMWARE_DMA \
        fieldmesh_fw_dma_status \
        --fw-dma-arm \
        --fw-dma-stop \
        "default firmware-DMA BASE" \
        fw_dma_arm_control \
        /dev/mem; do
        if ! grep -qF -- "$token" "$rf_ctrl_write_out"; then
            echo "Missing fieldmesh-ctrl-write token in $name rootfs: $token" >&2
            exit 1
        fi
    done
    case "$name" in
        z203)
            freshness_env="FIELDMESH_RUNTIME_STRINGS_FILE_Z203=$rf_ctrl_write_out"
            freshness_udp_env="FIELDMESH_RUNTIME_UDP_PROBE_STRINGS_FILE_Z203=$strings_out"
            freshness_artifact_env="FIELDMESH_RUNTIME_ARTIFACT_Z203=$rootfs_tar"
            ;;
        z103)
            freshness_env="FIELDMESH_RUNTIME_STRINGS_FILE_Z103=$rf_ctrl_write_out"
            freshness_udp_env="FIELDMESH_RUNTIME_UDP_PROBE_STRINGS_FILE_Z103=$strings_out"
            freshness_artifact_env="FIELDMESH_RUNTIME_ARTIFACT_Z103=$rootfs_tar"
            ;;
        *)
            echo "unsupported runtime freshness variant: $name" >&2
            exit 2
            ;;
    esac
    freshness_args=("$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" "$name")
    if [[ "$require_current_fw_dma_runtime" == "1" &&
          "$require_current_rf_guard_runtime" == "1" &&
          "$require_current_sidecar_addr_runtime" == "1" ]]; then
        freshness_args+=("--require-current")
        env "$freshness_env" "$freshness_udp_env" "$freshness_artifact_env" "${freshness_args[@]}"
    else
        env "$freshness_env" "$freshness_udp_env" "$freshness_artifact_env" "${freshness_args[@]}"
        if [[ "$require_current_fw_dma_runtime" == "1" ]]; then
            env "$freshness_env" "$freshness_udp_env" "$freshness_artifact_env" \
                "$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" \
                "$name" --require-current-fw-dma >/dev/null
        fi
        if [[ "$require_current_rf_guard_runtime" == "1" ]]; then
            env "$freshness_env" "$freshness_udp_env" "$freshness_artifact_env" \
                "$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" \
                "$name" --require-current-rf-guard >/dev/null
        fi
        if [[ "$require_current_sidecar_addr_runtime" == "1" ]]; then
            env "$freshness_env" "$freshness_udp_env" "$freshness_artifact_env" \
                "$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" \
                "$name" --require-current-sidecar-addr >/dev/null
        fi
    fi

    (cd "$jtag_dir" && sha256sum -c SHA256SUMS >/dev/null)

    if ! cmp -s "$dtb" "$jtag_dir/boot/devicetree.dtb"; then
        echo "FieldMesh package DTB and JTAG RAM-boot DTB differ for $name" >&2
        exit 1
    fi

    dumpimage -l "$package_dir/fit-work/build/pluto.itb" > "$fit_info_out" 2>/dev/null
    rootfs_md5="$(md5sum "$rootfs_cpio" | awk '{print $1}')"
    fit_ramdisk_md5="$(
        awk '
            /Description:[[:space:]]+Ramdisk/ { in_ramdisk = 1 }
            in_ramdisk && /Hash value:/ { print $3; exit }
        ' "$fit_info_out"
    )"
    if [[ -z "$fit_ramdisk_md5" ]]; then
        echo "Could not find FIT ramdisk hash for $name" >&2
        exit 1
    fi
    if [[ "$fit_ramdisk_md5" != "$rootfs_md5" ]]; then
        echo "Stale FIT ramdisk for $name: FIT md5=$fit_ramdisk_md5 rootfs md5=$rootfs_md5" >&2
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
require_cmd dumpimage

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
