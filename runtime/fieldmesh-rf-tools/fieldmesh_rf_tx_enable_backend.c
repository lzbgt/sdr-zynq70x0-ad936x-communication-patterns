#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const char *EVENT = "fieldmesh_rf_tx_enable_backend";
static const char *IIO_EVENT = "fieldmesh_rf_tx_enable_backend_iio_attr";
static const char *SLEEP_EVENT = "fieldmesh_rf_tx_enable_backend_sleep";
static const char *ROLLBACK_GAIN_DB = "-89.75";

static void json_escape(FILE *out, const char *s) {
    for (; *s != '\0'; ++s) {
        if (*s == '\\' || *s == '"') {
            fputc('\\', out);
        }
        if ((unsigned char)*s < 0x20) {
            fprintf(out, "\\u%04x", (unsigned char)*s);
        } else {
            fputc(*s, out);
        }
    }
}

static int fail(const char *message) {
    fprintf(stderr, "{\"event\":\"%s\",\"ok\":false,\"error\":\"", EVENT);
    json_escape(stderr, message);
    fputs("\"}\n", stderr);
    return 1;
}

static char *read_file(const char *path, size_t limit) {
    FILE *fp = fopen(path, "rb");
    if (fp == NULL) {
        return NULL;
    }
    char *buf = calloc(limit + 1, 1);
    if (buf == NULL) {
        fclose(fp);
        return NULL;
    }
    size_t n = fread(buf, 1, limit, fp);
    if (ferror(fp) || (!feof(fp) && n == limit)) {
        free(buf);
        fclose(fp);
        return NULL;
    }
    buf[n] = '\0';
    fclose(fp);
    return buf;
}

static const char *json_value(const char *json, const char *key) {
    char pattern[128];
    if (snprintf(pattern, sizeof(pattern), "\"%s\"", key) >= (int)sizeof(pattern)) {
        return NULL;
    }
    const char *p = strstr(json, pattern);
    if (p == NULL) {
        return NULL;
    }
    p += strlen(pattern);
    while (isspace((unsigned char)*p)) {
        ++p;
    }
    if (*p != ':') {
        return NULL;
    }
    ++p;
    while (isspace((unsigned char)*p)) {
        ++p;
    }
    return p;
}

static bool json_bool(const char *json, const char *key, bool *out) {
    const char *p = json_value(json, key);
    if (p == NULL) {
        return false;
    }
    if (strncmp(p, "true", 4) == 0) {
        *out = true;
        return true;
    }
    if (strncmp(p, "false", 5) == 0) {
        *out = false;
        return true;
    }
    return false;
}

static bool json_i64(const char *json, const char *key, int64_t *out) {
    const char *p = json_value(json, key);
    if (p == NULL) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    long long value = strtoll(p, &end, 10);
    if (errno != 0 || end == p) {
        return false;
    }
    *out = (int64_t)value;
    return true;
}

static bool json_int(const char *json, const char *key, long *out) {
    int64_t value = 0;
    if (!json_i64(json, key, &value) || value < (-2147483647 - 1) || value > 2147483647) {
        return false;
    }
    *out = (long)value;
    return true;
}

static bool json_double(const char *json, const char *key, double *out) {
    const char *p = json_value(json, key);
    if (p == NULL) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    double value = strtod(p, &end);
    if (errno != 0 || end == p) {
        return false;
    }
    *out = value;
    return true;
}

static bool json_string(const char *json, const char *key, char *out, size_t out_len) {
    const char *p = json_value(json, key);
    if (p == NULL || *p != '"' || out_len == 0) {
        return false;
    }
    ++p;
    size_t n = 0;
    while (*p != '\0' && *p != '"') {
        char ch = *p++;
        if (ch == '\\') {
            if (*p == '\0') {
                return false;
            }
            ch = *p++;
        }
        if (n + 1 >= out_len) {
            return false;
        }
        out[n++] = ch;
    }
    if (*p != '"') {
        return false;
    }
    out[n] = '\0';
    return true;
}

static bool require_bool(const char *json, const char *key, bool expected) {
    bool value = false;
    return json_bool(json, key, &value) && value == expected;
}

static bool env_bool_is_one(const char *name) {
    const char *value = getenv(name);
    return value != NULL && strcmp(value, "1") == 0;
}

static bool env_int_matches(const char *name, long expected) {
    const char *value = getenv(name);
    if (value == NULL) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    long parsed = strtol(value, &end, 10);
    return errno == 0 && end != value && *end == '\0' && parsed == expected;
}

static bool env_double_matches(const char *name, double expected) {
    const char *value = getenv(name);
    if (value == NULL) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    double parsed = strtod(value, &end);
    double diff = parsed - expected;
    if (diff < 0.0) {
        diff = -diff;
    }
    return errno == 0 && end != value && *end == '\0' && diff < 0.000001;
}

static bool dry_run_enabled(void) {
    const char *value = getenv("FIELD_MESH_BACKEND_DRY_RUN");
    return value != NULL && strcmp(value, "1") == 0;
}

static int wait_child(pid_t pid, const char *argv0) {
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return fail("waitpid failed");
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "{\"event\":\"%s\",\"ok\":false,\"error\":\"", EVENT);
        json_escape(stderr, argv0);
        fprintf(stderr, " failed\",\"child_status\":%d}\n", status);
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }
    return 0;
}

static int run_argv(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) {
        return fail("fork failed");
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    return wait_child(pid, argv[0]);
}

static int set_iio_attr(const char *channel, const char *attribute, const char *value, const char *phase) {
    char *const argv[] = {
        "iio_attr",
        "-c",
        "ad9361-phy",
        (char *)channel,
        (char *)attribute,
        (char *)value,
        NULL,
    };

    if (dry_run_enabled()) {
        printf("{\"event\":\"%s\",\"ok\":true,\"dry_run\":true,\"native_iio_attr_control\":true,\"phase\":\"", IIO_EVENT);
        json_escape(stdout, phase);
        printf("\",\"channel\":\"");
        json_escape(stdout, channel);
        printf("\",\"attribute\":\"");
        json_escape(stdout, attribute);
        printf("\",\"value\":\"");
        json_escape(stdout, value);
        printf("\",\"argv\":\"iio_attr -c ad9361-phy ");
        json_escape(stdout, channel);
        fputc(' ', stdout);
        json_escape(stdout, attribute);
        fputc(' ', stdout);
        json_escape(stdout, value);
        printf("\"}\n");
        return 0;
    }
    return run_argv(argv);
}

static int set_tx_hardware_gain(const char *gain_db, const char *phase) {
    return set_iio_attr("voltage0", "hardwaregain", gain_db, phase);
}

static int tune_rf_profile(int64_t center_frequency_hz, int64_t sample_rate_hz, int64_t rf_bandwidth_hz) {
    char center[32];
    char sample[32];
    char bandwidth[32];
    snprintf(center, sizeof(center), "%lld", (long long)center_frequency_hz);
    snprintf(sample, sizeof(sample), "%lld", (long long)sample_rate_hz);
    snprintf(bandwidth, sizeof(bandwidth), "%lld", (long long)rf_bandwidth_hz);

    if (set_iio_attr("altvoltage1", "frequency", center, "tune_center_frequency") != 0) {
        return 1;
    }
    if (set_iio_attr("voltage0", "sampling_frequency", sample, "tune_sample_rate") != 0) {
        return 1;
    }
    if (set_iio_attr("voltage0", "rf_bandwidth", bandwidth, "tune_rf_bandwidth") != 0) {
        return 1;
    }
    return 0;
}

static int sleep_bounded_ms(long duration_ms) {
    if (dry_run_enabled()) {
        printf("{\"event\":\"%s\",\"ok\":true,\"dry_run\":true,\"duration_ms\":%ld}\n", SLEEP_EVENT, duration_ms);
        return 0;
    }

    struct timespec req = {
        .tv_sec = duration_ms / 1000,
        .tv_nsec = (duration_ms % 1000) * 1000000L,
    };
    while (nanosleep(&req, &req) != 0) {
        if (errno != EINTR) {
            return fail("nanosleep failed");
        }
    }
    return 0;
}

static int run_tx_enable(long max_duration_ms, double tx_attenuation_db,
                         int64_t center_frequency_hz, int64_t sample_rate_hz, int64_t rf_bandwidth_hz) {
    char tx_gain_db[32];
    snprintf(tx_gain_db, sizeof(tx_gain_db), "-%.6g", tx_attenuation_db);

    if (tune_rf_profile(center_frequency_hz, sample_rate_hz, rf_bandwidth_hz) != 0) {
        return 1;
    }
    if (set_tx_hardware_gain(tx_gain_db, "enable") != 0) {
        return 1;
    }
    if (sleep_bounded_ms(max_duration_ms) != 0) {
        (void)set_tx_hardware_gain(ROLLBACK_GAIN_DB, "rollback_after_sleep_error");
        return 1;
    }
    if (set_tx_hardware_gain(ROLLBACK_GAIN_DB, "rollback") != 0) {
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *request_path = NULL;
    if (argc != 4 || strcmp(argv[1], "--bounded-tx-enable") != 0 || strcmp(argv[2], "--request") != 0) {
        return fail("usage: fieldmesh-rf-tx-enable-backend --bounded-tx-enable --request PATH");
    }
    request_path = argv[3];

    char *json = read_file(request_path, 65536);
    if (json == NULL) {
        return fail("failed to read request JSON");
    }

    int rc = 1;
    char event[128];
    char mode[64];
    char fixture_id[128];
    long contract_version = 0;
    long max_duration_ms = 0;
    int64_t center_frequency_hz = 0;
    int64_t sample_rate_hz = 0;
    int64_t rf_bandwidth_hz = 0;
    double fixture_attenuation_db = 0.0;
    double tx_attenuation_db = 0.0;

    if (!json_string(json, "event", event, sizeof(event)) ||
        strcmp(event, "fieldmesh_rf_tx_enable_backend_request") != 0) {
        rc = fail("request event mismatch");
        goto out;
    }
    if (!json_int(json, "contract_version", &contract_version) || contract_version != 1) {
        rc = fail("request contract_version mismatch");
        goto out;
    }
    if (!json_string(json, "mode", mode, sizeof(mode)) ||
        (strcmp(mode, "dry-run") != 0 && strcmp(mode, "execute-live-tx") != 0)) {
        rc = fail("request mode mismatch");
        goto out;
    }
    if (!json_string(json, "fixture_id", fixture_id, sizeof(fixture_id)) || fixture_id[0] == '\0') {
        rc = fail("request fixture_id is required");
        goto out;
    }
    if (!json_int(json, "max_tx_duration_ms", &max_duration_ms) ||
        max_duration_ms < 1 || max_duration_ms > 1000) {
        rc = fail("request max_tx_duration_ms must be 1..1000");
        goto out;
    }
    if (!json_double(json, "fixture_attenuation_db", &fixture_attenuation_db) ||
        fixture_attenuation_db < 30.0) {
        rc = fail("request fixture_attenuation_db must be >= 30");
        goto out;
    }
    if (!json_double(json, "tx_attenuation_db", &tx_attenuation_db) ||
        tx_attenuation_db < 0.0) {
        rc = fail("request tx_attenuation_db must be >= 0");
        goto out;
    }
    if (!json_i64(json, "center_frequency_hz", &center_frequency_hz) ||
        center_frequency_hz < 70000000LL || center_frequency_hz > 6000000000LL) {
        rc = fail("request center_frequency_hz is outside AD936x range");
        goto out;
    }
    if (!json_i64(json, "sample_rate_hz", &sample_rate_hz) ||
        sample_rate_hz < 520000LL || sample_rate_hz > 61440000LL) {
        rc = fail("request sample_rate_hz is outside AD936x practical range");
        goto out;
    }
    if (!json_i64(json, "rf_bandwidth_hz", &rf_bandwidth_hz) ||
        rf_bandwidth_hz < 200000LL || rf_bandwidth_hz > 56000000LL) {
        rc = fail("request rf_bandwidth_hz is outside AD936x practical range");
        goto out;
    }

    const char *required_true[] = {
        "ok",
        "conducted_or_shielded",
        "legal_frequency_profile",
        "rx_first",
        "tx_enable_guard",
        "sidecar_preflight_passed",
        "rf_engine_ready",
        "target_is_zynq_board",
        "requires_bounded_tx_duration",
        "requires_native_tune",
        "requires_rollback",
        "requires_c_rf_guard_action_policy_self_test",
        "starts_rf_tx_when_executed",
        "writes_hardware_when_executed",
        "active_source_select_allowed",
        "idle_guard_apply_allowed",
        "idle_source_select_allowed",
    };
    for (size_t i = 0; i < sizeof(required_true) / sizeof(required_true[0]); ++i) {
        if (!require_bool(json, required_true[i], true)) {
            char message[160];
            snprintf(message, sizeof(message), "request boolean %s must be true", required_true[i]);
            rc = fail(message);
            goto out;
        }
    }

    const char *required_false[] = {
        "opens_iio_buffers",
        "uses_inter_board_ip_routing",
        "active_guard_apply_allowed",
        "fault_guard_apply_allowed",
        "fault_source_select_allowed",
        "reads_hardware",
        "writes_hardware",
    };
    for (size_t i = 0; i < sizeof(required_false) / sizeof(required_false[0]); ++i) {
        if (!require_bool(json, required_false[i], false)) {
            char message[160];
            snprintf(message, sizeof(message), "request boolean %s must be false", required_false[i]);
            rc = fail(message);
            goto out;
        }
    }

    if (!env_bool_is_one("FIELD_MESH_EXECUTE_LIVE_TX") ||
        !env_bool_is_one("FIELD_MESH_ALLOW_HARDWARE_WRITES") ||
        !env_bool_is_one("FIELD_MESH_ALLOW_RF_TX")) {
        rc = fail("live RF and hardware authorization environment is required");
        goto out;
    }
    const char *env_fixture = getenv("FIELD_MESH_FIXTURE_ID");
    if (env_fixture == NULL || strcmp(env_fixture, fixture_id) != 0) {
        rc = fail("FIELD_MESH_FIXTURE_ID does not match request");
        goto out;
    }
    if (!env_int_matches("FIELD_MESH_MAX_TX_DURATION_MS", max_duration_ms)) {
        rc = fail("FIELD_MESH_MAX_TX_DURATION_MS does not match request");
        goto out;
    }
    if (!env_double_matches("FIELD_MESH_FIXTURE_ATTENUATION_DB", fixture_attenuation_db)) {
        rc = fail("FIELD_MESH_FIXTURE_ATTENUATION_DB does not match request");
        goto out;
    }

    rc = run_tx_enable(max_duration_ms, tx_attenuation_db, center_frequency_hz, sample_rate_hz, rf_bandwidth_hz);
    if (rc == 0) {
        printf("{\"event\":\"%s\",\"ok\":true,\"request\":\"", EVENT);
        json_escape(stdout, request_path);
        printf("\",\"fixture_id\":\"");
        json_escape(stdout, fixture_id);
        printf("\",\"center_frequency_hz\":%lld,\"sample_rate_hz\":%lld,\"rf_bandwidth_hz\":%lld,\"max_tx_duration_ms\":%ld,\"tx_attenuation_db\":%.6g,\"rollback_tx_attenuation_db\":89.75,\"writes_hardware\":true,\"starts_rf_tx\":true,\"bounded\":true,\"native_tune\":true,\"native_iio_attr_control\":true,\"delegated_to\":\"iio_attr\"}\n",
               (long long)center_frequency_hz, (long long)sample_rate_hz, (long long)rf_bandwidth_hz, max_duration_ms, tx_attenuation_db);
    }

out:
    free(json);
    return rc;
}
