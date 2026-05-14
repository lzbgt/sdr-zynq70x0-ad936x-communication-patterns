#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <string.h>

static int require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return 0;
    }
    fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return 1;
}

int main(void)
{
    fieldmesh_context_t *ctx = NULL;
    fieldmesh_session_t *session = NULL;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_GATEWAY),
        .timeout_ms = 1000,
    };
    fieldmesh_tun_config_t tun = {
        .adapter_name = "swarm0",
        .local_mesh_ip = "10.77.1.1",
        .remote_mesh_cidr = "10.77.2.0/24",
        .host_facing_device_ip = "192.168.2.1",
        .dst_node_id = "020000000103",
        .mesh_prefix_len = 16,
        .mtu_bytes = 1200,
    };
    fieldmesh_tun_plan_t plan;
    fieldmesh_tun_apply_report_t apply;

    strcpy(join.ap_id, "020000000203");
    strcpy(join.network_id, "fieldmesh-lab");
    strcpy(join.node_name, "tun-gateway-demo");

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create") ||
        require_ok(fieldmesh_report_peer_presence(ctx, tun.dst_node_id),
                   "report_peer_presence") ||
        require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                          "tun-gateway-demo"), "request_mode") ||
        require_ok(fieldmesh_plan_tun_adapter(session, &tun, &plan),
                   "plan_tun_adapter") ||
        require_ok(fieldmesh_apply_tun_adapter(session, &tun,
                                               FIELDMESH_TUN_APPLY_VALIDATE_ONLY,
                                               &apply),
                   "apply_tun_adapter_validate")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    printf("{\"event\":\"sdk_tun_gateway_plan\","
           "\"adapter_name\":\"%s\","
           "\"local_mesh_ip\":\"%s\","
           "\"mesh_prefix_len\":%u,"
           "\"remote_mesh_cidr\":\"%s\","
           "\"host_facing_device_ip\":\"%s\","
           "\"host_route_hint\":\"%s\","
           "\"dst_device_eui\":\"%s\","
           "\"adapter_kind\":%u,"
           "\"route_kind\":%u,"
           "\"selected_mode\":%u,"
           "\"mtu_bytes\":%u,"
           "\"creates_tun_on_board\":%u,"
           "\"creates_tun_on_host\":%u,"
           "\"uses_tap\":%u,"
           "\"uses_iio\":%u,"
           "\"uses_inter_board_ip_routing\":%u,"
           "\"requires_cap_net_admin\":%u,"
           "\"command_count\":%u}\n",
           plan.adapter_name, plan.local_mesh_ip, plan.mesh_prefix_len,
           plan.remote_mesh_cidr, plan.host_facing_device_ip, plan.host_route_hint,
           plan.dst_node_id, (unsigned)plan.adapter_kind,
           (unsigned)plan.route_kind, (unsigned)plan.selected_mode,
           plan.mtu_bytes, plan.creates_tun_on_board, plan.creates_tun_on_host,
           plan.uses_tap, plan.uses_iio, plan.uses_inter_board_ip_routing,
           plan.requires_cap_net_admin, plan.command_count);

    printf("{\"event\":\"sdk_tun_gateway_command\","
           "\"order\":1,\"command\":\"ip tuntap add dev swarm0 mode tun\"}\n");
    printf("{\"event\":\"sdk_tun_gateway_command\","
           "\"order\":2,\"command\":\"ip addr add 10.77.1.1/16 dev swarm0\"}\n");
    printf("{\"event\":\"sdk_tun_gateway_command\","
           "\"order\":3,\"command\":\"ip link set swarm0 mtu 1200 up\"}\n");
    printf("{\"event\":\"sdk_tun_gateway_command\","
           "\"order\":4,\"command\":\"ip route add 10.77.2.0/24 dev swarm0\"}\n");
    printf("{\"event\":\"sdk_tun_gateway_apply\","
           "\"accepted\":%u,"
           "\"dry_run\":%u,"
           "\"live_writes_requested\":%u,"
           "\"live_writes_authorized\":%u,"
           "\"commands_executed\":%u,"
           "\"writes_network\":%u,"
           "\"rollback_available\":%u,"
           "\"rollback_command_count\":%u}\n",
           apply.accepted, apply.dry_run, apply.live_writes_requested,
           apply.live_writes_authorized, apply.commands_executed,
           apply.writes_network, apply.rollback_available,
           apply.rollback_command_count);
    printf("{\"event\":\"sdk_tun_gateway_rollback_command\","
           "\"order\":1,\"command\":\"%s\"}\n",
           apply.rollback_hint);

    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return 0;
}
