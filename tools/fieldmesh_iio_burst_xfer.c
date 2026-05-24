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
            "       fieldmesh_iio_burst_xfer --bpsk-encode --frame-file PATH --iq-file PATH "
            "[--sample-rate-hz N] [--baseband-carrier-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bpsk-decode --iq-file PATH --decoded-file PATH "
            "[--expected-frame-len N] [--expected-frame-crc HEX] "
            "[--sample-rate-hz N] [--baseband-carrier-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bfsk-self-test\n"
            "       fieldmesh_iio_burst_xfer --bfsk-encode --frame-file PATH --iq-file PATH "
            "[--sample-rate-hz N] [--space-hz N] [--mark-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n"
            "       fieldmesh_iio_burst_xfer --bfsk-decode --iq-file PATH --decoded-file PATH "
            "[--expected-frame-len N] [--expected-frame-crc HEX] "
            "[--sample-rate-hz N] [--space-hz N] [--mark-hz N] "
            "[--samples-per-symbol N] [--bit-repeat N]\n");
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
        } else {
            fprintf(stderr, "unknown or incomplete modem argument: %s\n", arg);
            usage(stderr);
            exit(2);
        }
    }
    if (opt->sample_rate_hz == 0 || opt->samples_per_symbol < 2 || opt->bit_repeat == 0 ||
        opt->space_hz <= 0.0 || opt->mark_hz <= 0.0) {
        fprintf(stderr, "invalid modem parameters\n");
        exit(2);
    }
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
    struct blob decoded = {0};
    unsigned int sample_offset = 0;
    unsigned int chip_phase = 0;
    size_t bit_start = 0;
    bool ok = bpsk_decode_frame(iq.data, iq.len, &opt, &decoded,
                                &sample_offset, &chip_phase, &bit_start);
    ok = ok && decoded.len == sizeof(frame) &&
         memcmp(decoded.data, frame, sizeof(frame)) == 0;
    fprintf(stdout,
            "{\"event\":\"fieldmesh_bpsk_modem_self_test\",\"ok\":%s,"
            "\"frame_bytes\":%zu,\"iq_bytes\":%zu,\"sample_offset\":%u,"
            "\"chip_phase\":%u,\"bit_start\":%zu}\n",
            ok ? "true" : "false", sizeof(frame), iq.len, sample_offset,
            chip_phase, bit_start);
    free(decoded.data);
    free(iq.data);
    return ok ? 0 : 1;
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
            "\"tx_bytes\":%zu,\"rx_bytes\":%zd,\"rx_target_bytes\":%zu,"
            "\"cyclic\":%s,\"elapsed_ms\":%ld}\n",
            ok ? "true" : "false",
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

static int run_server(struct iio_device *rx_dev, struct iio_device *tx_dev,
                      const struct options *base)
{
    char line[4096];

    printf("{\"event\":\"fieldmesh_iio_burst_xfer_server\",\"ok\":true}\n");
    fflush(stdout);

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (strcmp(line, "QUIT") == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer_server_quit\",\"ok\":true}\n");
            fflush(stdout);
            return 0;
        }
        if (strncmp(line, "XFER ", 5) != 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"error\":\"expected_XFER_or_QUIT\"}\n");
            fflush(stdout);
            continue;
        }

        struct options req = *base;
        req.tx_file = NULL;
        req.rx_file = NULL;
        req.tx_samples = 0;
        req.rx_samples = 0;

        char *save = NULL;
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

        if (!req.tx_file || !req.rx_file || req.tx_samples == 0 || req.rx_samples == 0) {
            printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":false,"
                   "\"error\":\"missing_XFER_fields\"}\n");
            fflush(stdout);
            continue;
        }
        (void)run_xfer(rx_dev, tx_dev, &req, stdout);
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && strcmp(argv[1], "--bpsk-self-test") == 0) {
        return run_bpsk_self_test();
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
