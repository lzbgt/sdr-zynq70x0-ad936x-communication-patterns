#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIELDMESH_MAX_APS 4
#define FIELDMESH_MAX_CANDIDATES 16
#define FIELDMESH_MAX_STREAM_PAYLOAD 2048

struct fieldmesh_context {
    fieldmesh_config_t config;
    fieldmesh_ap_info_t aps[FIELDMESH_MAX_APS];
    size_t ap_count;
    fieldmesh_ap_candidate_t candidates[FIELDMESH_MAX_CANDIDATES];
    size_t candidate_count;
    uint32_t next_sequence;
    uint32_t election_epoch;
};

struct fieldmesh_ap {
    fieldmesh_context_t *context;
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char policy_name[FIELDMESH_NAME_TEXT_MAX];
    int running;
};

struct fieldmesh_session {
    fieldmesh_context_t *context;
    fieldmesh_ap_info_t ap;
    fieldmesh_mode_t selected_mode;
    int joined;
};

struct fieldmesh_stream {
    fieldmesh_session_t *session;
    fieldmesh_stream_config_t config;
    unsigned char last_payload[FIELDMESH_MAX_STREAM_PAYLOAD];
    size_t last_payload_len;
    fieldmesh_packet_meta_t last_meta;
    int has_packet;
};

static void sdk_copy_text(char *dst, size_t dst_len, const char *src)
{
    if (!dst || dst_len == 0) {
        return;
    }
    if (!src) {
        dst[0] = '\0';
        return;
    }
    (void)snprintf(dst, dst_len, "%s", src);
}

static uint32_t mode_mask(void)
{
    return (1u << FIELDMESH_MODE_P2P) |
           (1u << FIELDMESH_MODE_STAR) |
           (1u << FIELDMESH_MODE_GRAPH) |
           (1u << FIELDMESH_MODE_SCHEDULED);
}

static uint32_t class_mask(fieldmesh_node_class_t node_class)
{
    return 1u << (uint32_t)node_class;
}

static void init_default_aps(fieldmesh_context_t *context)
{
    fieldmesh_ap_info_t *ap;

    context->ap_count = 2;

    ap = &context->aps[0];
    memset(ap, 0, sizeof(*ap));
    sdk_copy_text(ap->ap_id, sizeof(ap->ap_id), "z203-hub");
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), "fieldmesh-lab");
    sdk_copy_text(ap->name, sizeof(ap->name), "SDR-Z203 2R2T AP broker");
    sdk_copy_text(ap->address, sizeof(ap->address), "192.168.2.1:49000");
    ap->transport = FIELDMESH_TRANSPORT_USB_ETH;
    ap->supported_modes_mask = mode_mask();
    ap->node_classes_mask = class_mask(FIELDMESH_NODE_AP_BROKER) |
                            class_mask(FIELDMESH_NODE_RELAY) |
                            class_mask(FIELDMESH_NODE_GATEWAY);
    ap->max_kbps = 7000;
    ap->link_quality_hint_db = 28;
    ap->requires_audit = 1;
    ap->supports_derived_cert = 1;

    ap = &context->aps[1];
    memset(ap, 0, sizeof(*ap));
    sdk_copy_text(ap->ap_id, sizeof(ap->ap_id), "z103-emergency");
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), "fieldmesh-lab");
    sdk_copy_text(ap->name, sizeof(ap->name), "SDR-Z103 1R1T emergency AP");
    sdk_copy_text(ap->address, sizeof(ap->address), "192.168.2.1:49000");
    ap->transport = FIELDMESH_TRANSPORT_USB_ETH;
    ap->supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                               (1u << FIELDMESH_MODE_STAR);
    ap->node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT) |
                            class_mask(FIELDMESH_NODE_RELAY);
    ap->max_kbps = 2200;
    ap->link_quality_hint_db = 18;
    ap->requires_audit = 1;
    ap->supports_derived_cert = 0;
}

static fieldmesh_ap_candidate_t default_candidate(const char *node_id,
                                                  int z203_preferred)
{
    fieldmesh_ap_candidate_t candidate;

    memset(&candidate, 0, sizeof(candidate));
    sdk_copy_text(candidate.node_id, sizeof(candidate.node_id), node_id);
    candidate.policy = FIELDMESH_AP_POLICY_HYBRID;
    candidate.supported_modes_mask = z203_preferred ? mode_mask() :
        ((1u << FIELDMESH_MODE_P2P) | (1u << FIELDMESH_MODE_STAR));
    candidate.node_classes_mask = z203_preferred ?
        (class_mask(FIELDMESH_NODE_AP_BROKER) | class_mask(FIELDMESH_NODE_RELAY)) :
        (class_mask(FIELDMESH_NODE_ENDPOINT) | class_mask(FIELDMESH_NODE_RELAY));
    candidate.max_kbps = z203_preferred ? 7000u : 2200u;
    candidate.reachable_peer_count = z203_preferred ? 3u : 1u;
    candidate.avg_rssi_dbm = z203_preferred ? -42 : -58;
    candidate.avg_snr_db = z203_preferred ? 29 : 17;
    candidate.estimated_geo_centrality = z203_preferred ? 88u : 54u;
    candidate.link_stability_score = z203_preferred ? 90u : 62u;
    candidate.mobility_score = z203_preferred ? 82u : 55u;
    candidate.handover_penalty = z203_preferred ? 0u : 12u;
    candidate.uptime_s = z203_preferred ? 1200u : 300u;
    candidate.clock_quality = z203_preferred ? 95u : 45u;
    candidate.power_score = z203_preferred ? 100u : 55u;
    candidate.compute_score = z203_preferred ? 90u : 45u;
    candidate.relay_score = z203_preferred ? 92u : 38u;
    candidate.security_score = z203_preferred ? 90u : 70u;
    candidate.wall_powered = z203_preferred ? 1u : 0u;
    candidate.has_disciplined_clock = z203_preferred ? 1u : 0u;
    candidate.relay_allowed = 1u;
    candidate.provisioned_identity = 1u;
    return candidate;
}

static uint32_t normalized_signed_metric(int value, int min_value, int max_value)
{
    if (value < min_value) {
        value = min_value;
    }
    if (value > max_value) {
        value = max_value;
    }
    return (uint32_t)((value - min_value) * 100 / (max_value - min_value));
}

static uint32_t candidate_score(const fieldmesh_ap_candidate_t *candidate)
{
    uint32_t score = 0;
    uint32_t rssi = normalized_signed_metric(candidate->avg_rssi_dbm, -100, -20);
    uint32_t snr = normalized_signed_metric(candidate->avg_snr_db, 0, 40);
    uint32_t modes = 0;

    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_P2P)) {
        modes += 10u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_STAR)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_GRAPH)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_SCHEDULED)) {
        modes += 25u;
    }

    score += candidate->max_kbps / 16u;
    score += candidate->reachable_peer_count * 120u;
    score += rssi * 4u;
    score += snr * 5u;
    score += candidate->estimated_geo_centrality * 5u;
    score += candidate->link_stability_score * 4u;
    score += candidate->mobility_score * 4u;
    score += candidate->relay_score * 5u;
    score += candidate->clock_quality * 3u;
    score += candidate->power_score * 3u;
    score += candidate->compute_score * 2u;
    score += candidate->security_score * 3u;
    score += modes * 4u;
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) {
        score += 500u;
    }
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_GATEWAY)) {
        score += 250u;
    }
    if (candidate->wall_powered) {
        score += 200u;
    }
    if (candidate->has_disciplined_clock) {
        score += 160u;
    }
    if (candidate->relay_allowed) {
        score += 120u;
    }
    if (candidate->provisioned_identity) {
        score += 120u;
    }
    score -= candidate->handover_penalty * 6u;
    return score;
}

static const fieldmesh_ap_info_t *find_ap(const fieldmesh_context_t *context,
                                          const char *ap_id,
                                          const char *network_id)
{
    size_t i;

    for (i = 0; i < context->ap_count; ++i) {
        const fieldmesh_ap_info_t *ap = &context->aps[i];
        if (ap_id && ap_id[0] != '\0' && strcmp(ap->ap_id, ap_id) != 0) {
            continue;
        }
        if (network_id && network_id[0] != '\0' &&
            strcmp(ap->network_id, network_id) != 0) {
            continue;
        }
        return ap;
    }
    return context->ap_count > 0 ? &context->aps[0] : NULL;
}

fieldmesh_status_t fieldmesh_context_create(const fieldmesh_config_t *config,
                                            fieldmesh_context_t **out_context)
{
    fieldmesh_context_t *context;

    if (!out_context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_context = NULL;
    context = (fieldmesh_context_t *)calloc(1, sizeof(*context));
    if (!context) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    if (config) {
        context->config = *config;
    } else {
        context->config.transport = FIELDMESH_TRANSPORT_AUTO;
        context->config.control_port = 49000u;
        context->config.timeout_ms = 2000u;
    }
    context->next_sequence = 1u;
    context->election_epoch = 1u;
    init_default_aps(context);
    *out_context = context;
    return FIELDMESH_OK;
}

void fieldmesh_context_destroy(fieldmesh_context_t *context)
{
    free(context);
}

fieldmesh_status_t fieldmesh_browse_aps(fieldmesh_context_t *context,
                                        uint32_t timeout_ms,
                                        fieldmesh_ap_callback_t callback,
                                        void *user)
{
    size_t i;

    (void)timeout_ms;
    if (!context || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->ap_count; ++i) {
        callback(&context->aps[i], user);
    }
    return context->ap_count > 0 ? FIELDMESH_OK : FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_publish_ap_candidate(fieldmesh_context_t *context,
                                                  const fieldmesh_ap_candidate_t *candidate)
{
    if (!context || !candidate || candidate->node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->candidate_count >= FIELDMESH_MAX_CANDIDATES) {
        return FIELDMESH_ERR_POLICY;
    }
    context->candidates[context->candidate_count++] = *candidate;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_elect_ap(fieldmesh_context_t *context,
                                      fieldmesh_ap_policy_t policy,
                                      uint32_t timeout_ms,
                                      fieldmesh_ap_election_result_t *out_result)
{
    fieldmesh_ap_candidate_t defaults[2];
    const fieldmesh_ap_candidate_t *best = NULL;
    const fieldmesh_ap_candidate_t *candidates = NULL;
    size_t candidate_count = 0;
    size_t i;
    uint32_t best_score = 0;

    (void)timeout_ms;
    if (!context || !out_result) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (policy == FIELDMESH_AP_POLICY_PREDEFINED) {
        best = &context->candidates[0];
        candidate_count = context->candidate_count;
        candidates = context->candidates;
    } else if (context->candidate_count > 0) {
        candidates = context->candidates;
        candidate_count = context->candidate_count;
    } else {
        defaults[0] = default_candidate("z203-hub", 1);
        defaults[1] = default_candidate("z103-emergency", 0);
        candidates = defaults;
        candidate_count = 2u;
    }
    if (candidate_count == 0 || !candidates) {
        return FIELDMESH_ERR_NOT_FOUND;
    }

    for (i = 0; i < candidate_count; ++i) {
        uint32_t score = candidate_score(&candidates[i]);
        if (!best || score > best_score ||
            (score == best_score && strcmp(candidates[i].node_id, best->node_id) < 0)) {
            best = &candidates[i];
            best_score = score;
        }
    }

    memset(out_result, 0, sizeof(*out_result));
    sdk_copy_text(out_result->elected_node_id, sizeof(out_result->elected_node_id),
                  best->node_id);
    sdk_copy_text(out_result->network_id, sizeof(out_result->network_id),
                  "fieldmesh-lab");
    out_result->policy = policy;
    out_result->election_epoch = context->election_epoch++;
    out_result->candidate_score = best_score;
    out_result->temporary_ap =
        (best->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) ? 0u : 1u;
    out_result->handover_allowed = 1u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_accept_ap_handover(fieldmesh_context_t *context,
                                                const fieldmesh_ap_election_result_t *result)
{
    if (!context || !result || result->elected_node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return result->handover_allowed ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

fieldmesh_status_t fieldmesh_join_ap(fieldmesh_context_t *context,
                                     const fieldmesh_join_request_t *request,
                                     fieldmesh_session_t **out_session)
{
    const fieldmesh_ap_info_t *ap;
    fieldmesh_session_t *session;

    if (!context || !request || !out_session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_session = NULL;
    if (request->method != FIELDMESH_JOIN_CREDENTIAL &&
        request->method != FIELDMESH_JOIN_DERIVED_CERT &&
        request->method != FIELDMESH_JOIN_AP_AUDIT) {
        return FIELDMESH_ERR_AUTH;
    }
    ap = find_ap(context, request->ap_id, request->network_id);
    if (!ap) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    session = (fieldmesh_session_t *)calloc(1, sizeof(*session));
    if (!session) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    session->context = context;
    session->ap = *ap;
    session->selected_mode = FIELDMESH_MODE_AUTO;
    session->joined = 1;
    *out_session = session;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_leave(fieldmesh_session_t *session)
{
    if (!session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    session->joined = 0;
    free(session);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_start(fieldmesh_context_t *context,
                                      const char *network_id,
                                      const char *policy_name,
                                      fieldmesh_ap_t **out_ap)
{
    fieldmesh_ap_t *ap;

    if (!context || !network_id || !out_ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_ap = NULL;
    ap = (fieldmesh_ap_t *)calloc(1, sizeof(*ap));
    if (!ap) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    ap->context = context;
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), network_id);
    sdk_copy_text(ap->policy_name, sizeof(ap->policy_name),
                  policy_name ? policy_name : "commanded-ap");
    ap->running = 1;
    *out_ap = ap;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_stop(fieldmesh_ap_t *ap)
{
    if (!ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    ap->running = 0;
    free(ap);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_audit_join(fieldmesh_ap_t *ap,
                                           const char *node_id,
                                           int approve)
{
    if (!ap || !ap->running || !node_id || node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return approve ? FIELDMESH_OK : FIELDMESH_ERR_AUTH;
}

fieldmesh_status_t fieldmesh_list_peers(fieldmesh_session_t *session,
                                        fieldmesh_peer_callback_t callback,
                                        void *user)
{
    fieldmesh_peer_info_t peer;

    if (!session || !session->joined || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(&peer, 0, sizeof(peer));
    sdk_copy_text(peer.node_id, sizeof(peer.node_id), "z203-hub");
    sdk_copy_text(peer.name, sizeof(peer.name), "2R2T AP broker");
    peer.node_classes_mask = class_mask(FIELDMESH_NODE_AP_BROKER) |
                             class_mask(FIELDMESH_NODE_RELAY);
    peer.supported_modes_mask = mode_mask();
    peer.max_kbps = 7000u;
    peer.direct_reachable = 1u;
    peer.relay_allowed = 1u;
    callback(&peer, user);

    memset(&peer, 0, sizeof(peer));
    sdk_copy_text(peer.node_id, sizeof(peer.node_id), "z103-endpoint");
    sdk_copy_text(peer.name, sizeof(peer.name), "1R1T endpoint");
    peer.node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT);
    peer.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                (1u << FIELDMESH_MODE_STAR);
    peer.max_kbps = 2200u;
    peer.direct_reachable = 0u;
    peer.relay_allowed = 0u;
    callback(&peer, user);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_query_route(fieldmesh_session_t *session,
                                         const char *dst_node_id,
                                         uint16_t stream_id,
                                         fieldmesh_route_info_t *out_route)
{
    if (!session || !session->joined || !dst_node_id || !out_route) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_route, 0, sizeof(*out_route));
    sdk_copy_text(out_route->dst_node_id, sizeof(out_route->dst_node_id), dst_node_id);
    out_route->stream_id = stream_id;
    out_route->selected_mode = session->selected_mode;
    if (out_route->selected_mode == FIELDMESH_MODE_AUTO) {
        out_route->selected_mode = FIELDMESH_MODE_SCHEDULED;
    }
    if (strcmp(dst_node_id, "z203-hub") == 0) {
        out_route->route_kind = FIELDMESH_ROUTE_DIRECT;
    } else if (out_route->selected_mode == FIELDMESH_MODE_SCHEDULED) {
        out_route->route_kind = FIELDMESH_ROUTE_SCHEDULED_RELAY;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      session->ap.ap_id);
        out_route->slot = 3u;
        out_route->epoch = 1u;
    } else {
        out_route->route_kind = FIELDMESH_ROUTE_AP_RELAYED;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      session->ap.ap_id);
    }
    out_route->delivered_kbps = 1024u;
    out_route->queue_age_ms = 4u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_request_mode(fieldmesh_session_t *session,
                                          fieldmesh_mode_t mode,
                                          const char *reason)
{
    (void)reason;
    if (!session || !session->joined) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (mode != FIELDMESH_MODE_AUTO &&
        mode != FIELDMESH_MODE_P2P &&
        mode != FIELDMESH_MODE_STAR &&
        mode != FIELDMESH_MODE_GRAPH &&
        mode != FIELDMESH_MODE_SCHEDULED) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    session->selected_mode = mode;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_open_stream(fieldmesh_session_t *session,
                                         const fieldmesh_stream_config_t *config,
                                         fieldmesh_stream_t **out_stream)
{
    fieldmesh_stream_t *stream;

    if (!session || !session->joined || !config || !out_stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_stream = NULL;
    stream = (fieldmesh_stream_t *)calloc(1, sizeof(*stream));
    if (!stream) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    stream->session = session;
    stream->config = *config;
    if (stream->config.requested_mode != FIELDMESH_MODE_AUTO) {
        session->selected_mode = stream->config.requested_mode;
    }
    *out_stream = stream;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_close_stream(fieldmesh_stream_t *stream)
{
    if (!stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    free(stream);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_send(fieldmesh_stream_t *stream,
                                  const void *payload,
                                  size_t payload_len,
                                  const fieldmesh_packet_meta_t *meta)
{
    if (!stream || !stream->session || !payload || payload_len > FIELDMESH_MAX_STREAM_PAYLOAD) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memcpy(stream->last_payload, payload, payload_len);
    stream->last_payload_len = payload_len;
    memset(&stream->last_meta, 0, sizeof(stream->last_meta));
    if (meta) {
        stream->last_meta = *meta;
    }
    sdk_copy_text(stream->last_meta.src_node_id, sizeof(stream->last_meta.src_node_id),
                  "local-node");
    if (stream->last_meta.dst_node_id[0] == '\0') {
        sdk_copy_text(stream->last_meta.dst_node_id, sizeof(stream->last_meta.dst_node_id),
                      stream->config.dst_node_id[0] ? stream->config.dst_node_id : "z103-endpoint");
    }
    stream->last_meta.stream_id = stream->config.stream_id;
    stream->last_meta.traffic_class = stream->config.traffic_class;
    stream->last_meta.mode = stream->session->selected_mode == FIELDMESH_MODE_AUTO ?
        stream->config.requested_mode : stream->session->selected_mode;
    if (stream->last_meta.mode == FIELDMESH_MODE_AUTO) {
        stream->last_meta.mode = FIELDMESH_MODE_SCHEDULED;
    }
    stream->last_meta.sequence = stream->session->context->next_sequence++;
    stream->last_meta.epoch = 1u;
    stream->last_meta.slot = 3u;
    stream->last_meta.queue_age_ms = 1u;
    stream->has_packet = 1;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_recv(fieldmesh_stream_t *stream,
                                  void *payload,
                                  size_t payload_capacity,
                                  size_t *out_payload_len,
                                  fieldmesh_packet_meta_t *out_meta,
                                  uint32_t timeout_ms)
{
    (void)timeout_ms;
    if (!stream || !payload || !out_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!stream->has_packet) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    if (payload_capacity < stream->last_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memcpy(payload, stream->last_payload, stream->last_payload_len);
    *out_payload_len = stream->last_payload_len;
    if (out_meta) {
        *out_meta = stream->last_meta;
    }
    stream->has_packet = 0;
    return FIELDMESH_OK;
}

const char *fieldmesh_status_string(fieldmesh_status_t status)
{
    switch (status) {
    case FIELDMESH_OK:
        return "ok";
    case FIELDMESH_ERR_INVALID_ARG:
        return "invalid-arg";
    case FIELDMESH_ERR_TIMEOUT:
        return "timeout";
    case FIELDMESH_ERR_NO_MEMORY:
        return "no-memory";
    case FIELDMESH_ERR_TRANSPORT:
        return "transport";
    case FIELDMESH_ERR_AUTH:
        return "auth";
    case FIELDMESH_ERR_POLICY:
        return "policy";
    case FIELDMESH_ERR_NOT_FOUND:
        return "not-found";
    case FIELDMESH_ERR_UNSUPPORTED:
        return "unsupported";
    default:
        return "unknown";
    }
}
