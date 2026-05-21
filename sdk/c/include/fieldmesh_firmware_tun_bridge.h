#ifndef FIELDMESH_FIRMWARE_TUN_BRIDGE_H
#define FIELDMESH_FIRMWARE_TUN_BRIDGE_H

#include "fieldmesh_firmware_packet_bridge.h"
#include "fieldmesh_sdk.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fieldmesh_fw_tun_reader {
    fieldmesh_tun_read_callback_t read_packet;
    void *user;
} fieldmesh_fw_tun_reader_t;

typedef struct fieldmesh_fw_tun_writer {
    fieldmesh_tun_write_callback_t write_packet;
    void *user;
} fieldmesh_fw_tun_writer_t;

/* Adapter for fieldmesh_fw_packet_bridge_read_cb_t. */
static inline int fieldmesh_fw_tun_read_packet(void *user,
                                               uint8_t *packet,
                                               uint16_t packet_capacity,
                                               uint16_t *out_packet_len)
{
    fieldmesh_fw_tun_reader_t *reader = (fieldmesh_fw_tun_reader_t *)user;
    size_t packet_len = 0u;
    fieldmesh_status_t status;

    if (!reader || !reader->read_packet || !packet || !out_packet_len ||
        packet_capacity == 0u) {
        return -1;
    }
    status = reader->read_packet(reader->user, packet, packet_capacity,
                                 &packet_len);
    if (status == FIELDMESH_ERR_TIMEOUT) {
        *out_packet_len = 0u;
        return 0;
    }
    if (status != FIELDMESH_OK || packet_len == 0u ||
        packet_len > packet_capacity || packet_len > UINT16_MAX) {
        return -1;
    }
    *out_packet_len = (uint16_t)packet_len;
    return 1;
}

/* Adapter for fieldmesh_fw_packet_bridge_write_cb_t. */
static inline int fieldmesh_fw_tun_write_packet(void *user,
                                                const uint8_t *packet,
                                                uint16_t packet_len)
{
    fieldmesh_fw_tun_writer_t *writer = (fieldmesh_fw_tun_writer_t *)user;
    size_t written_len = 0u;
    fieldmesh_status_t status;

    if (!writer || !writer->write_packet || !packet || packet_len == 0u) {
        return 0;
    }
    status = writer->write_packet(writer->user, packet, packet_len,
                                  &written_len);
    return status == FIELDMESH_OK && written_len == packet_len;
}

#ifdef __cplusplus
}
#endif

#endif
