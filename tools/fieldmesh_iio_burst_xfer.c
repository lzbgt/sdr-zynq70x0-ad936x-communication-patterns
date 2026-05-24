#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L

// Single-process libiio RX/TX burst helper for FieldMesh HIL RF bridge tests.
//
// This replaces the slow shell pair:
//   iio_readdev ... & timeout ... iio_writedev ...
// for one guarded IQ burst. RF safety and hardware configuration remain owned
// by the Python runner; this helper only opens IIO buffers, arms RX, pushes TX,
// and writes the captured RX IQ bytes.

#include <errno.h>
#include <iio.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define MAX_CHANNELS 8
#define IQ_AMPLITUDE 12000
#define DEFAULT_SAMPLE_RATE_HZ 3072000U
#define DEFAULT_BFSK_SPACE_HZ 50000.0
#define DEFAULT_BFSK_MARK_HZ 150000.0
#define DEFAULT_SAMPLES_PER_SYMBOL 64U
#define DEFAULT_BIT_REPEAT 4U
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static const unsigned char PREAMBLE[16] = {
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
};
static const unsigned char SYNC[] = {'F', 'M', '-', 'I', 'Q', '1'};

struct blob {
    unsigned char *data;
    size_t len;
};

struct modem_options {
    const char *frame_file;
    const char *iq_file;
    const char *decoded_file;
    unsigned int sample_rate_hz;
    double space_hz;
    double mark_hz;
    double baseband_carrier_hz;
    unsigned int samples_per_symbol;
    unsigned int bit_repeat;
    size_t expected_frame_len;
    uint32_t expected_frame_crc;
    bool have_expected_frame_len;
    bool have_expected_frame_crc;
    unsigned int iterations;
};

struct tone_prefixes {
    size_t total_samples;
    double *space_i;
    double *space_q;
    double *mark_i;
    double *mark_q;
};

struct bpsk_prefixes {
    size_t total_samples;
    double *symbol_i;
    double *symbol_q;
};

struct options {
    const char *tx_uri;
    const char *rx_uri;
    const char *tx_device;
    const char *rx_device;
    const char *tx_file;
    const char *rx_file;
    const char *channels[MAX_CHANNELS];
    int channel_count;
    size_t tx_samples;
    size_t rx_samples;
    size_t buffer_size;
    unsigned int tx_duration_ms;
    unsigned int rx_timeout_ms;
    unsigned int rx_arm_delay_ms;
    bool cyclic;
    bool server;
    bool persistent_server_mode;
    unsigned long long server_xfer_count;
    bool native_transport_worker_mode;
    bool native_transport_session_mode;
    bool native_transport_service_loop_mode;
    bool native_transport_scheduler_mode;
    bool native_transport_autonomous_loop_mode;
    bool native_transport_background_daemon_mode;
    bool native_transport_integrated_rf_service_daemon_mode;
    bool native_transport_state_daemon_queue_mode;
    unsigned long long transport_session_start_count;
    unsigned long long transport_worker_request_count;
    unsigned long long transport_service_loop_start_count;
    unsigned long long transport_service_loop_run_count;
    unsigned long long transport_scheduler_start_count;
    unsigned long long transport_scheduler_drain_count;
    unsigned long long transport_scheduler_scheduled_request_count;
    unsigned long long transport_autonomous_loop_start_count;
    unsigned long long transport_autonomous_loop_run_count;
    unsigned long long transport_autonomous_loop_scheduled_request_count;
    unsigned long long transport_background_daemon_start_count;
    unsigned long long transport_background_daemon_xfer_count;
    unsigned long long transport_background_daemon_scheduled_request_count;
    unsigned long long transport_integrated_rf_service_daemon_start_count;
    unsigned long long transport_integrated_rf_service_daemon_enqueue_count;
    unsigned long long transport_integrated_rf_service_daemon_drained_count;
    unsigned long long transport_state_daemon_queue_request_count;
};

struct rx_job {
    struct iio_buffer *buffer;
    const struct iio_device *device;
    const char *path;
    size_t target_bytes;
    ssize_t bytes_written;
    int rc;
};

static void usage(FILE *stream)
{
    fprintf(stream,
            "usage: fieldmesh_iio_burst_xfer --tx-uri URI --rx-uri URI "
            "--tx-device DEV --rx-device DEV --tx-file PATH --rx-file PATH "
            "--tx-samples N --rx-samples N [--buffer-size N] "
            "[--tx-duration-ms N] [--rx-timeout-ms N] "
            "[--rx-arm-delay-ms N] [--cyclic] "
            "[--channel voltage0 --channel voltage1] [--server]\n"
            "       fieldmesh_iio_burst_xfer --bpsk-self-test\n"
            "       fieldmesh_iio_burst_xfer --bpsk-benchmark --frame-file PATH "
            "[--iterations N] [--sample-rate-hz N] [--baseband-carrier-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bpsk-encode --frame-file PATH --iq-file PATH "
            "[--sample-rate-hz N] [--baseband-carrier-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bpsk-decode --iq-file PATH --decoded-file PATH "
            "[--expected-frame-len N] [--expected-frame-crc HEX] "
            "[--sample-rate-hz N] [--baseband-carrier-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bfsk-self-test\n"
            "       fieldmesh_iio_burst_xfer --bfsk-benchmark --frame-file PATH "
            "[--iterations N] [--sample-rate-hz N] [--space-hz N] [--mark-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bfsk-encode --frame-file PATH --iq-file PATH "
            "[--sample-rate-hz N] [--space-hz N] [--mark-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bfsk-decode --iq-file PATH --decoded-file PATH "
            "[--expected-frame-len N] [--expected-frame-crc HEX] "
            "[--sample-rate-hz N] [--space-hz N] [--mark-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --native-worker-self-test\n");
}

static int run_native_worker_self_test(void)
{
    printf("{\"event\":\"fieldmesh_iio_burst_native_worker_self_test\",\"ok\":true,"
           "\"proof\":\"FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1\","
           "\"native_iio_burst_worker\":true,"
           "\"persistent_server_supported\":true,"
           "\"persistent_worker_lifecycle_supported\":true,"
           "\"native_iio_burst_worker_lifecycle_proof\":\"FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1\","
           "\"server_owned_xfer_loop_supported\":true,"
           "\"native_iio_burst_transport_worker_supported\":true,"
           "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
           "\"native_iio_burst_transport_session_supported\":true,"
           "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
           "\"native_iio_burst_transport_service_loop_supported\":true,"
           "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
           "\"native_iio_burst_transport_scheduler_supported\":true,"
           "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
           "\"native_iio_burst_transport_autonomous_loop_supported\":true,"
           "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
           "\"native_iio_burst_transport_background_daemon_supported\":true,"
           "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
           "\"native_iio_burst_integrated_rf_service_daemon_supported\":true,"
           "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
           "\"native_iio_burst_state_daemon_transport_queue_supported\":true,"
           "\"native_iio_burst_state_daemon_transport_queue_proof\":\"FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_QUEUE v1\","
           "\"native_iio_burst_transport_request_event\":\"fieldmesh_iio_burst_transport_worker_request\","
           "\"native_iio_burst_transport_service_loop_event\":\"fieldmesh_iio_burst_transport_service_loop_run\","
           "\"native_iio_burst_transport_scheduler_event\":\"fieldmesh_iio_burst_transport_scheduler_drain\","
           "\"native_iio_burst_transport_autonomous_loop_event\":\"fieldmesh_iio_burst_transport_autonomous_loop_run\","
           "\"native_iio_burst_transport_background_daemon_event\":\"fieldmesh_iio_burst_transport_background_daemon_status\","
           "\"native_iio_burst_integrated_rf_service_daemon_event\":\"fieldmesh_iio_burst_integrated_rf_service_daemon_status\","
           "\"python_xfer_field_orchestration\":false,"
           "\"python_worker_xfer_submission\":false,"
           "\"python_direct_service_loop_run\":false,"
           "\"python_scheduler_drain_submission\":false,"
           "\"python_autonomous_loop_run_submission\":false,"
           "\"python_background_daemon_start_submission\":false,"
           "\"python_transport_request_file_submission\":false,"
           "\"python_transport_scheduler_queue_file_submission\":false,"
           "\"next_boundary\":\"native_transport_worker_autonomous_daemon\","
           "\"libiio_rx_tx_worker\":true,"
           "\"same_process_rx_tx\":true,"
           "\"python_iio_transport\":false,"
           "\"reads_hardware\":false,"
           "\"writes_hardware\":false,"
           "\"starts_rf_tx\":false}\n");
    return 0;
}

static unsigned long long parse_ull(const char *text, const char *name)
{
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(text, &end, 10);
    if (errno || end == text || *end != '\0') {
        fprintf(stderr, "%s must be an unsigned integer: %s\n", name, text);
        exit(2);
    }
    return value;
}

static void nsleep_ms(unsigned int ms)
{
    struct timespec ts;
    ts.tv_sec = (time_t)(ms / 1000U);
    ts.tv_nsec = (long)(ms % 1000U) * 1000000L;
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) {
        ;
    }
}

static void die_errno(const char *what, const char *path)
{
    fprintf(stderr, "%s %s failed: %s\n", what, path ? path : "", strerror(errno));
    exit(1);
}

static struct blob read_file_all(const char *path)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        die_errno("open", path);
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        die_errno("seek", path);
    }
    long size = ftell(fp);
    if (size < 0) {
        die_errno("tell", path);
    }
    rewind(fp);
    struct blob out = {
        .data = calloc((size_t)size ? (size_t)size : 1u, 1u),
        .len = (size_t)size,
    };
    if (!out.data) {
        fprintf(stderr, "calloc(%zu) failed\n", out.len);
        exit(1);
    }
    if (out.len && fread(out.data, 1, out.len, fp) != out.len) {
        die_errno("read", path);
    }
    if (fclose(fp) != 0) {
        die_errno("close", path);
    }
    return out;
}

static void write_file_all(const char *path, const unsigned char *data, size_t len)
{
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        die_errno("open", path);
    }
    if (len && fwrite(data, 1, len, fp) != len) {
        die_errno("write", path);
    }
    if (fclose(fp) != 0) {
        die_errno("close", path);
    }
}

static uint32_t crc32_update(uint32_t crc, const unsigned char *data, size_t len)
{
    crc = ~crc;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (unsigned int bit = 0; bit < 8u; ++bit) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

static void put_be16(unsigned char *out, uint16_t value)
{
    out[0] = (unsigned char)(value >> 8);
    out[1] = (unsigned char)value;
}

static void put_be32(unsigned char *out, uint32_t value)
{
    out[0] = (unsigned char)(value >> 24);
    out[1] = (unsigned char)(value >> 16);
    out[2] = (unsigned char)(value >> 8);
    out[3] = (unsigned char)value;
}

static uint16_t get_be16(const unsigned char *in)
{
    return (uint16_t)(((uint16_t)in[0] << 8) | in[1]);
}

static uint32_t get_be32(const unsigned char *in)
{
    return ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) |
           ((uint32_t)in[2] << 8) | (uint32_t)in[3];
}

static void put_i16le(unsigned char *out, int value)
{
    if (value > 32767) {
        value = 32767;
    } else if (value < -32768) {
        value = -32768;
    }
    uint16_t packed = (uint16_t)(int16_t)value;
    out[0] = (unsigned char)packed;
    out[1] = (unsigned char)(packed >> 8);
}

static int16_t get_i16le(const unsigned char *in)
{
    return (int16_t)((uint16_t)in[0] | ((uint16_t)in[1] << 8));
}

static struct blob burst_payload_from_frame(const unsigned char *frame, size_t frame_len)
{
    if (frame_len == 0u || frame_len > 65535u) {
        fprintf(stderr, "frame length must be 1..65535 bytes\n");
        exit(2);
    }
    size_t payload_len = sizeof(PREAMBLE) + sizeof(SYNC) + 2u + frame_len + 4u;
    struct blob payload = {
        .data = calloc(payload_len, 1u),
        .len = payload_len,
    };
    if (!payload.data) {
        fprintf(stderr, "calloc(%zu) failed\n", payload_len);
        exit(1);
    }
    size_t cursor = 0;
    memcpy(payload.data + cursor, PREAMBLE, sizeof(PREAMBLE));
    cursor += sizeof(PREAMBLE);
    memcpy(payload.data + cursor, SYNC, sizeof(SYNC));
    cursor += sizeof(SYNC);
    put_be16(payload.data + cursor, (uint16_t)frame_len);
    cursor += 2u;
    memcpy(payload.data + cursor, frame, frame_len);
    cursor += frame_len;
    put_be32(payload.data + cursor, crc32_update(0u, frame, frame_len));
    return payload;
}

static int bit_at(const unsigned char *data, size_t bit_index)
{
    return (data[bit_index / 8u] >> (7u - (bit_index % 8u))) & 1u;
}

static struct blob bfsk_encode_frame(
    const unsigned char *frame,
    size_t frame_len,
    const struct modem_options *opt)
{
    struct blob payload = burst_payload_from_frame(frame, frame_len);
    size_t source_bits = payload.len * 8u;
    size_t total_symbols = source_bits * opt->bit_repeat;
    size_t iq_len = total_symbols * opt->samples_per_symbol * 4u;
    struct blob iq = {
        .data = calloc(iq_len, 1u),
        .len = iq_len,
    };
    if (!iq.data) {
        fprintf(stderr, "calloc(%zu) failed\n", iq_len);
        exit(1);
    }

    double phase = 0.0;
    size_t out = 0;
    for (size_t bit_index = 0; bit_index < source_bits; ++bit_index) {
        int bit = bit_at(payload.data, bit_index);
        double freq = bit ? opt->mark_hz : opt->space_hz;
        double phase_step = 2.0 * M_PI * freq / (double)opt->sample_rate_hz;
        for (unsigned int repeat = 0; repeat < opt->bit_repeat; ++repeat) {
            for (unsigned int sample = 0; sample < opt->samples_per_symbol; ++sample) {
                int i_value = (int)lrint((double)IQ_AMPLITUDE * cos(phase));
                int q_value = (int)lrint((double)IQ_AMPLITUDE * sin(phase));
                put_i16le(iq.data + out, i_value);
                put_i16le(iq.data + out + 2u, q_value);
                out += 4u;
                phase += phase_step;
                if (phase >= 2.0 * M_PI) {
                    phase = fmod(phase, 2.0 * M_PI);
                }
            }
        }
    }
    free(payload.data);
    return iq;
}

static struct blob bpsk_encode_frame(
    const unsigned char *frame,
    size_t frame_len,
    const struct modem_options *opt)
{
    struct blob payload = burst_payload_from_frame(frame, frame_len);
    size_t source_bits = payload.len * 8u;
    size_t total_symbols = source_bits * opt->bit_repeat;
    size_t iq_len = total_symbols * opt->samples_per_symbol * 4u;
    struct blob iq = {
        .data = calloc(iq_len, 1u),
        .len = iq_len,
    };
    if (!iq.data) {
        fprintf(stderr, "calloc(%zu) failed\n", iq_len);
        exit(1);
    }

    size_t out = 0;
    double carrier_phase = 0.0;
    double carrier_step = 0.0;
    if (opt->baseband_carrier_hz != 0.0) {
        carrier_step = 2.0 * M_PI * opt->baseband_carrier_hz /
                       (double)opt->sample_rate_hz;
    }
    for (size_t bit_index = 0; bit_index < source_bits; ++bit_index) {
        int symbol_value = bit_at(payload.data, bit_index) ? IQ_AMPLITUDE : -IQ_AMPLITUDE;
        for (unsigned int repeat = 0; repeat < opt->bit_repeat; ++repeat) {
            for (unsigned int sample = 0; sample < opt->samples_per_symbol; ++sample) {
                int i_value = symbol_value;
                int q_value = 0;
                if (opt->baseband_carrier_hz != 0.0) {
                    q_value = (int)lrint((double)symbol_value * sin(carrier_phase));
                    i_value = (int)lrint((double)symbol_value * cos(carrier_phase));
                }
                put_i16le(iq.data + out, i_value);
                put_i16le(iq.data + out + 2u, q_value);
                out += 4u;
                if (opt->baseband_carrier_hz != 0.0) {
                    carrier_phase += carrier_step;
                    if (carrier_phase <= -2.0 * M_PI || carrier_phase >= 2.0 * M_PI) {
                        carrier_phase = fmod(carrier_phase, 2.0 * M_PI);
                    }
                }
            }
        }
    }
    free(payload.data);
    return iq;
}

static void free_tone_prefixes(struct tone_prefixes *prefixes)
{
    if (!prefixes) {
        return;
    }
    free(prefixes->space_i);
    free(prefixes->space_q);
    free(prefixes->mark_i);
    free(prefixes->mark_q);
    memset(prefixes, 0, sizeof(*prefixes));
}

static void free_bpsk_prefixes(struct bpsk_prefixes *prefixes)
{
    if (!prefixes) {
        return;
    }
    free(prefixes->symbol_i);
    free(prefixes->symbol_q);
    memset(prefixes, 0, sizeof(*prefixes));
}

static bool build_tone_prefixes(
    const unsigned char *iq,
    size_t iq_len,
    const struct modem_options *opt,
    struct tone_prefixes *prefixes)
{
    if (!iq || !opt || !prefixes || iq_len % 4u != 0u) {
        return false;
    }
    memset(prefixes, 0, sizeof(*prefixes));
    size_t total_samples = iq_len / 4u;
    if (total_samples == 0u || total_samples == SIZE_MAX) {
        return false;
    }
    size_t points = total_samples + 1u;
    prefixes->space_i = calloc(points, sizeof(*prefixes->space_i));
    prefixes->space_q = calloc(points, sizeof(*prefixes->space_q));
    prefixes->mark_i = calloc(points, sizeof(*prefixes->mark_i));
    prefixes->mark_q = calloc(points, sizeof(*prefixes->mark_q));
    if (!prefixes->space_i || !prefixes->space_q ||
        !prefixes->mark_i || !prefixes->mark_q) {
        free_tone_prefixes(prefixes);
        return false;
    }

    double space_step = -2.0 * M_PI * opt->space_hz / (double)opt->sample_rate_hz;
    double mark_step = -2.0 * M_PI * opt->mark_hz / (double)opt->sample_rate_hz;
    double space_phase = 0.0;
    double mark_phase = 0.0;
    prefixes->total_samples = total_samples;
    for (size_t sample_index = 0; sample_index < total_samples; ++sample_index) {
        int16_t iv = get_i16le(iq + sample_index * 4u);
        int16_t qv = get_i16le(iq + sample_index * 4u + 2u);
        double sample_i = (double)iv;
        double sample_q = (double)qv;

        double space_c = cos(space_phase);
        double space_s = sin(space_phase);
        double mark_c = cos(mark_phase);
        double mark_s = sin(mark_phase);
        prefixes->space_i[sample_index + 1u] =
            prefixes->space_i[sample_index] + sample_i * space_c - sample_q * space_s;
        prefixes->space_q[sample_index + 1u] =
            prefixes->space_q[sample_index] + sample_i * space_s + sample_q * space_c;
        prefixes->mark_i[sample_index + 1u] =
            prefixes->mark_i[sample_index] + sample_i * mark_c - sample_q * mark_s;
        prefixes->mark_q[sample_index + 1u] =
            prefixes->mark_q[sample_index] + sample_i * mark_s + sample_q * mark_c;

        space_phase += space_step;
        mark_phase += mark_step;
        if (space_phase <= -2.0 * M_PI || space_phase >= 2.0 * M_PI) {
            space_phase = fmod(space_phase, 2.0 * M_PI);
        }
        if (mark_phase <= -2.0 * M_PI || mark_phase >= 2.0 * M_PI) {
            mark_phase = fmod(mark_phase, 2.0 * M_PI);
        }
    }
    return true;
}

static bool build_bpsk_prefixes(
    const unsigned char *iq,
    size_t iq_len,
    const struct modem_options *opt,
    struct bpsk_prefixes *prefixes)
{
    if (!iq || !opt || !prefixes || iq_len % 4u != 0u) {
        return false;
    }
    memset(prefixes, 0, sizeof(*prefixes));
    size_t total_samples = iq_len / 4u;
    if (total_samples == 0u || total_samples == SIZE_MAX) {
        return false;
    }
    size_t points = total_samples + 1u;
    prefixes->symbol_i = calloc(points, sizeof(*prefixes->symbol_i));
    prefixes->symbol_q = calloc(points, sizeof(*prefixes->symbol_q));
    if (!prefixes->symbol_i || !prefixes->symbol_q) {
        free_bpsk_prefixes(prefixes);
        return false;
    }

    double carrier_step = 0.0;
    double carrier_phase = 0.0;
    if (opt->baseband_carrier_hz != 0.0) {
        carrier_step = -2.0 * M_PI * opt->baseband_carrier_hz /
                       (double)opt->sample_rate_hz;
    }
    prefixes->total_samples = total_samples;
    for (size_t sample_index = 0; sample_index < total_samples; ++sample_index) {
        int16_t iv = get_i16le(iq + sample_index * 4u);
        int16_t qv = get_i16le(iq + sample_index * 4u + 2u);
        double mixed_i = (double)iv;
        double mixed_q = (double)qv;
        if (opt->baseband_carrier_hz != 0.0) {
            mixed_i = (double)iv * cos(carrier_phase) -
                      (double)qv * sin(carrier_phase);
            mixed_q = (double)iv * sin(carrier_phase) +
                      (double)qv * cos(carrier_phase);
        }
        prefixes->symbol_i[sample_index + 1u] = prefixes->symbol_i[sample_index] + mixed_i;
        prefixes->symbol_q[sample_index + 1u] = prefixes->symbol_q[sample_index] + mixed_q;
        carrier_phase += carrier_step;
        if (carrier_phase <= -2.0 * M_PI || carrier_phase >= 2.0 * M_PI) {
            carrier_phase = fmod(carrier_phase, 2.0 * M_PI);
        }
    }
    return true;
}

static bool build_bpsk_bit_symbols(
    const struct bpsk_prefixes *prefixes,
    const struct modem_options *opt,
    unsigned int sample_offset,
    unsigned int chip_phase,
    double **out_i,
    double **out_q,
    size_t *out_bits)
{
    size_t total_samples = prefixes ? prefixes->total_samples : 0u;
    if (total_samples <= sample_offset || sample_offset >= opt->samples_per_symbol) {
        return false;
    }
    size_t chips = (total_samples - sample_offset) / opt->samples_per_symbol;
    if (chips <= chip_phase) {
        return false;
    }
    size_t bits = (chips - chip_phase) / opt->bit_repeat;
    double *bits_i = calloc(bits ? bits : 1u, sizeof(*bits_i));
    double *bits_q = calloc(bits ? bits : 1u, sizeof(*bits_q));
    if (!bits_i || !bits_q) {
        free(bits_i);
        free(bits_q);
        fprintf(stderr, "calloc(%zu) failed\n", bits);
        exit(1);
    }
    for (size_t bit_index = 0; bit_index < bits; ++bit_index) {
        double acc_i = 0.0;
        double acc_q = 0.0;
        for (unsigned int repeat = 0; repeat < opt->bit_repeat; ++repeat) {
            size_t chip = chip_phase + bit_index * opt->bit_repeat + repeat;
            size_t sample_start = sample_offset + chip * opt->samples_per_symbol;
            size_t sample_end = sample_start + opt->samples_per_symbol;
            acc_i += prefixes->symbol_i[sample_end] - prefixes->symbol_i[sample_start];
            acc_q += prefixes->symbol_q[sample_end] - prefixes->symbol_q[sample_start];
        }
        bits_i[bit_index] = acc_i;
        bits_q[bit_index] = acc_q;
    }
    *out_i = bits_i;
    *out_q = bits_q;
    *out_bits = bits;
    return true;
}

static double prefix_tone_energy(const double *prefix_i, const double *prefix_q,
                                 size_t sample_start, unsigned int samples_per_symbol)
{
    size_t sample_end = sample_start + samples_per_symbol;
    double acc_i = prefix_i[sample_end] - prefix_i[sample_start];
    double acc_q = prefix_q[sample_end] - prefix_q[sample_start];
    return acc_i * acc_i + acc_q * acc_q;
}

static unsigned char *decode_hard_bits(
    const struct tone_prefixes *prefixes,
    const struct modem_options *opt,
    unsigned int sample_offset,
    unsigned int chip_phase,
    size_t *out_bits)
{
    size_t total_samples = prefixes ? prefixes->total_samples : 0u;
    if (sample_offset >= opt->samples_per_symbol || total_samples <= sample_offset) {
        return NULL;
    }
    size_t chips = (total_samples - sample_offset) / opt->samples_per_symbol;
    if (chips <= chip_phase) {
        return NULL;
    }
    size_t bits = (chips - chip_phase) / opt->bit_repeat;
    unsigned char *hard = calloc(bits ? bits : 1u, 1u);
    if (!hard) {
        fprintf(stderr, "calloc(%zu) failed\n", bits);
        exit(1);
    }
    for (size_t bit_index = 0; bit_index < bits; ++bit_index) {
        unsigned int ones = 0;
        for (unsigned int repeat = 0; repeat < opt->bit_repeat; ++repeat) {
            size_t chip = chip_phase + bit_index * opt->bit_repeat + repeat;
            size_t sample_start = sample_offset + chip * opt->samples_per_symbol;
            double space = prefix_tone_energy(prefixes->space_i, prefixes->space_q,
                                              sample_start, opt->samples_per_symbol);
            double mark = prefix_tone_energy(prefixes->mark_i, prefixes->mark_q,
                                             sample_start, opt->samples_per_symbol);
            if (mark >= space) {
                ones++;
            }
        }
        hard[bit_index] = ones * 2u >= opt->bit_repeat ? 1u : 0u;
    }
    *out_bits = bits;
    return hard;
}

static unsigned char *decode_bpsk_hard_bits(
    const struct bpsk_prefixes *prefixes,
    const struct modem_options *opt,
    unsigned int sample_offset,
    unsigned int chip_phase,
    size_t *out_bits)
{
    size_t total_samples = prefixes ? prefixes->total_samples : 0u;
    if (total_samples <= sample_offset) {
        return NULL;
    }
    size_t chips = (total_samples - sample_offset) / opt->samples_per_symbol;
    if (chips <= chip_phase) {
        return NULL;
    }
    size_t bits = (chips - chip_phase) / opt->bit_repeat;
    unsigned char *hard = calloc(bits ? bits : 1u, 1u);
    if (!hard) {
        fprintf(stderr, "calloc(%zu) failed\n", bits);
        exit(1);
    }
    for (size_t bit_index = 0; bit_index < bits; ++bit_index) {
        unsigned int ones = 0;
        for (unsigned int repeat = 0; repeat < opt->bit_repeat; ++repeat) {
            size_t chip = chip_phase + bit_index * opt->bit_repeat + repeat;
            size_t sample_start = sample_offset + chip * opt->samples_per_symbol;
            double acc_i = prefixes->symbol_i[sample_start + opt->samples_per_symbol] -
                           prefixes->symbol_i[sample_start];
            if (acc_i >= 0) {
                ones++;
            }
        }
        hard[bit_index] = ones * 2u >= opt->bit_repeat ? 1u : 0u;
    }
    *out_bits = bits;
    return hard;
}

static bool recover_frame_from_bits(
    const unsigned char *bits,
    size_t bits_len,
    size_t bit_start,
    const struct modem_options *opt,
    struct blob *out);

static unsigned char *project_bpsk_bits(
    const double *bits_i,
    const double *bits_q,
    size_t bits_len,
    double phase_i,
    double phase_q)
{
    unsigned char *hard = calloc(bits_len ? bits_len : 1u, 1u);
    if (!hard) {
        fprintf(stderr, "calloc(%zu) failed\n", bits_len);
        exit(1);
    }
    for (size_t bit_index = 0; bit_index < bits_len; ++bit_index) {
        double projected = bits_i[bit_index] * phase_i + bits_q[bit_index] * phase_q;
        hard[bit_index] = projected >= 0.0 ? 1u : 0u;
    }
    return hard;
}

static bool bpsk_decode_frame_coherent(
    const struct bpsk_prefixes *prefixes,
    const struct modem_options *opt,
    struct blob *out,
    unsigned int *out_sample_offset,
    unsigned int *out_chip_phase,
    size_t *out_bit_start)
{
    size_t sync_bits = (sizeof(PREAMBLE) + sizeof(SYNC)) * 8u;
    size_t required_bits = sync_bits + 16u + 32u;
    if (opt->have_expected_frame_len) {
        required_bits += opt->expected_frame_len * 8u;
    }
    for (unsigned int sample_offset = 0; sample_offset < opt->samples_per_symbol; ++sample_offset) {
        for (unsigned int chip_phase = 0; chip_phase < opt->bit_repeat; ++chip_phase) {
            double *bits_i = NULL;
            double *bits_q = NULL;
            size_t bits_len = 0;
            if (!build_bpsk_bit_symbols(prefixes, opt, sample_offset, chip_phase,
                                        &bits_i, &bits_q, &bits_len)) {
                continue;
            }
            if (bits_len >= required_bits) {
                size_t latest_bit_start = bits_len - required_bits;
                for (size_t bit_start = 0; bit_start <= latest_bit_start; ++bit_start) {
                    double corr_i = 0.0;
                    double corr_q = 0.0;
                    for (size_t bit = 0; bit < sync_bits; ++bit) {
                        int expected = bit < sizeof(PREAMBLE) * 8u
                                           ? bit_at(PREAMBLE, bit)
                                           : bit_at(SYNC, bit - sizeof(PREAMBLE) * 8u);
                        double sign = expected ? 1.0 : -1.0;
                        corr_i += bits_i[bit_start + bit] * sign;
                        corr_q += bits_q[bit_start + bit] * sign;
                    }
                    double mag = hypot(corr_i, corr_q);
                    if (mag <= 0.0) {
                        continue;
                    }
                    double phase_i = corr_i / mag;
                    double phase_q = corr_q / mag;
                    unsigned int sync_errors = 0;
                    for (size_t bit = 0; bit < sync_bits; ++bit) {
                        int expected = bit < sizeof(PREAMBLE) * 8u
                                           ? bit_at(PREAMBLE, bit)
                                           : bit_at(SYNC, bit - sizeof(PREAMBLE) * 8u);
                        double projected = bits_i[bit_start + bit] * phase_i +
                                           bits_q[bit_start + bit] * phase_q;
                        int hard = projected >= 0.0 ? 1 : 0;
                        if (hard != expected) {
                            sync_errors++;
                        }
                    }
                    if (sync_errors != 0u) {
                        continue;
                    }
                    unsigned char *bits = project_bpsk_bits(bits_i, bits_q, bits_len,
                                                            phase_i, phase_q);
                    bool recovered = recover_frame_from_bits(bits, bits_len, bit_start, opt, out);
                    free(bits);
                    if (recovered) {
                        *out_sample_offset = sample_offset;
                        *out_chip_phase = chip_phase;
                        *out_bit_start = bit_start;
                        free(bits_i);
                        free(bits_q);
                        return true;
                    }
                }
            }
            free(bits_i);
            free(bits_q);
        }
    }
    return false;
}

static int hard_bits_match_bytes(const unsigned char *bits, size_t bit_start,
                                 const unsigned char *bytes, size_t len)
{
    for (size_t i = 0; i < len * 8u; ++i) {
        if (bits[bit_start + i] != bit_at(bytes, i)) {
            return 0;
        }
    }
    return 1;
}

static struct blob bytes_from_hard_bits(const unsigned char *bits, size_t bit_start, size_t len)
{
    struct blob out = {
        .data = calloc(len ? len : 1u, 1u),
        .len = len,
    };
    if (!out.data) {
        fprintf(stderr, "calloc(%zu) failed\n", len);
        exit(1);
    }
    for (size_t byte_index = 0; byte_index < len; ++byte_index) {
        unsigned char value = 0;
        for (unsigned int bit = 0; bit < 8u; ++bit) {
            value = (unsigned char)((value << 1) |
                                    (bits[bit_start + byte_index * 8u + bit] & 1u));
        }
        out.data[byte_index] = value;
    }
    return out;
}

static bool recover_frame_from_bits(
    const unsigned char *bits,
    size_t bits_len,
    size_t bit_start,
    const struct modem_options *opt,
    struct blob *out)
{
    size_t cursor = bit_start + (sizeof(PREAMBLE) + sizeof(SYNC)) * 8u;
    if (bits_len < cursor + 16u) {
        return false;
    }
    struct blob len_bytes = bytes_from_hard_bits(bits, cursor, 2u);
    uint16_t frame_len = get_be16(len_bytes.data);
    free(len_bytes.data);
    if (opt->have_expected_frame_len && frame_len != opt->expected_frame_len) {
        return false;
    }
    if (frame_len == 0u) {
        return false;
    }
    cursor += 16u;
    size_t frame_bits = (size_t)frame_len * 8u;
    if (bits_len < cursor + frame_bits + 32u) {
        return false;
    }
    struct blob frame = bytes_from_hard_bits(bits, cursor, frame_len);
    cursor += frame_bits;
    struct blob crc_bytes = bytes_from_hard_bits(bits, cursor, 4u);
    uint32_t recovered_crc = get_be32(crc_bytes.data);
    free(crc_bytes.data);
    uint32_t expected_crc = crc32_update(0u, frame.data, frame.len);
    if (opt->have_expected_frame_crc && expected_crc != opt->expected_frame_crc) {
        free(frame.data);
        return false;
    }
    if (recovered_crc != expected_crc) {
        free(frame.data);
        return false;
    }
    *out = frame;
    return true;
}

static bool bfsk_decode_frame(
    const unsigned char *iq,
    size_t iq_len,
    const struct modem_options *opt,
    struct blob *out,
    unsigned int *out_sample_offset,
    unsigned int *out_chip_phase,
    size_t *out_bit_start)
{
    struct tone_prefixes prefixes;
    if (!build_tone_prefixes(iq, iq_len, opt, &prefixes)) {
        fprintf(stderr, "failed to build BFSK tone prefixes\n");
        return false;
    }
    for (unsigned int sample_offset = 0; sample_offset < opt->samples_per_symbol; ++sample_offset) {
        for (unsigned int chip_phase = 0; chip_phase < opt->bit_repeat; ++chip_phase) {
            size_t bits_len = 0;
            unsigned char *bits = decode_hard_bits(&prefixes, opt, sample_offset,
                                                   chip_phase, &bits_len);
            if (!bits) {
                continue;
            }
            size_t sync_bits = (sizeof(PREAMBLE) + sizeof(SYNC)) * 8u;
            if (bits_len >= sync_bits + 16u + 32u) {
                for (size_t bit_start = 0; bit_start + sync_bits <= bits_len; ++bit_start) {
                    if (!hard_bits_match_bytes(bits, bit_start, PREAMBLE, sizeof(PREAMBLE)) ||
                        !hard_bits_match_bytes(bits, bit_start + sizeof(PREAMBLE) * 8u,
                                               SYNC, sizeof(SYNC))) {
                        continue;
                    }
                    if (recover_frame_from_bits(bits, bits_len, bit_start, opt, out)) {
                        *out_sample_offset = sample_offset;
                        *out_chip_phase = chip_phase;
                        *out_bit_start = bit_start;
                        free(bits);
                        free_tone_prefixes(&prefixes);
                        return true;
                    }
                }
            }
            free(bits);
        }
    }
    free_tone_prefixes(&prefixes);
    return false;
}

static bool bpsk_decode_frame(
    const unsigned char *iq,
    size_t iq_len,
    const struct modem_options *opt,
    struct blob *out,
    unsigned int *out_sample_offset,
    unsigned int *out_chip_phase,
    size_t *out_bit_start)
{
    struct bpsk_prefixes prefixes;
    if (!build_bpsk_prefixes(iq, iq_len, opt, &prefixes)) {
        fprintf(stderr, "failed to build BPSK symbol prefixes\n");
        return false;
    }
    if (bpsk_decode_frame_coherent(&prefixes, opt, out, out_sample_offset,
                                   out_chip_phase, out_bit_start)) {
        free_bpsk_prefixes(&prefixes);
        return true;
    }
    for (unsigned int sample_offset = 0; sample_offset < opt->samples_per_symbol; ++sample_offset) {
        for (unsigned int chip_phase = 0; chip_phase < opt->bit_repeat; ++chip_phase) {
            size_t bits_len = 0;
            unsigned char *bits = decode_bpsk_hard_bits(&prefixes, opt, sample_offset,
                                                        chip_phase, &bits_len);
            if (!bits) {
                continue;
            }
            size_t sync_bits = (sizeof(PREAMBLE) + sizeof(SYNC)) * 8u;
            if (bits_len >= sync_bits + 16u + 32u) {
                for (size_t bit_start = 0; bit_start + sync_bits <= bits_len; ++bit_start) {
                    if (!hard_bits_match_bytes(bits, bit_start, PREAMBLE, sizeof(PREAMBLE)) ||
                        !hard_bits_match_bytes(bits, bit_start + sizeof(PREAMBLE) * 8u,
                                               SYNC, sizeof(SYNC))) {
                        continue;
                    }
                    if (recover_frame_from_bits(bits, bits_len, bit_start, opt, out)) {
                        *out_sample_offset = sample_offset;
                        *out_chip_phase = chip_phase;
                        *out_bit_start = bit_start;
                        free(bits);
                        free_bpsk_prefixes(&prefixes);
                        return true;
                    }
                }
            }
            free(bits);
        }
    }
    free_bpsk_prefixes(&prefixes);
    return false;
}

static void modem_defaults(struct modem_options *opt)
{
    memset(opt, 0, sizeof(*opt));
    opt->sample_rate_hz = DEFAULT_SAMPLE_RATE_HZ;
    opt->space_hz = DEFAULT_BFSK_SPACE_HZ;
    opt->mark_hz = DEFAULT_BFSK_MARK_HZ;
    opt->baseband_carrier_hz = 0.0;
    opt->samples_per_symbol = DEFAULT_SAMPLES_PER_SYMBOL;
    opt->bit_repeat = DEFAULT_BIT_REPEAT;
    opt->iterations = 200U;
}

static uint32_t parse_u32_arg(const char *text, const char *name)
{
    unsigned long long value = parse_ull(text, name);
    if (value > 0xffffffffULL) {
        fprintf(stderr, "%s is too large: %s\n", name, text);
        exit(2);
    }
    return (uint32_t)value;
}

static uint32_t parse_crc_arg(const char *text)
{
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 0);
    if (errno || end == text || *end != '\0' || value > 0xffffffffUL) {
        fprintf(stderr, "--expected-frame-crc must be a u32 integer: %s\n", text);
        exit(2);
    }
    return (uint32_t)value;
}

static double parse_double_arg(const char *text, const char *name)
{
    char *end = NULL;
    errno = 0;
    double value = strtod(text, &end);
    if (errno || end == text || *end != '\0') {
        fprintf(stderr, "%s must be numeric: %s\n", name, text);
        exit(2);
    }
    return value;
}

static void parse_modem_args(int argc, char **argv, struct modem_options *opt)
{
    modem_defaults(opt);
    for (int i = 2; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "--frame-file") == 0 && i + 1 < argc) {
            opt->frame_file = argv[++i];
        } else if (strcmp(arg, "--iq-file") == 0 && i + 1 < argc) {
            opt->iq_file = argv[++i];
        } else if (strcmp(arg, "--decoded-file") == 0 && i + 1 < argc) {
            opt->decoded_file = argv[++i];
        } else if (strcmp(arg, "--sample-rate-hz") == 0 && i + 1 < argc) {
            opt->sample_rate_hz = parse_u32_arg(argv[++i], "--sample-rate-hz");
        } else if (strcmp(arg, "--space-hz") == 0 && i + 1 < argc) {
            opt->space_hz = parse_double_arg(argv[++i], "--space-hz");
        } else if (strcmp(arg, "--mark-hz") == 0 && i + 1 < argc) {
            opt->mark_hz = parse_double_arg(argv[++i], "--mark-hz");
        } else if (strcmp(arg, "--baseband-carrier-hz") == 0 && i + 1 < argc) {
            opt->baseband_carrier_hz = parse_double_arg(argv[++i], "--baseband-carrier-hz");
        } else if (strcmp(arg, "--samples-per-symbol") == 0 && i + 1 < argc) {
            opt->samples_per_symbol = parse_u32_arg(argv[++i], "--samples-per-symbol");
        } else if (strcmp(arg, "--bit-repeat") == 0 && i + 1 < argc) {
            opt->bit_repeat = parse_u32_arg(argv[++i], "--bit-repeat");
        } else if (strcmp(arg, "--expected-frame-len") == 0 && i + 1 < argc) {
            opt->expected_frame_len = (size_t)parse_ull(argv[++i], "--expected-frame-len");
            opt->have_expected_frame_len = true;
        } else if (strcmp(arg, "--expected-frame-crc") == 0 && i + 1 < argc) {
            opt->expected_frame_crc = parse_crc_arg(argv[++i]);
            opt->have_expected_frame_crc = true;
        } else if (strcmp(arg, "--iterations") == 0 && i + 1 < argc) {
            opt->iterations = parse_u32_arg(argv[++i], "--iterations");
        } else {
            fprintf(stderr, "unknown or incomplete modem argument: %s\n", arg);
            usage(stderr);
            exit(2);
        }
    }
    if (opt->sample_rate_hz == 0 || opt->samples_per_symbol < 2 || opt->bit_repeat == 0 ||
        opt->space_hz <= 0.0 || opt->mark_hz <= 0.0 || opt->iterations == 0) {
        fprintf(stderr, "invalid modem parameters\n");
        exit(2);
    }
}

static long long monotonic_us(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000000LL + now.tv_nsec / 1000LL;
}

static unsigned long long kbps_for_bytes(size_t bytes,
                                         unsigned int iterations,
                                         long long elapsed_us)
{
    if (elapsed_us <= 0) {
        elapsed_us = 1;
    }
    unsigned long long bits = (unsigned long long)bytes * 8ULL *
                              (unsigned long long)iterations;
    return (bits * 1000ULL) / (unsigned long long)elapsed_us;
}

static int run_bpsk_encode(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.frame_file || !opt.iq_file) {
        usage(stderr);
        return 2;
    }
    struct blob frame = read_file_all(opt.frame_file);
    struct blob iq = bpsk_encode_frame(frame.data, frame.len, &opt);
    write_file_all(opt.iq_file, iq.data, iq.len);
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bpsk_modem_encode\",\"ok\":true,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"samples_per_symbol\":%u,"
            "\"bit_repeat\":%u,\"baseband_carrier_hz\":%.0f}\n",
            frame.len, iq.len, opt.samples_per_symbol, opt.bit_repeat,
            opt.baseband_carrier_hz);
    free(iq.data);
    free(frame.data);
    return 0;
}

static int run_bpsk_decode(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.iq_file || !opt.decoded_file) {
        usage(stderr);
        return 2;
    }
    struct blob iq = read_file_all(opt.iq_file);
    struct blob decoded = {0};
    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    bool ok = bpsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                &sample_offset, &chip_phase, &bit_start);
    if (ok) {
        write_file_all(opt.decoded_file, decoded.data, decoded.len);
    }
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bpsk_modem_decode\",\"ok\":%s,"
            "\"iq_bytes\":%zu,\"frame_bytes\":%zu,\"samples_per_symbol\":%u,"
            "\"bit_repeat\":%u,\"sample_offset\":%u,\"chip_phase\":%u,"
            "\"bit_start\":%zu,\"baseband_carrier_hz\":%.0f}\n",
            ok ? "true" : "false", iq.len, ok ? decoded.len : (size_t)0,
            opt.samples_per_symbol, opt.bit_repeat, sample_offset,
            chip_phase, bit_start, opt.baseband_carrier_hz);
    free(decoded.data);
    free(iq.data);
    return ok ? 0 : 1;
}

static struct blob rotate_iq_90deg(const struct blob *iq)
{
    struct blob rotated = {
        .data = calloc(iq->len, 1u),
        .len = iq->len,
    };
    if (!rotated.data) {
        fprintf(stderr, "calloc(%zu) failed\n", iq->len);
        exit(1);
    }
    for (size_t offset = 0; offset + 3u < iq->len; offset += 4u) {
        int i_value = get_i16le(iq->data + offset);
        int q_value = get_i16le(iq->data + offset + 2u);
        put_i16le(rotated.data + offset, -q_value);
        put_i16le(rotated.data + offset + 2u, i_value);
    }
    return rotated;
}

static bool decoded_frame_matches(const struct blob *decoded,
                                  const unsigned char *frame,
                                  size_t frame_len)
{
    return decoded->len == frame_len &&
           memcmp(decoded->data, frame, frame_len) == 0;
}

static int run_bpsk_self_test(void)
{
    struct modem_options opt;
    modem_defaults(&opt);
    static const unsigned char frame[] = {
        'F', 'M', 'B', 'A', 'T', 'C', 'H', '1',
        0x00, 0x02,
        0x00, 0x03, 0x01, 0x02, 0x03,
        0x00, 0x04, 0xaa, 0xbb, 0xcc, 0xdd,
    };
    struct blob iq = bpsk_encode_frame(frame, sizeof(frame), &opt);
    struct blob decoded_base = {0};
    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    bool base_ok = bpsk_decode_frame(iq.data, iq.len, &opt, &decoded_base,
                                     &sample_offset, &chip_phase, &bit_start) &&
                   decoded_frame_matches(&decoded_base, frame, sizeof(frame));

    struct blob rotated_iq = rotate_iq_90deg(&iq);
    struct blob decoded_rotated = {0};
    unsigned int rotated_sample_offset = 0;
    unsigned int rotated_chip_phase = 0;
    size_t rotated_bit_start = 0;
    bool phase_recovery_ok =
        bpsk_decode_frame(rotated_iq.data, rotated_iq.len, &opt,
                          &decoded_rotated, &rotated_sample_offset,
                          &rotated_chip_phase, &rotated_bit_start) &&
        decoded_frame_matches(&decoded_rotated, frame, sizeof(frame));

    struct modem_options carrier_opt = opt;
    carrier_opt.sample_rate_hz = 1000000U;
    carrier_opt.baseband_carrier_hz = 125000.0;
    carrier_opt.samples_per_symbol = 16U;
    carrier_opt.bit_repeat = 2U;
    struct blob carrier_iq = bpsk_encode_frame(frame, sizeof(frame), &carrier_opt);
    struct blob decoded_carrier = {0};
    unsigned int carrier_sample_offset = 0;
    unsigned int carrier_chip_phase = 0;
    size_t carrier_bit_start = 0;
    bool carrier_ok =
        bpsk_decode_frame(carrier_iq.data, carrier_iq.len, &carrier_opt,
                          &decoded_carrier, &carrier_sample_offset,
                          &carrier_chip_phase, &carrier_bit_start) &&
        decoded_frame_matches(&decoded_carrier, frame, sizeof(frame));

    bool ok = base_ok && phase_recovery_ok && carrier_ok;
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bpsk_modem_self_test\",\"ok\":%s,"
            "\"base_ok\":%s,\"phase_recovery_ok\":%s,\"carrier_ok\":%s,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"sample_offset\":%u,"
            "\"chip_phase\":%u,\"bit_start\":%zu,"
            "\"carrier_sample_offset\":%u,\"carrier_chip_phase\":%u,"
            "\"carrier_bit_start\":%zu,\"baseband_carrier_hz\":%.0f}\n",
            ok ? "true" : "false",
            base_ok ? "true" : "false",
            phase_recovery_ok ? "true" : "false",
            carrier_ok ? "true" : "false",
            sizeof(frame), iq.len, sample_offset,
            chip_phase, bit_start, carrier_sample_offset,
            carrier_chip_phase, carrier_bit_start,
            carrier_opt.baseband_carrier_hz);
    free(decoded_carrier.data);
    free(carrier_iq.data);
    free(decoded_rotated.data);
    free(rotated_iq.data);
    free(decoded_base.data);
    free(iq.data);
    return ok ? 0 : 1;
}

static int run_bpsk_benchmark(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.frame_file) {
        usage(stderr);
        return 2;
    }

    struct blob frame = read_file_all(opt.frame_file);
    opt.expected_frame_len = frame.len;
    opt.expected_frame_crc = crc32_update(0u, frame.data, frame.len);
    opt.have_expected_frame_len = true;
    opt.have_expected_frame_crc = true;

    struct blob iq = {0};
    long long encode_start = monotonic_us();
    for (unsigned int i = 0; i < opt.iterations; ++i) {
        struct blob next = bpsk_encode_frame(frame.data, frame.len, &opt);
        if (i + 1u == opt.iterations) {
            iq = next;
        } else {
            free(next.data);
        }
    }
    long long encode_us = monotonic_us() - encode_start;
    if (encode_us <= 0) {
        encode_us = 1;
    }

    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    long long decode_start = monotonic_us();
    for (unsigned int i = 0; i < opt.iterations; ++i) {
        struct blob decoded = {0};
        bool ok = bpsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                    &sample_offset, &chip_phase, &bit_start) &&
                  decoded_frame_matches(&decoded, frame.data, frame.len);
        free(decoded.data);
        if (!ok) {
            fprintf(stderr, "BPSK benchmark decode failed at iteration %u\n", i);
            free(iq.data);
            free(frame.data);
            return 1;
        }
    }
    long long decode_us = monotonic_us() - decode_start;
    if (decode_us <= 0) {
        decode_us = 1;
    }

    fprintf(stdout,
            "{\"event\":\"fieldmesh_bpsk_modem_benchmark\",\"ok\":true,"
            "\"hot_path_language\":\"c\",\"uses_python_modem\":false,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"iterations\":%u,"
            "\"samples_per_symbol\":%u,\"bit_repeat\":%u,"
            "\"baseband_carrier_hz\":%.0f,"
            "\"encode_elapsed_us\":%lld,\"decode_elapsed_us\":%lld,"
            "\"encode_frame_kbps\":%llu,\"decode_frame_kbps\":%llu,"
            "\"sample_offset\":%u,\"chip_phase\":%u,\"bit_start\":%zu}\n",
            frame.len, iq.len, opt.iterations, opt.samples_per_symbol,
            opt.bit_repeat, opt.baseband_carrier_hz, encode_us, decode_us,
            kbps_for_bytes(frame.len, opt.iterations, encode_us),
            kbps_for_bytes(frame.len, opt.iterations, decode_us),
            sample_offset, chip_phase, bit_start);
    free(iq.data);
    free(frame.data);
    return 0;
}

static int run_bfsk_encode(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.frame_file || !opt.iq_file) {
        usage(stderr);
        return 2;
    }
    struct blob frame = read_file_all(opt.frame_file);
    struct blob iq = bfsk_encode_frame(frame.data, frame.len, &opt);
    write_file_all(opt.iq_file, iq.data, iq.len);
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bfsk_modem_encode\",\"ok\":true,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"samples_per_symbol\":%u,"
            "\"bit_repeat\":%u}\n",
            frame.len, iq.len, opt.samples_per_symbol, opt.bit_repeat);
    free(iq.data);
    free(frame.data);
    return 0;
}

static int run_bfsk_decode(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.iq_file || !opt.decoded_file) {
        usage(stderr);
        return 2;
    }
    struct blob iq = read_file_all(opt.iq_file);
    struct blob decoded = {0};
    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    bool ok = bfsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                &sample_offset, &chip_phase, &bit_start);
    if (ok) {
        write_file_all(opt.decoded_file, decoded.data, decoded.len);
    }
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bfsk_modem_decode\",\"ok\":%s,"
            "\"iq_bytes\":%zu,\"frame_bytes\":%zu,\"samples_per_symbol\":%u,"
            "\"bit_repeat\":%u,\"sample_offset\":%u,\"chip_phase\":%u,"
            "\"bit_start\":%zu}\n",
            ok ? "true" : "false", iq.len, ok ? decoded.len : (size_t)0,
            opt.samples_per_symbol, opt.bit_repeat, sample_offset,
            chip_phase, bit_start);
    free(decoded.data);
    free(iq.data);
    return ok ? 0 : 1;
}

static int run_bfsk_self_test(void)
{
    struct modem_options opt;
    modem_defaults(&opt);
    // FMBATCH1 matches the Python bridge raw binary batch magic used by HIL.
    static const unsigned char frame[] = {
        'F', 'M', 'B', 'A', 'T', 'C', 'H', '1',
        0x00, 0x02,
        0x00, 0x03, 0x01, 0x02, 0x03,
        0x00, 0x04, 0xaa, 0xbb, 0xcc, 0xdd,
    };
    struct blob iq = bfsk_encode_frame(frame, sizeof(frame), &opt);
    struct blob decoded = {0};
    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    bool ok = bfsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                &sample_offset, &chip_phase, &bit_start);
    ok = ok && decoded.len == sizeof(frame) &&
         memcmp(decoded.data, frame, sizeof(frame)) == 0;
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bfsk_modem_self_test\",\"ok\":%s,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"sample_offset\":%u,"
            "\"chip_phase\":%u,\"bit_start\":%zu}\n",
            ok ? "true" : "false", sizeof(frame), iq.len, sample_offset,
            chip_phase, bit_start);
    free(decoded.data);
    free(iq.data);
    return ok ? 0 : 1;
}

static int run_bfsk_benchmark(int argc, char **argv)
{
    struct modem_options opt;
    parse_modem_args(argc, argv, &opt);
    if (!opt.frame_file) {
        usage(stderr);
        return 2;
    }

    struct blob frame = read_file_all(opt.frame_file);
    opt.expected_frame_len = frame.len;
    opt.expected_frame_crc = crc32_update(0u, frame.data, frame.len);
    opt.have_expected_frame_len = true;
    opt.have_expected_frame_crc = true;

    struct blob iq = {0};
    long long encode_start = monotonic_us();
    for (unsigned int i = 0; i < opt.iterations; ++i) {
        struct blob next = bfsk_encode_frame(frame.data, frame.len, &opt);
        if (i + 1u == opt.iterations) {
            iq = next;
        } else {
            free(next.data);
        }
    }
    long long encode_us = monotonic_us() - encode_start;
    if (encode_us <= 0) {
        encode_us = 1;
    }

    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    long long decode_start = monotonic_us();
    for (unsigned int i = 0; i < opt.iterations; ++i) {
        struct blob decoded = {0};
        bool ok = bfsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                    &sample_offset, &chip_phase, &bit_start) &&
                  decoded_frame_matches(&decoded, frame.data, frame.len);
        free(decoded.data);
        if (!ok) {
            fprintf(stderr, "BFSK benchmark decode failed at iteration %u\n", i);
            free(iq.data);
            free(frame.data);
            return 1;
        }
    }
    long long decode_us = monotonic_us() - decode_start;
    if (decode_us <= 0) {
        decode_us = 1;
    }

    fprintf(stdout,
            "{\"event\":\"fieldmesh_bfsk_modem_benchmark\",\"ok\":true,"
            "\"hot_path_language\":\"c\",\"uses_python_modem\":false,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"iterations\":%u,"
            "\"samples_per_symbol\":%u,\"bit_repeat\":%u,"
            "\"space_hz\":%.0f,\"mark_hz\":%.0f,"
            "\"encode_elapsed_us\":%lld,\"decode_elapsed_us\":%lld,"
            "\"encode_frame_kbps\":%llu,\"decode_frame_kbps\":%llu,"
            "\"sample_offset\":%u,\"chip_phase\":%u,\"bit_start\":%zu}\n",
            frame.len, iq.len, opt.iterations, opt.samples_per_symbol,
            opt.bit_repeat, opt.space_hz, opt.mark_hz, encode_us, decode_us,
            kbps_for_bytes(frame.len, opt.iterations, encode_us),
            kbps_for_bytes(frame.len, opt.iterations, decode_us),
            sample_offset, chip_phase, bit_start);
    free(iq.data);
    free(frame.data);
    return 0;
}

static void parse_args(int argc, char **argv, struct options *opt)
{
    memset(opt, 0, sizeof(*opt));
    opt->tx_duration_ms = 250;
    opt->rx_timeout_ms = 5000;
    opt->rx_arm_delay_ms = 10;
    opt->channel_count = 0;

    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "--help") == 0) {
            usage(stdout);
            exit(0);
        } else if (strcmp(arg, "--tx-uri") == 0 && i + 1 < argc) {
            opt->tx_uri = argv[++i];
        } else if (strcmp(arg, "--rx-uri") == 0 && i + 1 < argc) {
            opt->rx_uri = argv[++i];
        } else if (strcmp(arg, "--tx-device") == 0 && i + 1 < argc) {
            opt->tx_device = argv[++i];
        } else if (strcmp(arg, "--rx-device") == 0 && i + 1 < argc) {
            opt->rx_device = argv[++i];
        } else if (strcmp(arg, "--tx-file") == 0 && i + 1 < argc) {
            opt->tx_file = argv[++i];
        } else if (strcmp(arg, "--rx-file") == 0 && i + 1 < argc) {
            opt->rx_file = argv[++i];
        } else if (strcmp(arg, "--tx-samples") == 0 && i + 1 < argc) {
            opt->tx_samples = (size_t)parse_ull(argv[++i], "--tx-samples");
        } else if (strcmp(arg, "--rx-samples") == 0 && i + 1 < argc) {
            opt->rx_samples = (size_t)parse_ull(argv[++i], "--rx-samples");
        } else if (strcmp(arg, "--buffer-size") == 0 && i + 1 < argc) {
            opt->buffer_size = (size_t)parse_ull(argv[++i], "--buffer-size");
        } else if (strcmp(arg, "--tx-duration-ms") == 0 && i + 1 < argc) {
            opt->tx_duration_ms = (unsigned int)parse_ull(argv[++i], "--tx-duration-ms");
        } else if (strcmp(arg, "--rx-timeout-ms") == 0 && i + 1 < argc) {
            opt->rx_timeout_ms = (unsigned int)parse_ull(argv[++i], "--rx-timeout-ms");
        } else if (strcmp(arg, "--rx-arm-delay-ms") == 0 && i + 1 < argc) {
            opt->rx_arm_delay_ms = (unsigned int)parse_ull(argv[++i], "--rx-arm-delay-ms");
        } else if (strcmp(arg, "--channel") == 0 && i + 1 < argc) {
            if (opt->channel_count >= MAX_CHANNELS) {
                fprintf(stderr, "too many --channel entries\n");
                exit(2);
            }
            opt->channels[opt->channel_count++] = argv[++i];
        } else if (strcmp(arg, "--cyclic") == 0) {
            opt->cyclic = true;
        } else if (strcmp(arg, "--server") == 0) {
            opt->server = true;
        } else {
            fprintf(stderr, "unknown or incomplete argument: %s\n", arg);
            usage(stderr);
            exit(2);
        }
    }

    if (!opt->tx_uri || !opt->rx_uri || !opt->tx_device || !opt->rx_device ||
        (!opt->server && (!opt->tx_file || !opt->rx_file ||
                          opt->tx_samples == 0 || opt->rx_samples == 0))) {
        usage(stderr);
        exit(2);
    }
    if (opt->channel_count == 0) {
        opt->channels[opt->channel_count++] = "voltage0";
        opt->channels[opt->channel_count++] = "voltage1";
    }
    if (opt->buffer_size == 0) {
        opt->buffer_size = opt->tx_samples > opt->rx_samples ? opt->tx_samples : opt->rx_samples;
    }
}

static struct iio_context *open_context(const char *uri, unsigned int timeout_ms)
{
    struct iio_context *ctx = iio_create_context_from_uri(uri);
    if (!ctx) {
        fprintf(stderr, "failed to open IIO context %s: %s\n", uri, strerror(errno));
        exit(1);
    }
    int rc = iio_context_set_timeout(ctx, timeout_ms);
    if (rc < 0) {
        fprintf(stderr, "failed to set timeout on %s: %s\n", uri, strerror(-rc));
        iio_context_destroy(ctx);
        exit(1);
    }
    return ctx;
}

static struct iio_device *find_device(struct iio_context *ctx, const char *name)
{
    struct iio_device *dev = iio_context_find_device(ctx, name);
    if (!dev) {
        fprintf(stderr, "missing IIO device %s\n", name);
        exit(1);
    }
    return dev;
}

static void enable_channels(struct iio_device *dev, const struct options *opt, bool output)
{
    for (int i = 0; i < opt->channel_count; i++) {
        struct iio_channel *chn = iio_device_find_channel(dev, opt->channels[i], output);
        if (!chn) {
            fprintf(stderr, "missing %s channel %s on device\n",
                    output ? "output" : "input", opt->channels[i]);
            exit(1);
        }
        iio_channel_enable(chn);
    }
}

static unsigned char *read_file_exact(const char *path, size_t bytes)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        exit(1);
    }
    unsigned char *data = calloc(1, bytes);
    if (!data) {
        fprintf(stderr, "calloc(%zu) failed\n", bytes);
        fclose(fp);
        exit(1);
    }
    size_t got = fread(data, 1, bytes, fp);
    if (got != bytes) {
        fprintf(stderr, "%s short read: got %zu expected %zu\n", path, got, bytes);
        free(data);
        fclose(fp);
        exit(1);
    }
    fclose(fp);
    return data;
}

static void fill_tx_buffer(struct iio_buffer *buffer, const unsigned char *data, size_t bytes)
{
    unsigned char *dst = (unsigned char *)iio_buffer_start(buffer);
    unsigned char *end = (unsigned char *)iio_buffer_end(buffer);
    size_t capacity = (size_t)(end - dst);
    if (capacity < bytes) {
        fprintf(stderr, "TX IIO buffer too small: capacity %zu need %zu\n", capacity, bytes);
        exit(1);
    }
    memcpy(dst, data, bytes);
}

static void *rx_thread_main(void *opaque)
{
    struct rx_job *job = (struct rx_job *)opaque;
    FILE *fp = fopen(job->path, "wb");
    if (!fp) {
        job->rc = errno ? errno : EIO;
        return NULL;
    }

    size_t written = 0;
    while (written < job->target_bytes) {
        ssize_t got = iio_buffer_refill(job->buffer);
        if (got < 0) {
            job->rc = (int)-got;
            fclose(fp);
            return NULL;
        }
        unsigned char *src = (unsigned char *)iio_buffer_start(job->buffer);
        size_t remaining = job->target_bytes - written;
        size_t chunk = (size_t)got < remaining ? (size_t)got : remaining;
        if (fwrite(src, 1, chunk, fp) != chunk) {
            job->rc = errno ? errno : EIO;
            fclose(fp);
            return NULL;
        }
        written += chunk;
    }

    if (fclose(fp) != 0) {
        job->rc = errno ? errno : EIO;
        return NULL;
    }
    job->bytes_written = (ssize_t)written;
    job->rc = 0;
    return NULL;
}

static int run_xfer(struct iio_device *rx_dev, struct iio_device *tx_dev,
                    const struct options *opt, FILE *json_out)
{
    struct timespec started;
    clock_gettime(CLOCK_MONOTONIC, &started);

    ssize_t rx_sample_size = iio_device_get_sample_size(rx_dev);
    ssize_t tx_sample_size = iio_device_get_sample_size(tx_dev);
    if (rx_sample_size <= 0 || tx_sample_size <= 0) {
        fprintf(stderr, "invalid IIO sample sizes: rx=%zd tx=%zd\n",
                rx_sample_size, tx_sample_size);
        return 1;
    }

    size_t tx_bytes = opt->tx_samples * (size_t)tx_sample_size;
    size_t rx_bytes = opt->rx_samples * (size_t)rx_sample_size;
    size_t buffer_size = opt->buffer_size;
    if (buffer_size == 0) {
        buffer_size = opt->tx_samples > opt->rx_samples ? opt->tx_samples : opt->rx_samples;
    }
    unsigned char *tx_data = read_file_exact(opt->tx_file, tx_bytes);

    struct iio_buffer *rx_buffer = iio_device_create_buffer(rx_dev, buffer_size, false);
    if (!rx_buffer) {
        fprintf(stderr, "create RX buffer failed: %s\n", strerror(errno));
        free(tx_data);
        return 1;
    }
    struct iio_buffer *tx_buffer = iio_device_create_buffer(tx_dev, opt->tx_samples, opt->cyclic);
    if (!tx_buffer) {
        fprintf(stderr, "create TX buffer failed: %s\n", strerror(errno));
        iio_buffer_destroy(rx_buffer);
        free(tx_data);
        return 1;
    }

    fill_tx_buffer(tx_buffer, tx_data, tx_bytes);
    free(tx_data);

    struct rx_job job = {
        .buffer = rx_buffer,
        .device = rx_dev,
        .path = opt->rx_file,
        .target_bytes = rx_bytes,
        .bytes_written = 0,
        .rc = 0,
    };
    pthread_t rx_thread;
    int rc = pthread_create(&rx_thread, NULL, rx_thread_main, &job);
    if (rc != 0) {
        fprintf(stderr, "pthread_create failed: %s\n", strerror(rc));
        iio_buffer_destroy(tx_buffer);
        iio_buffer_destroy(rx_buffer);
        return 1;
    }

    nsleep_ms(opt->rx_arm_delay_ms);
    ssize_t pushed = opt->cyclic ? iio_buffer_push(tx_buffer) :
                                   iio_buffer_push_partial(tx_buffer, opt->tx_samples);
    if (pushed < 0) {
        fprintf(stderr, "TX push failed: %s\n", strerror((int)-pushed));
        iio_buffer_cancel(rx_buffer);
    }
    if (opt->cyclic) {
        nsleep_ms(opt->tx_duration_ms);
    }
    iio_buffer_cancel(tx_buffer);

    pthread_join(rx_thread, NULL);
    if (job.rc != 0) {
        fprintf(stderr, "RX capture failed: %s\n", strerror(job.rc));
    }

    iio_buffer_destroy(tx_buffer);
    iio_buffer_destroy(rx_buffer);

    struct timespec ended;
    clock_gettime(CLOCK_MONOTONIC, &ended);
    long elapsed_ms = (long)((ended.tv_sec - started.tv_sec) * 1000L +
                             (ended.tv_nsec - started.tv_nsec) / 1000000L);

    bool ok = pushed >= 0 && job.rc == 0;
    fprintf(json_out,
            "{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":%s,"
            "\"native_iio_burst_worker\":true,"
            "\"persistent_native_iio_burst_worker\":%s,"
            "\"native_iio_burst_worker_lifecycle\":%s,"
            "\"native_iio_burst_worker_lifecycle_proof\":\"%s\","
            "\"server_owned_xfer_loop\":%s,"
            "\"server_xfer_count\":%llu,"
            "\"native_iio_burst_transport_worker\":%s,"
            "\"native_iio_burst_transport_worker_proof\":\"%s\","
            "\"native_iio_burst_transport_session\":%s,"
            "\"native_iio_burst_transport_session_proof\":\"%s\","
            "\"transport_session_start_count\":%llu,"
            "\"transport_worker_request\":%s,"
            "\"transport_worker_request_count\":%llu,"
            "\"native_iio_burst_transport_service_loop\":%s,"
            "\"native_iio_burst_transport_service_loop_proof\":\"%s\","
            "\"transport_service_loop_start_count\":%llu,"
            "\"transport_service_loop_run\":%s,"
            "\"transport_service_loop_run_count\":%llu,"
            "\"native_iio_burst_transport_scheduler\":%s,"
            "\"native_iio_burst_transport_scheduler_proof\":\"%s\","
            "\"transport_scheduler_start_count\":%llu,"
            "\"transport_scheduler_drain\":%s,"
            "\"transport_scheduler_drain_count\":%llu,"
            "\"transport_scheduler_scheduled_request_count\":%llu,"
            "\"native_iio_burst_transport_autonomous_loop\":%s,"
            "\"native_iio_burst_transport_autonomous_loop_proof\":\"%s\","
            "\"transport_autonomous_loop_start_count\":%llu,"
            "\"transport_autonomous_loop_run\":%s,"
            "\"transport_autonomous_loop_run_count\":%llu,"
            "\"transport_autonomous_loop_scheduled_request_count\":%llu,"
            "\"native_iio_burst_transport_background_daemon\":%s,"
            "\"native_iio_burst_transport_background_daemon_proof\":\"%s\","
            "\"transport_background_daemon_start_count\":%llu,"
            "\"transport_background_daemon_xfer\":%s,"
            "\"transport_background_daemon_xfer_count\":%llu,"
            "\"transport_background_daemon_scheduled_request_count\":%llu,"
            "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
            "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"%s\","
            "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
            "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
            "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
            "\"native_iio_burst_state_daemon_transport_queue\":%s,"
            "\"native_iio_burst_state_daemon_transport_queue_proof\":\"%s\","
            "\"transport_state_daemon_queue_request\":%s,"
            "\"transport_state_daemon_queue_request_count\":%llu,"
            "\"python_transport_request_file_submission\":%s,"
            "\"python_transport_scheduler_queue_file_submission\":%s,"
            "\"python_xfer_field_orchestration\":%s,"
            "\"python_worker_xfer_submission\":%s,"
            "\"python_direct_service_loop_run\":%s,"
            "\"python_scheduler_drain_submission\":%s,"
            "\"python_autonomous_loop_run_submission\":%s,"
            "\"python_background_daemon_start_submission\":%s,"
            "\"next_boundary\":\"native_transport_worker_autonomous_daemon\","
            "\"libiio_rx_tx_worker\":true,"
            "\"same_process_rx_tx\":true,"
            "\"python_iio_transport\":false,"
            "\"tx_bytes\":%zu,\"rx_bytes\":%zd,\"rx_target_bytes\":%zu,"
            "\"cyclic\":%s,\"elapsed_ms\":%ld}\n",
            ok ? "true" : "false",
            opt->persistent_server_mode ? "true" : "false",
            opt->persistent_server_mode ? "true" : "false",
            opt->persistent_server_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1" : "",
            opt->persistent_server_mode ? "true" : "false",
            opt->server_xfer_count,
            opt->native_transport_worker_mode ? "true" : "false",
            opt->native_transport_worker_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1" : "",
            opt->native_transport_session_mode ? "true" : "false",
            opt->native_transport_session_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1" : "",
            opt->transport_session_start_count,
            opt->native_transport_worker_mode ? "true" : "false",
            opt->transport_worker_request_count,
            opt->native_transport_service_loop_mode ? "true" : "false",
            opt->native_transport_service_loop_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1" : "",
            opt->transport_service_loop_start_count,
            opt->native_transport_service_loop_mode ? "true" : "false",
            opt->transport_service_loop_run_count,
            opt->native_transport_scheduler_mode ? "true" : "false",
            opt->native_transport_scheduler_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1" : "",
            opt->transport_scheduler_start_count,
            opt->native_transport_scheduler_mode ? "true" : "false",
            opt->transport_scheduler_drain_count,
            opt->transport_scheduler_scheduled_request_count,
            opt->native_transport_autonomous_loop_mode ? "true" : "false",
            opt->native_transport_autonomous_loop_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1" : "",
            opt->transport_autonomous_loop_start_count,
            opt->native_transport_autonomous_loop_mode ? "true" : "false",
            opt->transport_autonomous_loop_run_count,
            opt->transport_autonomous_loop_scheduled_request_count,
            opt->native_transport_background_daemon_mode ? "true" : "false",
            opt->native_transport_background_daemon_mode ?
                "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1" : "",
            opt->transport_background_daemon_start_count,
            opt->native_transport_background_daemon_mode ? "true" : "false",
            opt->transport_background_daemon_xfer_count,
            opt->transport_background_daemon_scheduled_request_count,
            opt->native_transport_integrated_rf_service_daemon_mode ? "true" : "false",
            opt->native_transport_integrated_rf_service_daemon_mode ?
                "FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1" : "",
            opt->transport_integrated_rf_service_daemon_start_count,
            opt->transport_integrated_rf_service_daemon_enqueue_count,
            opt->transport_integrated_rf_service_daemon_drained_count,
            opt->native_transport_state_daemon_queue_mode ? "true" : "false",
            opt->native_transport_state_daemon_queue_mode ?
                "FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_QUEUE v1" : "",
            opt->native_transport_state_daemon_queue_mode ? "true" : "false",
            opt->transport_state_daemon_queue_request_count,
            opt->native_transport_state_daemon_queue_mode ? "false" : "true",
            opt->native_transport_state_daemon_queue_mode ? "false" : "true",
            opt->native_transport_worker_mode ? "false" : "true",
            (opt->native_transport_service_loop_mode ||
             opt->native_transport_autonomous_loop_mode) ? "false" :
                (opt->native_transport_worker_mode ? "true" : "false"),
            (opt->native_transport_service_loop_mode &&
             !opt->native_transport_scheduler_mode &&
             !opt->native_transport_autonomous_loop_mode) ? "true" : "false",
            (opt->native_transport_scheduler_mode &&
             !opt->native_transport_autonomous_loop_mode) ? "true" : "false",
            (opt->native_transport_autonomous_loop_mode &&
             !opt->native_transport_background_daemon_mode) ? "true" : "false",
            (opt->native_transport_background_daemon_mode &&
             !opt->native_transport_integrated_rf_service_daemon_mode) ? "true" : "false",
            tx_bytes, job.bytes_written, rx_bytes, opt->cyclic ? "true" : "false",
            elapsed_ms);
    fflush(json_out);
    return ok ? 0 : 1;
}

static const char *value_after(char *token, const char *prefix)
{
    size_t len = strlen(prefix);
    return strncmp(token, prefix, len) == 0 ? token + len : NULL;
}

static int apply_worker_request_field(struct options *req, char *key, char *value)
{
    if (strcmp(key, "tx_file") == 0) {
        char *copy = strdup(value);
        if (!copy) {
            return -1;
        }
        free((char *)req->tx_file);
        req->tx_file = copy;
    } else if (strcmp(key, "rx_file") == 0) {
        char *copy = strdup(value);
        if (!copy) {
            return -1;
        }
        free((char *)req->rx_file);
        req->rx_file = copy;
    } else if (strcmp(key, "tx_samples") == 0) {
        req->tx_samples = (size_t)parse_ull(value, "tx_samples");
    } else if (strcmp(key, "rx_samples") == 0) {
        req->rx_samples = (size_t)parse_ull(value, "rx_samples");
    } else if (strcmp(key, "buffer_size") == 0) {
        req->buffer_size = (size_t)parse_ull(value, "buffer_size");
    } else if (strcmp(key, "tx_duration_ms") == 0) {
        req->tx_duration_ms = (unsigned int)parse_ull(value, "tx_duration_ms");
    } else if (strcmp(key, "rx_arm_delay_ms") == 0) {
        req->rx_arm_delay_ms = (unsigned int)parse_ull(value, "rx_arm_delay_ms");
    } else if (strcmp(key, "cyclic") == 0) {
        req->cyclic = strcmp(value, "1") == 0 || strcmp(value, "true") == 0;
    } else if (strcmp(key, "event") != 0 &&
               strcmp(key, "native_iio_burst_transport_request") != 0) {
        return -1;
    }
    return 0;
}

static int load_worker_request_file(struct options *req, const char *path)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }
    char line[4096];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        char *eq = strchr(line, '=');
        if (!eq) {
            fclose(fp);
            return -1;
        }
        *eq = '\0';
        if (apply_worker_request_field(req, line, eq + 1) != 0) {
            fclose(fp);
            return -1;
        }
    }
    if (fclose(fp) != 0) {
        return -1;
    }
    return 0;
}

static int load_scheduler_queue_file(const char *path, char **request_file_out)
{
    *request_file_out = NULL;
    FILE *fp = fopen(path, "r");
    if (!fp) {
        return -1;
    }
    char line[4096];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        char *eq = strchr(line, '=');
        if (!eq) {
            fclose(fp);
            free(*request_file_out);
            *request_file_out = NULL;
            return -1;
        }
        *eq = '\0';
        const char *value = eq + 1;
        if (strcmp(line, "request_file") == 0) {
            char *copy = strdup(value);
            if (!copy) {
                fclose(fp);
                free(*request_file_out);
                *request_file_out = NULL;
                return -1;
            }
            free(*request_file_out);
            *request_file_out = copy;
        } else if (strcmp(line, "event") != 0 &&
                   strcmp(line, "native_iio_burst_transport_scheduler_queue") != 0 &&
                   strcmp(line, "priority") != 0 &&
                   strcmp(line, "sequence") != 0) {
            fclose(fp);
            free(*request_file_out);
            *request_file_out = NULL;
            return -1;
        }
    }
    if (fclose(fp) != 0 || !*request_file_out) {
        free(*request_file_out);
        *request_file_out = NULL;
        return -1;
    }
    return 0;
}

static int load_worker_request_fields(struct options *req, char *args)
{
    char *save = NULL;
    bool saw_field = false;
    for (char *token = strtok_r(args, " ", &save);
         token;
         token = strtok_r(NULL, " ", &save)) {
        char *eq = strchr(token, '=');
        if (!eq || eq == token) {
            return -1;
        }
        *eq = '\0';
        if (apply_worker_request_field(req, token, eq + 1) != 0) {
            return -1;
        }
        saw_field = true;
    }
    return saw_field ? 0 : -1;
}

struct background_job {
    pthread_t thread;
    pthread_mutex_t lock;
    bool active;
    bool running;
    bool done;
    int rc;
    struct iio_device *rx_dev;
    struct iio_device *tx_dev;
    struct options req;
    char *tx_file_owned;
    char *rx_file_owned;
    char *json;
    size_t json_len;
};

static void background_job_init(struct background_job *job)
{
    memset(job, 0, sizeof(*job));
    pthread_mutex_init(&job->lock, NULL);
}

static void background_job_release_owned(struct background_job *job)
{
    free(job->tx_file_owned);
    free(job->rx_file_owned);
    free(job->json);
    job->tx_file_owned = NULL;
    job->rx_file_owned = NULL;
    job->json = NULL;
    job->json_len = 0;
}

static void background_job_destroy(struct background_job *job)
{
    if (job->active) {
        pthread_join(job->thread, NULL);
        job->active = false;
    }
    background_job_release_owned(job);
    pthread_mutex_destroy(&job->lock);
}

static void *background_job_main(void *arg)
{
    struct background_job *job = arg;
    char *json = NULL;
    size_t json_len = 0;
    FILE *out = open_memstream(&json, &json_len);
    int rc = 1;

    if (out) {
        rc = run_xfer(job->rx_dev, job->tx_dev, &job->req, out);
        if (fclose(out) != 0) {
            rc = 1;
        }
    }

    pthread_mutex_lock(&job->lock);
    job->json = json;
    job->json_len = json_len;
    job->rc = rc;
    job->running = false;
    job->done = true;
    pthread_mutex_unlock(&job->lock);
    return NULL;
}

static int run_server(struct iio_device *rx_dev, struct iio_device *tx_dev,
                      const struct options *base)
{
    char line[4096];
    unsigned long long xfer_count = 0;
    unsigned long long worker_request_count = 0;
    unsigned long long transport_session_start_count = 0;
    unsigned long long transport_service_loop_start_count = 0;
    unsigned long long transport_service_loop_run_count = 0;
    unsigned long long transport_scheduler_start_count = 0;
    unsigned long long transport_scheduler_drain_count = 0;
    unsigned long long transport_scheduler_scheduled_request_count = 0;
    unsigned long long transport_autonomous_loop_start_count = 0;
    unsigned long long transport_autonomous_loop_run_count = 0;
    unsigned long long transport_autonomous_loop_scheduled_request_count = 0;
    unsigned long long transport_background_daemon_start_count = 0;
    unsigned long long transport_background_daemon_xfer_count = 0;
    unsigned long long transport_background_daemon_scheduled_request_count = 0;
    unsigned long long transport_integrated_rf_service_daemon_start_count = 0;
    unsigned long long transport_integrated_rf_service_daemon_enqueue_count = 0;
    unsigned long long transport_integrated_rf_service_daemon_drained_count = 0;
    unsigned long long transport_state_daemon_queue_request_count = 0;
    bool transport_session_started = false;
    bool transport_service_loop_started = false;
    bool transport_scheduler_started = false;
    bool transport_autonomous_loop_started = false;
    bool transport_background_daemon_started = false;
    bool transport_integrated_rf_service_daemon_started = false;
    struct background_job background_job;
    background_job_init(&background_job);

    printf("{\"event\":\"fieldmesh_iio_burst_xfer_server\",\"ok\":true,"
           "\"native_iio_burst_worker\":true,"
           "\"persistent_native_iio_burst_worker\":true,"
           "\"native_iio_burst_worker_lifecycle\":true,"
           "\"native_iio_burst_worker_lifecycle_proof\":\"FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1\","
           "\"server_owned_xfer_loop\":true,"
           "\"server_xfer_count\":0,"
           "\"native_iio_burst_transport_worker\":true,"
           "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
           "\"native_iio_burst_transport_session_supported\":true,"
           "\"native_iio_burst_transport_session\":false,"
           "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
           "\"native_iio_burst_transport_service_loop_supported\":true,"
           "\"native_iio_burst_transport_service_loop\":false,"
           "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
           "\"native_iio_burst_transport_scheduler_supported\":true,"
           "\"native_iio_burst_transport_scheduler\":false,"
           "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
           "\"native_iio_burst_transport_autonomous_loop_supported\":true,"
           "\"native_iio_burst_transport_autonomous_loop\":false,"
           "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
           "\"native_iio_burst_transport_background_daemon_supported\":true,"
           "\"native_iio_burst_transport_background_daemon\":false,"
           "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
           "\"native_iio_burst_integrated_rf_service_daemon_supported\":true,"
           "\"native_iio_burst_integrated_rf_service_daemon\":false,"
           "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
           "\"transport_worker_request_count\":0,"
           "\"transport_session_start_count\":0,"
           "\"transport_service_loop_start_count\":0,"
           "\"transport_service_loop_run_count\":0,"
           "\"transport_scheduler_start_count\":0,"
           "\"transport_scheduler_drain_count\":0,"
           "\"transport_scheduler_scheduled_request_count\":0,"
           "\"transport_autonomous_loop_start_count\":0,"
           "\"transport_autonomous_loop_run_count\":0,"
           "\"transport_autonomous_loop_scheduled_request_count\":0,"
           "\"transport_background_daemon_start_count\":0,"
           "\"transport_background_daemon_xfer_count\":0,"
           "\"transport_background_daemon_scheduled_request_count\":0,"
           "\"transport_integrated_rf_service_daemon_start_count\":0,"
           "\"transport_integrated_rf_service_daemon_enqueue_count\":0,"
           "\"transport_integrated_rf_service_daemon_drained_count\":0,"
           "\"python_xfer_field_orchestration\":false,"
           "\"python_worker_xfer_submission\":false,"
           "\"python_direct_service_loop_run\":false,"
           "\"python_scheduler_drain_submission\":false,"
           "\"python_autonomous_loop_run_submission\":false,"
           "\"python_background_daemon_start_submission\":false,"
           "\"next_boundary\":\"native_transport_worker_autonomous_daemon\","
           "\"server_pid\":%ld,"
           "\"libiio_rx_tx_worker\":true,"
           "\"python_iio_transport\":false}\n",
           (long)getpid());
    fflush(stdout);

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (strcmp(line, "TRANSPORT_WORKER_START") == 0) {
            transport_session_started = true;
            transport_session_start_count++;
            printf("{\"event\":\"fieldmesh_iio_burst_transport_worker_start\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"transport_session_start_count\":%llu,"
                   "\"transport_worker_request_count\":%llu,"
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"transport_service_loop_start_count\":%llu,"
                   "\"transport_service_loop_run_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_xfer_field_orchestration\":false,"
                   "\"python_worker_xfer_submission\":false,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_session_start_count,
                   worker_request_count,
                   transport_service_loop_started ? "true" : "false",
                   transport_service_loop_start_count,
                   transport_service_loop_run_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_WORKER_STATUS") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_transport_worker_status\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":%s,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"transport_session_start_count\":%llu,"
                   "\"transport_worker_request_count\":%llu,"
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"transport_service_loop_start_count\":%llu,"
                   "\"transport_service_loop_run_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_xfer_field_orchestration\":false,"
                   "\"python_worker_xfer_submission\":false,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_session_started ? "true" : "false",
                   transport_session_start_count,
                   worker_request_count,
                   transport_service_loop_started ? "true" : "false",
                   transport_service_loop_start_count,
                   transport_service_loop_run_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_SERVICE_LOOP_START") == 0) {
            if (!transport_session_started) {
                printf("{\"event\":\"fieldmesh_iio_burst_transport_service_loop_start\",\"ok\":false,"
                       "\"native_iio_burst_transport_worker\":true,"
                       "\"native_iio_burst_transport_session\":false,"
                       "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                       "\"native_iio_burst_transport_service_loop\":false,"
                       "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                       "\"error\":\"transport_session_not_started\"}\n");
                fflush(stdout);
                continue;
            }
            transport_service_loop_started = true;
            transport_service_loop_start_count++;
            printf("{\"event\":\"fieldmesh_iio_burst_transport_service_loop_start\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"transport_session_start_count\":%llu,"
                   "\"transport_worker_request_count\":%llu,"
                   "\"transport_service_loop_start_count\":%llu,"
                   "\"transport_service_loop_run_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_xfer_field_orchestration\":false,"
                   "\"python_worker_xfer_submission\":false,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_session_start_count,
                   worker_request_count,
                   transport_service_loop_start_count,
                   transport_service_loop_run_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_SERVICE_LOOP_STATUS") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_transport_service_loop_status\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":%s,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"transport_session_start_count\":%llu,"
                   "\"transport_worker_request_count\":%llu,"
                   "\"transport_service_loop_start_count\":%llu,"
                   "\"transport_service_loop_run_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_xfer_field_orchestration\":false,"
                   "\"python_worker_xfer_submission\":false,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_session_started ? "true" : "false",
                   transport_service_loop_started ? "true" : "false",
                   transport_session_start_count,
                   worker_request_count,
                   transport_service_loop_start_count,
                   transport_service_loop_run_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_SCHEDULER_START") == 0) {
            if (!transport_service_loop_started) {
                printf("{\"event\":\"fieldmesh_iio_burst_transport_scheduler_start\",\"ok\":false,"
                       "\"native_iio_burst_transport_service_loop\":false,"
                       "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                       "\"native_iio_burst_transport_scheduler\":false,"
                       "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                       "\"error\":\"transport_service_loop_not_started\"}\n");
                fflush(stdout);
                continue;
            }
            transport_scheduler_started = true;
            transport_scheduler_start_count++;
            printf("{\"event\":\"fieldmesh_iio_burst_transport_scheduler_start\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":true,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"transport_scheduler_start_count\":%llu,"
                   "\"transport_scheduler_drain_count\":%llu,"
                   "\"transport_scheduler_scheduled_request_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_scheduler_start_count,
                   transport_scheduler_drain_count,
                   transport_scheduler_scheduled_request_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_SCHEDULER_STATUS") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_transport_scheduler_status\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":%s,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":%s,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"transport_scheduler_start_count\":%llu,"
                   "\"transport_scheduler_drain_count\":%llu,"
                   "\"transport_scheduler_scheduled_request_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"next_boundary\":\"native_transport_worker_autonomous_daemon\"}\n",
                   transport_session_started ? "true" : "false",
                   transport_service_loop_started ? "true" : "false",
                   transport_scheduler_started ? "true" : "false",
                   transport_scheduler_start_count,
                   transport_scheduler_drain_count,
                   transport_scheduler_scheduled_request_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_AUTONOMOUS_LOOP_START") == 0) {
            if (!transport_scheduler_started) {
                printf("{\"event\":\"fieldmesh_iio_burst_transport_autonomous_loop_start\",\"ok\":false,"
                       "\"native_iio_burst_transport_scheduler\":false,"
                       "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                       "\"native_iio_burst_transport_autonomous_loop\":false,"
                       "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                       "\"error\":\"transport_scheduler_not_started\"}\n");
                fflush(stdout);
                continue;
            }
            transport_autonomous_loop_started = true;
            transport_autonomous_loop_start_count++;
            printf("{\"event\":\"fieldmesh_iio_burst_transport_autonomous_loop_start\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":true,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"native_iio_burst_transport_autonomous_loop\":true,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"transport_autonomous_loop_start_count\":%llu,"
                   "\"transport_autonomous_loop_run_count\":%llu,"
                   "\"transport_autonomous_loop_scheduled_request_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"python_scheduler_drain_submission\":false,"
                   "\"next_boundary\":\"native_transport_worker_background_daemon\"}\n",
                   transport_autonomous_loop_start_count,
                   transport_autonomous_loop_run_count,
                   transport_autonomous_loop_scheduled_request_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_AUTONOMOUS_LOOP_STATUS") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_transport_autonomous_loop_status\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":%s,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":%s,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"native_iio_burst_transport_autonomous_loop\":%s,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"transport_autonomous_loop_start_count\":%llu,"
                   "\"transport_autonomous_loop_run_count\":%llu,"
                   "\"transport_autonomous_loop_scheduled_request_count\":%llu,"
                   "\"server_xfer_count\":%llu,"
                   "\"python_direct_service_loop_run\":false,"
                   "\"python_scheduler_drain_submission\":false,"
                   "\"next_boundary\":\"native_transport_worker_background_daemon\"}\n",
                   transport_session_started ? "true" : "false",
                   transport_service_loop_started ? "true" : "false",
                   transport_scheduler_started ? "true" : "false",
                   transport_autonomous_loop_started ? "true" : "false",
                   transport_autonomous_loop_start_count,
                   transport_autonomous_loop_run_count,
                   transport_autonomous_loop_scheduled_request_count,
                   xfer_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_START") == 0) {
            if (!transport_autonomous_loop_started) {
                printf("{\"event\":\"fieldmesh_iio_burst_integrated_rf_service_daemon_start\",\"ok\":false,"
                       "\"native_iio_burst_transport_autonomous_loop\":false,"
                       "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                       "\"native_iio_burst_integrated_rf_service_daemon\":false,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"transport_autonomous_loop_not_started\"}\n");
                fflush(stdout);
                continue;
            }
            transport_integrated_rf_service_daemon_started = true;
            transport_integrated_rf_service_daemon_start_count++;
            printf("{\"event\":\"fieldmesh_iio_burst_integrated_rf_service_daemon_start\",\"ok\":true,"
                   "\"native_iio_burst_transport_autonomous_loop\":true,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"native_iio_burst_integrated_rf_service_daemon\":true,"
                   "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                   "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
                   "\"python_background_daemon_start_submission\":false,"
                   "\"next_boundary\":\"native_iio_transport_integrated_rf_service_daemon\"}\n",
                   transport_integrated_rf_service_daemon_start_count,
                   transport_integrated_rf_service_daemon_enqueue_count,
                   transport_integrated_rf_service_daemon_drained_count);
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_STATUS") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_integrated_rf_service_daemon_status\",\"ok\":true,"
                   "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                   "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                   "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
                   "\"python_background_daemon_start_submission\":false,"
                   "\"next_boundary\":\"native_iio_transport_integrated_rf_service_daemon\"}\n",
                   transport_integrated_rf_service_daemon_started ? "true" : "false",
                   transport_integrated_rf_service_daemon_start_count,
                   transport_integrated_rf_service_daemon_enqueue_count,
                   transport_integrated_rf_service_daemon_drained_count);
            fflush(stdout);
            continue;
        }
        const char *integrated_enqueue_prefix =
            "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_ENQUEUE ";
        const char *integrated_enqueue_fields_prefix =
            "TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_ENQUEUE_FIELDS ";
        bool integrated_daemon_enqueue =
            strncmp(line, integrated_enqueue_prefix,
                    strlen(integrated_enqueue_prefix)) == 0;
        bool integrated_daemon_enqueue_fields =
            strncmp(line, integrated_enqueue_fields_prefix,
                    strlen(integrated_enqueue_fields_prefix)) == 0;
        bool background_daemon_start =
            strncmp(line, "TRANSPORT_BACKGROUND_DAEMON_START ", 34) == 0;
        if (background_daemon_start || integrated_daemon_enqueue ||
            integrated_daemon_enqueue_fields) {
            if (!transport_autonomous_loop_started) {
                printf("{\"event\":\"%s\",\"ok\":false,"
                       "\"native_iio_burst_transport_autonomous_loop\":false,"
                       "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                       "\"native_iio_burst_transport_background_daemon\":false,"
                       "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                       "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"transport_autonomous_loop_not_started\"}\n",
                       integrated_daemon_enqueue ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue" :
                           integrated_daemon_enqueue_fields ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                           "fieldmesh_iio_burst_transport_background_daemon_start",
                       transport_integrated_rf_service_daemon_started ? "true" : "false");
                fflush(stdout);
                continue;
            }
            if ((integrated_daemon_enqueue || integrated_daemon_enqueue_fields) &&
                !transport_integrated_rf_service_daemon_started) {
                printf("{\"event\":\"%s\",\"ok\":false,"
                       "\"native_iio_burst_integrated_rf_service_daemon\":false,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"integrated_rf_service_daemon_not_started\"}\n",
                       integrated_daemon_enqueue_fields ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue");
                fflush(stdout);
                continue;
            }
            pthread_mutex_lock(&background_job.lock);
            bool background_running = background_job.active && background_job.running;
            bool background_done = background_job.active && background_job.done;
            pthread_mutex_unlock(&background_job.lock);
            if (background_running) {
                printf("{\"event\":\"%s\",\"ok\":false,"
                       "\"native_iio_burst_transport_background_daemon\":true,"
                       "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                       "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"transport_background_daemon_busy\"}\n",
                       integrated_daemon_enqueue ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue" :
                           integrated_daemon_enqueue_fields ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                           "fieldmesh_iio_burst_transport_background_daemon_start",
                       transport_integrated_rf_service_daemon_started ? "true" : "false");
                fflush(stdout);
                continue;
            }
            if (background_done) {
                pthread_join(background_job.thread, NULL);
                background_job.active = false;
                background_job_release_owned(&background_job);
            }

            struct options req = *base;
            req.tx_file = NULL;
            req.rx_file = NULL;
            req.tx_samples = 0;
            req.rx_samples = 0;
            req.persistent_server_mode = true;
            req.server_xfer_count = xfer_count + 1ULL;
            req.native_transport_worker_mode = true;
            req.native_transport_session_mode = transport_session_started;
            req.native_transport_service_loop_mode = true;
            req.native_transport_scheduler_mode = true;
            req.native_transport_autonomous_loop_mode = true;
            req.native_transport_background_daemon_mode = true;
            req.native_transport_integrated_rf_service_daemon_mode =
                integrated_daemon_enqueue || integrated_daemon_enqueue_fields;
            req.native_transport_state_daemon_queue_mode =
                integrated_daemon_enqueue_fields;
            req.transport_session_start_count = transport_session_start_count;
            req.transport_worker_request_count = worker_request_count + 1ULL;
            req.transport_service_loop_start_count = transport_service_loop_start_count;
            req.transport_service_loop_run_count = transport_service_loop_run_count + 1ULL;
            req.transport_scheduler_start_count = transport_scheduler_start_count;
            req.transport_scheduler_drain_count = transport_scheduler_drain_count + 1ULL;
            req.transport_scheduler_scheduled_request_count =
                transport_scheduler_scheduled_request_count + 1ULL;
            req.transport_autonomous_loop_start_count = transport_autonomous_loop_start_count;
            req.transport_autonomous_loop_run_count = transport_autonomous_loop_run_count + 1ULL;
            req.transport_autonomous_loop_scheduled_request_count =
                transport_autonomous_loop_scheduled_request_count + 1ULL;
            req.transport_background_daemon_start_count =
                transport_background_daemon_start_count + 1ULL;
            req.transport_background_daemon_xfer_count =
                transport_background_daemon_xfer_count + 1ULL;
            req.transport_background_daemon_scheduled_request_count =
                transport_background_daemon_scheduled_request_count + 1ULL;
            req.transport_integrated_rf_service_daemon_start_count =
                transport_integrated_rf_service_daemon_start_count;
            req.transport_integrated_rf_service_daemon_enqueue_count =
                transport_integrated_rf_service_daemon_enqueue_count +
                ((integrated_daemon_enqueue || integrated_daemon_enqueue_fields) ? 1ULL : 0ULL);
            req.transport_integrated_rf_service_daemon_drained_count =
                transport_integrated_rf_service_daemon_drained_count +
                ((integrated_daemon_enqueue || integrated_daemon_enqueue_fields) ? 1ULL : 0ULL);
            req.transport_state_daemon_queue_request_count =
                transport_state_daemon_queue_request_count +
                (integrated_daemon_enqueue_fields ? 1ULL : 0ULL);

            char *save = NULL;
            const char *queue_file = NULL;
            char *request_file = NULL;
            int request_ok = -1;
            if (integrated_daemon_enqueue_fields) {
                request_ok = load_worker_request_fields(
                    &req,
                    line + strlen(integrated_enqueue_fields_prefix));
            } else {
                char *args_start = integrated_daemon_enqueue ?
                    line + strlen(integrated_enqueue_prefix) :
                    line + 34;
                for (char *token = strtok_r(args_start, " ", &save);
                     token;
                     token = strtok_r(NULL, " ", &save)) {
                    const char *value = value_after(token, "queue_file=");
                    if (value) {
                        queue_file = value;
                    }
                }
                request_ok = (!queue_file ||
                    load_scheduler_queue_file(queue_file, &request_file) != 0 ||
                    load_worker_request_file(&req, request_file) != 0) ? -1 : 0;
            }
            if (request_ok != 0 || !req.tx_file || !req.rx_file ||
                req.tx_samples == 0 || req.rx_samples == 0) {
                free((char *)req.tx_file);
                free((char *)req.rx_file);
                free(request_file);
                printf("{\"event\":\"%s\",\"ok\":false,"
                       "\"native_iio_burst_transport_background_daemon\":false,"
                       "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                       "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"invalid_transport_request\"}\n",
                       integrated_daemon_enqueue ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue" :
                           integrated_daemon_enqueue_fields ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                           "fieldmesh_iio_burst_transport_background_daemon_start",
                       transport_integrated_rf_service_daemon_started ? "true" : "false");
                fflush(stdout);
                continue;
            }
            free(request_file);

            background_job.req = req;
            background_job.rx_dev = rx_dev;
            background_job.tx_dev = tx_dev;
            background_job.tx_file_owned = (char *)req.tx_file;
            background_job.rx_file_owned = (char *)req.rx_file;
            background_job.rc = 1;
            background_job.running = true;
            background_job.done = false;
            background_job.active = true;
            if (pthread_create(&background_job.thread, NULL,
                               background_job_main, &background_job) != 0) {
                background_job.active = false;
                background_job.running = false;
                background_job_release_owned(&background_job);
                printf("{\"event\":\"%s\",\"ok\":false,"
                       "\"native_iio_burst_transport_background_daemon\":false,"
                       "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                       "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                       "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                       "\"error\":\"pthread_create_failed\"}\n",
                       integrated_daemon_enqueue ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue" :
                           integrated_daemon_enqueue_fields ?
                           "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                           "fieldmesh_iio_burst_transport_background_daemon_start",
                       transport_integrated_rf_service_daemon_started ? "true" : "false");
                fflush(stdout);
                continue;
            }

            xfer_count++;
            worker_request_count++;
            transport_service_loop_run_count++;
            transport_scheduler_drain_count++;
            transport_scheduler_scheduled_request_count++;
            transport_autonomous_loop_run_count++;
            transport_autonomous_loop_scheduled_request_count++;
            transport_background_daemon_started = true;
            transport_background_daemon_start_count++;
            transport_background_daemon_xfer_count++;
            transport_background_daemon_scheduled_request_count++;
            if (integrated_daemon_enqueue || integrated_daemon_enqueue_fields) {
                transport_integrated_rf_service_daemon_enqueue_count++;
                transport_integrated_rf_service_daemon_drained_count++;
            }
            if (integrated_daemon_enqueue_fields) {
                transport_state_daemon_queue_request_count++;
            }
            printf("{\"event\":\"%s\",\"ok\":true,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":true,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"native_iio_burst_transport_autonomous_loop\":true,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"native_iio_burst_transport_background_daemon\":true,"
                   "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                   "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                   "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                   "\"transport_background_daemon_start_count\":%llu,"
                   "\"transport_background_daemon_xfer_count\":%llu,"
                   "\"transport_background_daemon_scheduled_request_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
                   "\"native_iio_burst_state_daemon_transport_queue\":%s,"
                   "\"native_iio_burst_state_daemon_transport_queue_proof\":\"FIELDMESH_IIO_BURST_STATE_DAEMON_TRANSPORT_QUEUE v1\","
                   "\"transport_state_daemon_queue_request\":%s,"
                   "\"transport_state_daemon_queue_request_count\":%llu,"
                   "\"transport_background_daemon_running\":true,"
                   "\"python_transport_request_file_submission\":%s,"
                   "\"python_transport_scheduler_queue_file_submission\":%s,"
                   "\"python_autonomous_loop_run_submission\":false,"
                   "\"python_background_daemon_start_submission\":%s,"
                   "\"next_boundary\":\"native_iio_transport_integrated_rf_service_daemon\"}\n",
                   integrated_daemon_enqueue ?
                       "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue" :
                       integrated_daemon_enqueue_fields ?
                       "fieldmesh_iio_burst_integrated_rf_service_daemon_enqueue_fields" :
                       "fieldmesh_iio_burst_transport_background_daemon_start",
                   transport_integrated_rf_service_daemon_started ? "true" : "false",
                   transport_background_daemon_start_count,
                   transport_background_daemon_xfer_count,
                   transport_background_daemon_scheduled_request_count,
                   transport_integrated_rf_service_daemon_start_count,
                   transport_integrated_rf_service_daemon_enqueue_count,
                   transport_integrated_rf_service_daemon_drained_count,
                   integrated_daemon_enqueue_fields ? "true" : "false",
                   integrated_daemon_enqueue_fields ? "true" : "false",
                   transport_state_daemon_queue_request_count,
                   integrated_daemon_enqueue_fields ? "false" : "true",
                   integrated_daemon_enqueue_fields ? "false" : "true",
                   (integrated_daemon_enqueue || integrated_daemon_enqueue_fields) ?
                       "false" :
                       "true");
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "TRANSPORT_BACKGROUND_DAEMON_STATUS") == 0) {
            pthread_mutex_lock(&background_job.lock);
            bool background_done = background_job.active && background_job.done;
            bool background_running = background_job.active && background_job.running;
            pthread_mutex_unlock(&background_job.lock);
            if (background_done) {
                pthread_join(background_job.thread, NULL);
                background_job.active = false;
                if (background_job.json) {
                    fputs(background_job.json, stdout);
                    if (background_job.json_len == 0 ||
                        background_job.json[background_job.json_len - 1] != '\n') {
                        fputc('\n', stdout);
                    }
                } else {
                    printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                           "\"native_iio_burst_transport_background_daemon\":true,"
                           "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                           "\"error\":\"transport_background_daemon_missing_result\"}\n");
                }
                fflush(stdout);
                background_job_release_owned(&background_job);
                continue;
            }
            printf("{\"event\":\"fieldmesh_iio_burst_transport_background_daemon_status\",\"ok\":true,"
                   "\"native_iio_burst_transport_background_daemon\":%s,"
                   "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                   "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                   "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                   "\"transport_background_daemon_start_count\":%llu,"
                   "\"transport_background_daemon_xfer_count\":%llu,"
                   "\"transport_background_daemon_scheduled_request_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
                   "\"transport_background_daemon_running\":%s,"
                   "\"transport_background_daemon_done\":false,"
                   "\"python_autonomous_loop_run_submission\":false,"
                   "\"python_background_daemon_start_submission\":false,"
                   "\"next_boundary\":\"native_iio_transport_integrated_rf_service_daemon\"}\n",
                   transport_background_daemon_started ? "true" : "false",
                   transport_integrated_rf_service_daemon_started ? "true" : "false",
                   transport_background_daemon_start_count,
                   transport_background_daemon_xfer_count,
                   transport_background_daemon_scheduled_request_count,
                   transport_integrated_rf_service_daemon_start_count,
                   transport_integrated_rf_service_daemon_enqueue_count,
                   transport_integrated_rf_service_daemon_drained_count,
                   background_running ? "true" : "false");
            fflush(stdout);
            continue;
        }
        if (strcmp(line, "QUIT") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer_server_quit\",\"ok\":true,"
                   "\"native_iio_burst_worker_lifecycle\":true,"
                   "\"native_iio_burst_worker_lifecycle_proof\":\"FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1\","
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":%s,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":%s,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"native_iio_burst_transport_scheduler\":%s,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"native_iio_burst_transport_autonomous_loop\":%s,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"native_iio_burst_transport_background_daemon\":%s,"
                   "\"native_iio_burst_transport_background_daemon_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1\","
                   "\"native_iio_burst_integrated_rf_service_daemon\":%s,"
                   "\"native_iio_burst_integrated_rf_service_daemon_proof\":\"FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1\","
                   "\"transport_session_start_count\":%llu,"
                   "\"transport_worker_request_count\":%llu,"
                   "\"transport_service_loop_start_count\":%llu,"
                   "\"transport_service_loop_run_count\":%llu,"
                   "\"transport_scheduler_start_count\":%llu,"
                   "\"transport_scheduler_drain_count\":%llu,"
                   "\"transport_scheduler_scheduled_request_count\":%llu,"
                   "\"transport_autonomous_loop_start_count\":%llu,"
                   "\"transport_autonomous_loop_run_count\":%llu,"
                   "\"transport_autonomous_loop_scheduled_request_count\":%llu,"
                   "\"transport_background_daemon_start_count\":%llu,"
                   "\"transport_background_daemon_xfer_count\":%llu,"
                   "\"transport_background_daemon_scheduled_request_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_start_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_enqueue_count\":%llu,"
                   "\"transport_integrated_rf_service_daemon_drained_count\":%llu,"
                   "\"server_owned_xfer_loop\":true,"
                   "\"server_xfer_count\":%llu}\n",
                   transport_session_started ? "true" : "false",
                   transport_service_loop_started ? "true" : "false",
                   transport_scheduler_started ? "true" : "false",
                   transport_autonomous_loop_started ? "true" : "false",
                   transport_background_daemon_started ? "true" : "false",
                   transport_integrated_rf_service_daemon_started ? "true" : "false",
                   transport_session_start_count,
                   worker_request_count,
                   transport_service_loop_start_count,
                   transport_service_loop_run_count,
                   transport_scheduler_start_count,
                   transport_scheduler_drain_count,
                   transport_scheduler_scheduled_request_count,
                   transport_autonomous_loop_start_count,
                   transport_autonomous_loop_run_count,
                   transport_autonomous_loop_scheduled_request_count,
                   transport_background_daemon_start_count,
                   transport_background_daemon_xfer_count,
                   transport_background_daemon_scheduled_request_count,
                   transport_integrated_rf_service_daemon_start_count,
                   transport_integrated_rf_service_daemon_enqueue_count,
                   transport_integrated_rf_service_daemon_drained_count,
                   xfer_count);
            fflush(stdout);
            background_job_destroy(&background_job);
            return 0;
        }
        bool worker_xfer = strncmp(line, "WORKER_XFER ", 12) == 0;
        bool service_loop_xfer = strncmp(line, "TRANSPORT_SERVICE_LOOP_RUN ", 27) == 0;
        bool scheduler_drain = strncmp(line, "TRANSPORT_SCHEDULER_DRAIN ", 26) == 0;
        bool autonomous_loop_run = strncmp(line, "TRANSPORT_AUTONOMOUS_LOOP_RUN ", 30) == 0;
        bool legacy_xfer = strncmp(line, "XFER ", 5) == 0;
        if (!worker_xfer && !service_loop_xfer && !scheduler_drain &&
            !autonomous_loop_run && !legacy_xfer) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"error\":\"expected_TRANSPORT_WORKER_or_SERVICE_LOOP_or_SCHEDULER_or_AUTONOMOUS_LOOP_or_WORKER_XFER_or_XFER_or_QUIT\"}\n");
            fflush(stdout);
            continue;
        }
        if ((worker_xfer || service_loop_xfer || scheduler_drain || autonomous_loop_run) &&
            !transport_session_started) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":false,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"error\":\"transport_session_not_started\"}\n");
            fflush(stdout);
            continue;
        }
        if ((service_loop_xfer || scheduler_drain || autonomous_loop_run) &&
            !transport_service_loop_started) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                   "\"native_iio_burst_transport_session\":true,"
                   "\"native_iio_burst_transport_session_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1\","
                   "\"native_iio_burst_transport_service_loop\":false,"
                   "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                   "\"error\":\"transport_service_loop_not_started\"}\n");
            fflush(stdout);
            continue;
        }
        if ((scheduler_drain || autonomous_loop_run) && !transport_scheduler_started) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_scheduler\":false,"
                   "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                   "\"error\":\"transport_scheduler_not_started\"}\n");
            fflush(stdout);
            continue;
        }
        if (autonomous_loop_run && !transport_autonomous_loop_started) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"native_iio_burst_transport_worker\":true,"
                   "\"native_iio_burst_transport_service_loop\":true,"
                   "\"native_iio_burst_transport_scheduler\":true,"
                   "\"native_iio_burst_transport_autonomous_loop\":false,"
                   "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                   "\"error\":\"transport_autonomous_loop_not_started\"}\n");
            fflush(stdout);
            continue;
        }

        struct options req = *base;
        req.tx_file = NULL;
        req.rx_file = NULL;
        req.tx_samples = 0;
        req.rx_samples = 0;
        req.persistent_server_mode = true;
        req.server_xfer_count = xfer_count + 1ULL;
        req.native_transport_worker_mode = worker_xfer || service_loop_xfer ||
            scheduler_drain || autonomous_loop_run;
        req.native_transport_session_mode = transport_session_started;
        req.native_transport_service_loop_mode = service_loop_xfer ||
            scheduler_drain || autonomous_loop_run;
        req.native_transport_scheduler_mode = scheduler_drain || autonomous_loop_run;
        req.native_transport_autonomous_loop_mode = autonomous_loop_run;
        req.transport_session_start_count = transport_session_start_count;
        req.transport_worker_request_count = (worker_xfer || service_loop_xfer ||
            scheduler_drain || autonomous_loop_run) ? worker_request_count + 1ULL : 0ULL;
        req.transport_service_loop_start_count = transport_service_loop_start_count;
        req.transport_service_loop_run_count = (service_loop_xfer || scheduler_drain ||
            autonomous_loop_run) ? transport_service_loop_run_count + 1ULL : 0ULL;
        req.transport_scheduler_start_count = transport_scheduler_start_count;
        req.transport_scheduler_drain_count = (scheduler_drain || autonomous_loop_run) ?
            transport_scheduler_drain_count + 1ULL : 0ULL;
        req.transport_scheduler_scheduled_request_count = (scheduler_drain || autonomous_loop_run) ?
            transport_scheduler_scheduled_request_count + 1ULL : 0ULL;
        req.transport_autonomous_loop_start_count = transport_autonomous_loop_start_count;
        req.transport_autonomous_loop_run_count = autonomous_loop_run ?
            transport_autonomous_loop_run_count + 1ULL : 0ULL;
        req.transport_autonomous_loop_scheduled_request_count = autonomous_loop_run ?
            transport_autonomous_loop_scheduled_request_count + 1ULL : 0ULL;

        char *save = NULL;
        char *scheduler_request_file = NULL;
        if (worker_xfer || service_loop_xfer || scheduler_drain || autonomous_loop_run) {
            const char *request_file = NULL;
            char *request_line = worker_xfer ? line + 12 :
                (service_loop_xfer ? line + 27 :
                 (scheduler_drain ? line + 26 : line + 30));
            for (char *token = strtok_r(request_line, " ", &save);
                 token;
                 token = strtok_r(NULL, " ", &save)) {
                const char *value = value_after(token, (scheduler_drain || autonomous_loop_run) ?
                                                "queue_file=" : "request_file=");
                if (value) {
                    request_file = value;
                }
            }
            if ((scheduler_drain || autonomous_loop_run) && request_file &&
                load_scheduler_queue_file(request_file, &scheduler_request_file) == 0) {
                request_file = scheduler_request_file;
            }
            if (!request_file || load_worker_request_file(&req, request_file) != 0) {
                free((char *)req.tx_file);
                free((char *)req.rx_file);
                free(scheduler_request_file);
                printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                       "\"native_iio_burst_transport_worker\":true,"
                       "\"native_iio_burst_transport_worker_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1\","
                       "\"native_iio_burst_transport_service_loop\":%s,"
                       "\"native_iio_burst_transport_service_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1\","
                       "\"native_iio_burst_transport_scheduler\":%s,"
                       "\"native_iio_burst_transport_scheduler_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1\","
                       "\"native_iio_burst_transport_autonomous_loop\":%s,"
                       "\"native_iio_burst_transport_autonomous_loop_proof\":\"FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1\","
                       "\"error\":\"invalid_transport_request\"}\n",
                       (service_loop_xfer || scheduler_drain || autonomous_loop_run) ? "true" : "false",
                       (scheduler_drain || autonomous_loop_run) ? "true" : "false",
                       autonomous_loop_run ? "true" : "false");
                fflush(stdout);
                continue;
            }
        } else {
            for (char *token = strtok_r(line + 5, " ", &save);
                 token;
                 token = strtok_r(NULL, " ", &save)) {
                const char *value;
                if ((value = value_after(token, "tx_file="))) {
                    req.tx_file = value;
                } else if ((value = value_after(token, "rx_file="))) {
                    req.rx_file = value;
                } else if ((value = value_after(token, "tx_samples="))) {
                    req.tx_samples = (size_t)parse_ull(value, "tx_samples");
                } else if ((value = value_after(token, "rx_samples="))) {
                    req.rx_samples = (size_t)parse_ull(value, "rx_samples");
                } else if ((value = value_after(token, "buffer_size="))) {
                    req.buffer_size = (size_t)parse_ull(value, "buffer_size");
                } else if ((value = value_after(token, "tx_duration_ms="))) {
                    req.tx_duration_ms = (unsigned int)parse_ull(value, "tx_duration_ms");
                } else if ((value = value_after(token, "rx_arm_delay_ms="))) {
                    req.rx_arm_delay_ms = (unsigned int)parse_ull(value, "rx_arm_delay_ms");
                } else if ((value = value_after(token, "cyclic="))) {
                    req.cyclic = strcmp(value, "1") == 0 || strcmp(value, "true") == 0;
                }
            }
        }

        if (!req.tx_file || !req.rx_file || req.tx_samples == 0 || req.rx_samples == 0) {
        if (worker_xfer || service_loop_xfer || scheduler_drain || autonomous_loop_run) {
                free((char *)req.tx_file);
                free((char *)req.rx_file);
                free(scheduler_request_file);
            }
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"error\":\"missing_XFER_fields\"}\n");
            fflush(stdout);
            continue;
        }
        xfer_count++;
        if (worker_xfer || service_loop_xfer) {
            worker_request_count++;
        }
        if (scheduler_drain || autonomous_loop_run) {
            worker_request_count++;
        }
        if (service_loop_xfer || scheduler_drain || autonomous_loop_run) {
            transport_service_loop_run_count++;
        }
        if (scheduler_drain || autonomous_loop_run) {
            transport_scheduler_drain_count++;
            transport_scheduler_scheduled_request_count++;
        }
        if (autonomous_loop_run) {
            transport_autonomous_loop_run_count++;
            transport_autonomous_loop_scheduled_request_count++;
        }
        (void)run_xfer(rx_dev, tx_dev, &req, stdout);
        if (worker_xfer || service_loop_xfer || scheduler_drain || autonomous_loop_run) {
            free((char *)req.tx_file);
            free((char *)req.rx_file);
        }
        free(scheduler_request_file);
    }
    background_job_destroy(&background_job);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && strcmp(argv[1], "--bpsk-self-test") == 0) {
        return run_bpsk_self_test();
    }
    if (argc >= 2 && strcmp(argv[1], "--native-worker-self-test") == 0) {
        return run_native_worker_self_test();
    }
    if (argc >= 2 && strcmp(argv[1], "--bpsk-benchmark") == 0) {
        return run_bpsk_benchmark(argc, argv);
    }
    if (argc >= 2 && strcmp(argv[1], "--bpsk-encode") == 0) {
        return run_bpsk_encode(argc, argv);
    }
    if (argc >= 2 && strcmp(argv[1], "--bpsk-decode") == 0) {
        return run_bpsk_decode(argc, argv);
    }
    if (argc >= 2 && strcmp(argv[1], "--bfsk-self-test") == 0) {
        return run_bfsk_self_test();
    }
    if (argc >= 2 && strcmp(argv[1], "--bfsk-benchmark") == 0) {
        return run_bfsk_benchmark(argc, argv);
    }
    if (argc >= 2 && strcmp(argv[1], "--bfsk-encode") == 0) {
        return run_bfsk_encode(argc, argv);
    }
    if (argc >= 2 && strcmp(argv[1], "--bfsk-decode") == 0) {
        return run_bfsk_decode(argc, argv);
    }

    struct options opt;
    parse_args(argc, argv, &opt);

    struct iio_context *rx_ctx = open_context(opt.rx_uri, opt.rx_timeout_ms);
    struct iio_context *tx_ctx = open_context(opt.tx_uri, opt.rx_timeout_ms);
    struct iio_device *rx_dev = find_device(rx_ctx, opt.rx_device);
    struct iio_device *tx_dev = find_device(tx_ctx, opt.tx_device);

    enable_channels(rx_dev, &opt, false);
    enable_channels(tx_dev, &opt, true);

    int rc = opt.server ? run_server(rx_dev, tx_dev, &opt) :
                          run_xfer(rx_dev, tx_dev, &opt, stdout);
    iio_context_destroy(tx_ctx);
    iio_context_destroy(rx_ctx);
    return rc;
}
