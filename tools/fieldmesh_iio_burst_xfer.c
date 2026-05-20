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
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>

#define MAX_CHANNELS 8

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
            "[--channel voltage0 --channel voltage1]\n");
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
        } else {
            fprintf(stderr, "unknown or incomplete argument: %s\n", arg);
            usage(stderr);
            exit(2);
        }
    }

    if (!opt->tx_uri || !opt->rx_uri || !opt->tx_device || !opt->rx_device ||
        !opt->tx_file || !opt->rx_file || opt->tx_samples == 0 ||
        opt->rx_samples == 0) {
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

int main(int argc, char **argv)
{
    struct options opt;
    parse_args(argc, argv, &opt);

    struct iio_context *rx_ctx = open_context(opt.rx_uri, opt.rx_timeout_ms);
    struct iio_context *tx_ctx = open_context(opt.tx_uri, opt.rx_timeout_ms);
    struct iio_device *rx_dev = find_device(rx_ctx, opt.rx_device);
    struct iio_device *tx_dev = find_device(tx_ctx, opt.tx_device);

    enable_channels(rx_dev, &opt, false);
    enable_channels(tx_dev, &opt, true);

    ssize_t rx_sample_size = iio_device_get_sample_size(rx_dev);
    ssize_t tx_sample_size = iio_device_get_sample_size(tx_dev);
    if (rx_sample_size <= 0 || tx_sample_size <= 0) {
        fprintf(stderr, "invalid IIO sample sizes: rx=%zd tx=%zd\n", rx_sample_size, tx_sample_size);
        return 1;
    }

    size_t tx_bytes = opt.tx_samples * (size_t)tx_sample_size;
    size_t rx_bytes = opt.rx_samples * (size_t)rx_sample_size;
    unsigned char *tx_data = read_file_exact(opt.tx_file, tx_bytes);

    struct iio_buffer *rx_buffer = iio_device_create_buffer(rx_dev, opt.buffer_size, false);
    if (!rx_buffer) {
        fprintf(stderr, "create RX buffer failed: %s\n", strerror(errno));
        free(tx_data);
        return 1;
    }
    struct iio_buffer *tx_buffer = iio_device_create_buffer(tx_dev, opt.tx_samples, opt.cyclic);
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
        .path = opt.rx_file,
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

    nsleep_ms(opt.rx_arm_delay_ms);
    ssize_t pushed = opt.cyclic ? iio_buffer_push(tx_buffer) : iio_buffer_push_partial(tx_buffer, opt.tx_samples);
    if (pushed < 0) {
        fprintf(stderr, "TX push failed: %s\n", strerror((int)-pushed));
        iio_buffer_cancel(rx_buffer);
    }
    if (opt.cyclic) {
        nsleep_ms(opt.tx_duration_ms);
    }
    iio_buffer_cancel(tx_buffer);

    pthread_join(rx_thread, NULL);
    if (job.rc != 0) {
        fprintf(stderr, "RX capture failed: %s\n", strerror(job.rc));
    }

    iio_buffer_destroy(tx_buffer);
    iio_buffer_destroy(rx_buffer);
    iio_context_destroy(tx_ctx);
    iio_context_destroy(rx_ctx);

    if (pushed < 0 || job.rc != 0) {
        return 1;
    }

    printf("{\"event\":\"fieldmesh_iio_burst_xfer\",\"ok\":true,"
           "\"tx_bytes\":%zu,\"rx_bytes\":%zd,\"rx_target_bytes\":%zu,"
           "\"cyclic\":%s}\n",
           tx_bytes, job.bytes_written, rx_bytes, opt.cyclic ? "true" : "false");
    return 0;
}
