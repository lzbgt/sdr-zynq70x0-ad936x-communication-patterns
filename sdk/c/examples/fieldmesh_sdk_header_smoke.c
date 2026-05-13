#include "fieldmesh_sdk.h"

static void ap_seen(const fieldmesh_ap_info_t *ap, void *user)
{
    (void)ap;
    (void)user;
}

static void peer_seen(const fieldmesh_peer_info_t *peer, void *user)
{
    (void)peer;
    (void)user;
}

int main(void)
{
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT),
        .timeout_ms = 5000,
    };
    fieldmesh_stream_config_t stream = {
        .stream_id = 1,
        .traffic_class = FIELDMESH_CLASS_C1_TELEMETRY,
        .requested_mode = FIELDMESH_MODE_AUTO,
        .deadline_ms = 50,
        .bitrate_hint_kbps = 64,
    };
    fieldmesh_ap_candidate_t candidate = {
        .policy = FIELDMESH_AP_POLICY_HYBRID,
        .node_classes_mask = (1u << FIELDMESH_NODE_AP_BROKER),
        .supported_modes_mask = (1u << FIELDMESH_MODE_STAR) | (1u << FIELDMESH_MODE_SCHEDULED),
        .max_kbps = 7000,
        .reachable_peer_count = 2,
        .avg_rssi_dbm = -42,
        .avg_snr_db = 29,
        .estimated_geo_centrality = 88,
        .link_stability_score = 90,
        .mobility_score = 82,
        .clock_quality = 100,
        .power_score = 100,
        .relay_score = 100,
        .wall_powered = 1,
        .has_disciplined_clock = 1,
        .relay_allowed = 1,
    };
    fieldmesh_ap_election_result_t election = {
        .policy = FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM,
        .election_epoch = 1,
        .temporary_ap = 1,
        .handover_allowed = 1,
    };
    fieldmesh_packet_meta_t meta = {
        .stream_id = 1,
        .traffic_class = FIELDMESH_CLASS_C1_TELEMETRY,
        .mode = FIELDMESH_MODE_AUTO,
    };
    fieldmesh_device_profile_t device = {
        .center_frequency_hz = 2400000000ull,
        .sample_rate_hz = 1000000,
        .rf_bandwidth_hz = 1000000,
        .fixture_attenuation_db = 60,
        .conducted_or_shielded = 1,
        .legal_frequency_profile = 1,
        .tx_enable_guard = 1,
        .rx_first_required = 1,
    };
    fieldmesh_device_validation_report_t device_report = {
        .valid = 1,
        .uses_inter_board_ip_routing = 0,
    };
    fieldmesh_iio_burst_plan_t iio_plan = {
        .rx_first = 1,
        .command_count = 8,
        .iq_samples = 6656,
    };

    (void)config;
    (void)join;
    (void)stream;
    (void)candidate;
    (void)election;
    (void)meta;
    (void)device;
    (void)device_report;
    (void)iio_plan;
    (void)ap_seen;
    (void)peer_seen;
    return FIELDMESH_OK;
}
