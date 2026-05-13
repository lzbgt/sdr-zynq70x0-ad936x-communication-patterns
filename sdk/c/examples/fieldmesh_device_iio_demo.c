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

static void print_report(const char *event,
                         const fieldmesh_device_validation_report_t *report)
{
    printf("{\"event\":\"%s\",\"valid\":%u,\"live_rf_allowed\":%u,"
           "\"opens_iio_buffers\":%u,\"starts_rf_tx\":%u,"
           "\"writes_hardware\":%u,\"uses_inter_board_ip_routing\":%u,"
           "\"message\":\"%s\"}\n",
           event, report->valid, report->live_rf_allowed,
           report->opens_iio_buffers, report->starts_rf_tx,
           report->writes_hardware, report->uses_inter_board_ip_routing,
           report->message);
}

int main(void)
{
    fieldmesh_context_t *ctx = 0;
    fieldmesh_device_profile_t tx_profile;
    fieldmesh_device_profile_t rx_profile;
    fieldmesh_device_validation_report_t report;
    fieldmesh_iio_burst_plan_t plan;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create") ||
        require_ok(fieldmesh_get_device_profile(ctx, &tx_profile), "get_tx_profile") ||
        require_ok(fieldmesh_get_device_profile(ctx, &rx_profile), "get_rx_profile")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    snprintf(tx_profile.board_id, sizeof(tx_profile.board_id), "%s", "z203");
    snprintf(tx_profile.iio_uri, sizeof(tx_profile.iio_uri), "%s", "ip:192.168.2.1");
    snprintf(rx_profile.board_id, sizeof(rx_profile.board_id), "%s", "z103");
    snprintf(rx_profile.iio_uri, sizeof(rx_profile.iio_uri), "%s", "ip:192.168.3.1");

    if (require_ok(fieldmesh_validate_device_profile(ctx, &tx_profile, &report),
                   "validate_tx_profile") ||
        require_ok(fieldmesh_set_device_profile(ctx, &tx_profile), "set_tx_profile")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    print_report("sdk_device_iio_profile", &report);

    if (require_ok(fieldmesh_plan_iio_burst(ctx, &tx_profile, &rx_profile, 6656u,
                                            &plan), "plan_iio_burst")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    printf("{\"event\":\"sdk_device_iio_plan\",\"sdk_layer\":\"local_iio_device\","
           "\"served_over\":\"host_eth_ip\",\"tx_uri\":\"%s\",\"rx_uri\":\"%s\","
           "\"tx_device\":\"%s\",\"rx_device\":\"%s\",\"rx_first\":%u,"
           "\"commands\":%u,\"iq_samples\":%u,"
           "\"uses_inter_board_ip_routing\":%u,"
           "\"opens_iio_buffers\":%u,\"starts_rf_tx\":%u,"
           "\"writes_hardware\":%u,\"live_rf_allowed\":%u}\n",
           plan.tx_iio_uri, plan.rx_iio_uri, plan.tx_device, plan.rx_device,
           plan.rx_first, plan.command_count, plan.iq_samples,
           plan.uses_inter_board_ip_routing, plan.opens_iio_buffers,
           plan.starts_rf_tx, plan.writes_hardware, plan.live_rf_allowed);

    rx_profile.fixture_attenuation_db = 10u;
    if (fieldmesh_validate_device_profile(ctx, &rx_profile, &report) != FIELDMESH_ERR_POLICY) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    print_report("sdk_device_iio_reject_low_attenuation", &report);

    tx_profile.allow_hardware_writes = 1u;
    rx_profile.fixture_attenuation_db = 60u;
    rx_profile.allow_hardware_writes = 1u;
    if (require_ok(fieldmesh_validate_device_profile(ctx, &tx_profile, &report),
                   "validate_tx_live_profile") ||
        require_ok(fieldmesh_plan_iio_burst(ctx, &tx_profile, &rx_profile, 6656u,
                                            &plan), "plan_live_iio_burst")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    printf("{\"event\":\"sdk_device_iio_live_plan\",\"live_rf_allowed\":%u,"
           "\"opens_iio_buffers\":%u,\"starts_rf_tx\":%u,"
           "\"writes_hardware\":%u,\"rx_first\":%u}\n",
           plan.live_rf_allowed, plan.opens_iio_buffers, plan.starts_rf_tx,
           plan.writes_hardware, plan.rx_first);

    fieldmesh_context_destroy(ctx);
    return 0;
}
