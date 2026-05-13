#include "fieldmesh_sdk.h"

struct demo_state {
    fieldmesh_ap_info_t first_ap;
    int saw_ap;
};

static void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    struct demo_state *state = (struct demo_state *)user;

    if (!state->saw_ap && ap) {
        state->first_ap = *ap;
        state->saw_ap = 1;
    }
}

int main(void)
{
    fieldmesh_context_t *ctx = 0;
    fieldmesh_session_t *session = 0;
    fieldmesh_stream_t *stream = 0;
    struct demo_state state = {0};
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_AUTO,
        .control_port = 49000,
        .timeout_ms = 2000,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT),
        .timeout_ms = 5000,
    };
    fieldmesh_stream_config_t stream_config = {
        .stream_id = 1,
        .traffic_class = FIELDMESH_CLASS_C1_TELEMETRY,
        .requested_mode = FIELDMESH_MODE_AUTO,
        .deadline_ms = 50,
        .bitrate_hint_kbps = 64,
    };
    const char payload[] = "fieldmesh endpoint demo";
    fieldmesh_status_t status;

    status = fieldmesh_context_create(&config, &ctx);
    if (status != FIELDMESH_OK) {
        return 1;
    }

    status = fieldmesh_browse_aps(ctx, 2000, on_ap, &state);
    if (status == FIELDMESH_OK && state.saw_ap) {
        const char *node_id = state.first_ap.ap_id;

        (void)node_id;
        join.ap_id[0] = '\0';
        join.network_id[0] = '\0';
        status = fieldmesh_join_ap(ctx, &join, &session);
    }
    if (status == FIELDMESH_OK && session) {
        status = fieldmesh_open_stream(session, &stream_config, &stream);
    }
    if (status == FIELDMESH_OK && stream) {
        status = fieldmesh_send(stream, payload, sizeof(payload), 0);
        (void)fieldmesh_close_stream(stream);
    }
    if (session) {
        (void)fieldmesh_leave(session);
    }
    fieldmesh_context_destroy(ctx);
    return status == FIELDMESH_OK ? 0 : 1;
}
