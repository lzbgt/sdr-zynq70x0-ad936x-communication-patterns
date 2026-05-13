#include "fieldmesh_sdk.h"

int main(void)
{
    fieldmesh_context_t *ctx = 0;
    fieldmesh_ap_t *ap = 0;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_AUTO,
        .control_port = 49000,
        .timeout_ms = 2000,
    };
    fieldmesh_status_t status;

    status = fieldmesh_context_create(&config, &ctx);
    if (status != FIELDMESH_OK) {
        return 1;
    }

    /*
     * Production applications should call this only when the user, application
     * policy, or provisioning profile commands this node to become AP/broker.
     */
    status = fieldmesh_ap_start(ctx, "fieldmesh-lab", "hybrid-ap-or-swarm", &ap);
    if (status == FIELDMESH_OK) {
        (void)fieldmesh_ap_stop(ap);
    }

    fieldmesh_context_destroy(ctx);
    return status == FIELDMESH_OK ? 0 : 1;
}
