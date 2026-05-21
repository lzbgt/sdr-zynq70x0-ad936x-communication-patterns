#include "fieldmesh_firmware_abi.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

static int write_blob(const char *dir, const char *name, const uint8_t *data, size_t len)
{
    char path[512];
    int n = snprintf(path, sizeof(path), "%s/%s", dir, name);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "path too long for %s/%s\n", dir, name);
        return 1;
    }
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return 1;
    }
    if (fwrite(data, 1, len, fp) != len) {
        fprintf(stderr, "write %s failed: %s\n", path, strerror(errno));
        fclose(fp);
        return 1;
    }
    if (fclose(fp) != 0) {
        fprintf(stderr, "close %s failed: %s\n", path, strerror(errno));
        return 1;
    }
    return 0;
}

static int ensure_dir(const char *dir)
{
    if (mkdir(dir, 0777) == 0 || errno == EEXIST) {
        return 0;
    }
    fprintf(stderr, "mkdir %s failed: %s\n", dir, strerror(errno));
    return 1;
}

int main(int argc, char **argv)
{
    const char *vector_dir = NULL;
    if (argc == 3 && strcmp(argv[1], "--write-vectors") == 0) {
        vector_dir = argv[2];
    } else if (argc != 1) {
        fprintf(stderr, "usage: %s [--write-vectors DIR]\n", argv[0]);
        return 2;
    }

    static const uint8_t crc_check[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
    fieldmesh_fw_tx_desc_v1_t tx;
    fieldmesh_fw_rx_desc_v1_t rx;
    fieldmesh_fw_ack_v1_t ack;

    fieldmesh_fw_tx_desc_v1_init(
        &tx,
        FIELDMESH_FW_STATE_QUEUED,
        1u,
        FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_FEC,
        3u,
        2u,
        4u,
        0x10203040u,
        0x0000010203040506ull,
        0x10000000u,
        76u,
        0x0000010203040900ull);

    fieldmesh_fw_rx_desc_v1_init(
        &rx,
        FIELDMESH_FW_STATE_READY,
        FIELDMESH_FW_RX_STATUS_CRC_OK | FIELDMESH_FW_RX_STATUS_FEC_OK,
        (int16_t)(-55 * 256),
        (int16_t)(18 * 256),
        -1250,
        2u,
        0x0000010203040555ull,
        0x10080000u,
        76u,
        3u,
        0x10203040u);

    fieldmesh_fw_ack_v1_init(
        &ack,
        FIELDMESH_FW_ACK_FLAG_SELECTIVE | FIELDMESH_FW_ACK_FLAG_LINK_METRIC,
        3u,
        0x10203000u,
        0x00000000ffffffffull,
        2u,
        2u);

    int ok = 1;
    ok = ok && fieldmesh_fw_crc32c(crc_check, sizeof(crc_check)) == 0xe3069283u;
    ok = ok && fieldmesh_fw_tx_desc_v1_valid(&tx);
    ok = ok && fieldmesh_fw_rx_desc_v1_valid(&rx);
    ok = ok && fieldmesh_fw_ack_v1_valid(&ack);
    ok = ok && tx.bytes[0] == FIELDMESH_FW_STATE_QUEUED;
    ok = ok && fieldmesh_fw_get_le16(tx.bytes + 24u) == 76u;
    ok = ok && fieldmesh_fw_get_le32(tx.bytes + 20u) == 0x10000000u;
    ok = ok && fieldmesh_fw_get_le32(rx.bytes + 20u) == 0x10080000u;
    ok = ok && (ack.bytes[0] >> 4) == FIELDMESH_FW_ABI_VERSION;
    ok = ok && (ack.bytes[0] & 0x0fu) == FIELDMESH_FW_ACK_TYPE;

    if (vector_dir) {
        if (ensure_dir(vector_dir) != 0 ||
            write_blob(vector_dir, "fieldmesh_fw_tx_desc_v1.bin", tx.bytes, sizeof(tx.bytes)) != 0 ||
            write_blob(vector_dir, "fieldmesh_fw_rx_desc_v1.bin", rx.bytes, sizeof(rx.bytes)) != 0 ||
            write_blob(vector_dir, "fieldmesh_fw_ack_v1.bin", ack.bytes, sizeof(ack.bytes)) != 0) {
            return 1;
        }
    }

    printf("{\"event\":\"fieldmesh_firmware_abi_probe\","
           "\"ok\":%s,"
           "\"abi_version\":%u,"
           "\"tx_desc_bytes\":%u,"
           "\"rx_desc_bytes\":%u,"
           "\"ack_frame_bytes\":%u,"
           "\"tx_crc32c\":\"0x%08x\","
           "\"rx_crc32c\":\"0x%08x\","
           "\"ack_crc16\":\"0x%04x\","
           "\"crc32c_check\":\"0x%08x\","
           "\"uses_json_on_air\":false,"
           "\"hot_path_language\":\"c\","
           "\"vendor_runtime_dependency\":false}\n",
           ok ? "true" : "false",
           FIELDMESH_FW_ABI_VERSION,
           FIELDMESH_FW_TX_DESC_V1_BYTES,
           FIELDMESH_FW_RX_DESC_V1_BYTES,
           FIELDMESH_FW_ACK_V1_BYTES,
           fieldmesh_fw_get_le32(tx.bytes + FIELDMESH_FW_TX_DESC_CRC_OFFSET),
           fieldmesh_fw_get_le32(rx.bytes + FIELDMESH_FW_RX_DESC_CRC_OFFSET),
           fieldmesh_fw_get_le16(ack.bytes + FIELDMESH_FW_ACK_CRC_OFFSET),
           fieldmesh_fw_crc32c(crc_check, sizeof(crc_check)));

    return ok ? 0 : 1;
}
