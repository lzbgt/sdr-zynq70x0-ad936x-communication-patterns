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
    static const unsigned char payload[] = {
        0x01u, 0x04u, 0x10u, 0x20u, 0x33u, 0x55u, 0x89u, 0xabu
    };
    static const unsigned char declare_payload[] = {
        FIELDMESH_MAC_TLV_DEVICE_NAME, 0x04u, 'z', '2', '0', '3',
        FIELDMESH_MAC_TLV_DTYPE, 0x02u, 0x00u, 0x22u,
        FIELDMESH_MAC_TLV_CAPABILITY_MASK, 0x04u, 0x00u, 0x00u, 0x00u, 0x0fu,
        FIELDMESH_MAC_TLV_GNSS_POSITION, 0x10u,
        0x00u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x00u, 0x00u,
        0x00u, 0x00u, 0x00u, 0x78u
    };
    static const unsigned char sdk_payload[] = {
        FIELDMESH_SDK_TLV_DEVICE_EUI, 0x00u, 0x00u, 0x06u,
        0x02u, 0x00u, 0x00u, 0x02u, 0x03u,
        FIELDMESH_SDK_TLV_DTYPE, 0x00u, 0x00u, 0x02u,
        0x00u, 0x22u,
        FIELDMESH_SDK_TLV_CAPS, 0x00u, 0x00u, 0x04u,
        0x00u, 0x00u, 0x00u, 0x0fu
    };
    fieldmesh_mac_frame_header_t header;
    fieldmesh_mac_frame_header_t decoded;
    fieldmesh_mac_frame_header_t declare_header;
    fieldmesh_mac_frame_header_t decoded_declare;
    fieldmesh_sdk_frame_header_t sdk_header;
    fieldmesh_sdk_frame_header_t decoded_sdk;
    unsigned char frame[128];
    unsigned char declare_frame[160];
    unsigned char sdk_frame[128];
    unsigned char decoded_payload[32];
    unsigned char decoded_declare_payload[64];
    unsigned char decoded_sdk_payload[64];
    char src_text[FIELDMESH_EUI_TEXT_MAX];
    char dst_text[FIELDMESH_EUI_TEXT_MAX];
    size_t frame_len = 0u;
    size_t declare_frame_len = 0u;
    size_t sdk_frame_len = 0u;
    size_t decoded_payload_len = 0u;
    size_t decoded_declare_len = 0u;
    size_t decoded_sdk_len = 0u;

    memset(&header, 0, sizeof(header));
    header.version = FIELDMESH_MAC_VERSION_1;
    header.profile_id = 7u;
    header.frame_type = FIELDMESH_MAC_FRAME_APP_DATA;
    header.traffic_class = FIELDMESH_CLASS_C2_VIDEO_BASE;
    header.path_mode = FIELDMESH_MAC_PATH_DIRECT_P2P;
    header.hop_limit = 1u;
    header.sequence = 42u;
    header.stream_id = 502u;
    if (require_ok(fieldmesh_eui_from_text("020000000203", header.src_eui),
                   "src_eui_from_text") ||
        require_ok(fieldmesh_eui_from_text("020000000103", header.dst_eui),
                   "dst_eui_from_text") ||
        require_ok(fieldmesh_encode_mac_frame(&header, payload, sizeof(payload),
                                              frame, sizeof(frame), &frame_len),
                   "encode_mac_frame") ||
        require_ok(fieldmesh_decode_mac_frame(frame, frame_len, &decoded,
                                              decoded_payload,
                                              sizeof(decoded_payload),
                                              &decoded_payload_len),
                   "decode_mac_frame") ||
        require_ok(fieldmesh_eui_to_text(decoded.src_eui, src_text,
                                         sizeof(src_text)),
                   "src_eui_to_text") ||
        require_ok(fieldmesh_eui_to_text(decoded.dst_eui, dst_text,
                                         sizeof(dst_text)),
                   "dst_eui_to_text")) {
        return 1;
    }
    if (decoded_payload_len != sizeof(payload) ||
        memcmp(decoded_payload, payload, sizeof(payload)) != 0 ||
        decoded.version != FIELDMESH_MAC_VERSION_1 ||
        decoded.frame_type != FIELDMESH_MAC_FRAME_APP_DATA ||
        decoded.traffic_class != FIELDMESH_CLASS_C2_VIDEO_BASE ||
        decoded.path_mode != FIELDMESH_MAC_PATH_DIRECT_P2P ||
        strcmp(src_text, "020000000203") != 0 ||
        strcmp(dst_text, "020000000103") != 0) {
        fprintf(stderr, "decoded BLR MAC frame did not match input\n");
        return 1;
    }

    declare_header = header;
    declare_header.frame_type = FIELDMESH_MAC_FRAME_PRESENCE;
    declare_header.traffic_class = FIELDMESH_CLASS_C1_TELEMETRY;
    declare_header.path_mode = FIELDMESH_MAC_PATH_GROUP_FANOUT;
    declare_header.hop_limit = 1u;
    declare_header.sequence = 43u;
    declare_header.stream_id = 1u;
    if (require_ok(fieldmesh_encode_mac_frame(&declare_header,
                                              declare_payload,
                                              sizeof(declare_payload),
                                              declare_frame,
                                              sizeof(declare_frame),
                                              &declare_frame_len),
                   "encode_declare_frame") ||
        require_ok(fieldmesh_decode_mac_frame(declare_frame,
                                              declare_frame_len,
                                              &decoded_declare,
                                              decoded_declare_payload,
                                              sizeof(decoded_declare_payload),
                                              &decoded_declare_len),
                   "decode_declare_frame")) {
        return 1;
    }
    if (decoded_declare.frame_type != FIELDMESH_MAC_FRAME_PRESENCE ||
        decoded_declare.path_mode != FIELDMESH_MAC_PATH_GROUP_FANOUT ||
        decoded_declare_len != sizeof(declare_payload) ||
        memcmp(decoded_declare_payload, declare_payload,
               sizeof(declare_payload)) != 0) {
        fprintf(stderr, "decoded BLR declare frame did not match input\n");
        return 1;
    }

    memset(&sdk_header, 0, sizeof(sdk_header));
    sdk_header.version = FIELDMESH_SDK_VERSION_1;
    sdk_header.msg_type = FIELDMESH_SDK_MSG_PEER_DIRECTORY;
    sdk_header.header_len_bytes = FIELDMESH_SDK_HEADER_BYTES;
    sdk_header.sequence = 100u;
    sdk_header.request_id = 0x203103u;
    sdk_header.tlv_count = 3u;
    if (require_ok(fieldmesh_encode_sdk_frame(&sdk_header, sdk_payload,
                                              sizeof(sdk_payload),
                                              sdk_frame, sizeof(sdk_frame),
                                              &sdk_frame_len),
                   "encode_sdk_frame") ||
        require_ok(fieldmesh_decode_sdk_frame(sdk_frame, sdk_frame_len,
                                              &decoded_sdk,
                                              decoded_sdk_payload,
                                              sizeof(decoded_sdk_payload),
                                              &decoded_sdk_len),
                   "decode_sdk_frame")) {
        return 1;
    }
    if (decoded_sdk.version != FIELDMESH_SDK_VERSION_1 ||
        decoded_sdk.msg_type != FIELDMESH_SDK_MSG_PEER_DIRECTORY ||
        decoded_sdk.header_len_bytes != FIELDMESH_SDK_HEADER_BYTES ||
        decoded_sdk.tlv_count != 3u ||
        decoded_sdk_len != sizeof(sdk_payload) ||
        memcmp(decoded_sdk_payload, sdk_payload, sizeof(sdk_payload)) != 0) {
        fprintf(stderr, "decoded BLR SDK frame did not match input\n");
        return 1;
    }

    printf("{\"event\":\"sdk_mac_frame\","
           "\"magic\":\"BLR\","
           "\"version\":%u,"
           "\"header_bytes\":%u,"
           "\"trailer_bytes\":%u,"
           "\"frame_bytes\":%lu,"
           "\"payload_bytes\":%lu,"
           "\"frame_type\":%u,"
           "\"traffic_class\":%u,"
           "\"path_mode\":%u,"
           "\"src_eui\":\"%s\","
           "\"dst_eui\":\"%s\","
           "\"header_crc32c\":%u,"
           "\"payload_crc32c\":%u,"
           "\"uses_json_on_air\":0,"
           "\"carries_peer_name_per_frame\":0,"
           "\"declare_frame_type\":%u,"
           "\"declare_payload_bytes\":%lu,"
           "\"tlv_name\":%u,"
           "\"tlv_gnss\":%u,"
           "\"tlv_dtype\":%u,"
           "\"dtype_2r2t\":%u}\n",
           (unsigned)decoded.version,
           (unsigned)FIELDMESH_MAC_HEADER_BYTES,
           (unsigned)FIELDMESH_MAC_TRAILER_BYTES,
           (unsigned long)frame_len,
           (unsigned long)decoded_payload_len,
           (unsigned)decoded.frame_type,
           (unsigned)decoded.traffic_class,
           (unsigned)decoded.path_mode,
           src_text,
           dst_text,
           decoded.header_crc32c,
           decoded.payload_crc32c,
           (unsigned)decoded_declare.frame_type,
           (unsigned long)decoded_declare_len,
           (unsigned)FIELDMESH_MAC_TLV_DEVICE_NAME,
           (unsigned)FIELDMESH_MAC_TLV_GNSS_POSITION,
           (unsigned)FIELDMESH_MAC_TLV_DTYPE,
           (unsigned)FIELDMESH_DEVICE_TYPE_2R2T);
    printf("{\"event\":\"sdk_payload_frame\","
           "\"magic\":\"BLR\","
           "\"version\":%u,"
           "\"header_bytes\":%u,"
           "\"tlv_header_bytes\":%u,"
           "\"trailer_bytes\":%u,"
           "\"frame_bytes\":%lu,"
           "\"payload_bytes\":%lu,"
           "\"msg_type\":%u,"
           "\"tlv_count\":%u,"
           "\"tlv_eui\":%u,"
           "\"tlv_dtype\":%u,"
           "\"tlv_caps\":%u,"
           "\"header_crc32c\":%u,"
           "\"payload_crc32c\":%u,"
           "\"uses_json\":0,"
           "\"stm32f1_parseable\":1}\n",
           (unsigned)decoded_sdk.version,
           (unsigned)FIELDMESH_SDK_HEADER_BYTES,
           (unsigned)FIELDMESH_SDK_TLV_HEADER_BYTES,
           (unsigned)FIELDMESH_SDK_TRAILER_BYTES,
           (unsigned long)sdk_frame_len,
           (unsigned long)decoded_sdk_len,
           (unsigned)decoded_sdk.msg_type,
           (unsigned)decoded_sdk.tlv_count,
           (unsigned)FIELDMESH_SDK_TLV_DEVICE_EUI,
           (unsigned)FIELDMESH_SDK_TLV_DTYPE,
           (unsigned)FIELDMESH_SDK_TLV_CAPS,
           decoded_sdk.header_crc32c,
           decoded_sdk.payload_crc32c);
    return 0;
}
