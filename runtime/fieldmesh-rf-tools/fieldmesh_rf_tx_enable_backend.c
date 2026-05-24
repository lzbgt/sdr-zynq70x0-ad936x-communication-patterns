#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *EVENT = "fieldmesh_rf_tx_enable_backend";

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

static bool json_int(const char *json, const char *key, long *out) {
    const char *p = json_value(json, key);
    if (p == NULL) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    long value = strtol(p, &end, 10);
    if (errno != 0 || end == p) {
        return false;
    }
    *out = value;
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

static int run_tx_enable(long max_duration_ms, double tx_attenuation_db) {
    char duration[32];
    char attenuation[32];
    snprintf(duration, sizeof(duration), "%ld", max_duration_ms);
    snprintf(attenuation, sizeof(attenuation), "%.6g", tx_attenuation_db);

    pid_t pid = fork();
    if (pid < 0) {
        return fail("fork failed");
    }
    if (pid == 0) {
        char *const argv[] = {
            "fieldmesh-radio-tx-enable",
            "--max-duration-ms",
            duration,
            "--tx-attenuation-db",
            attenuation,
            "--conducted-or-shielded",
            "--rx-first",
            "--tx-enable-guard",
            NULL,
        };
        execvp(argv[0], argv);
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        return fail("waitpid failed");
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "{\"event\":\"%s\",\"ok\":false,\"error\":\"fieldmesh-radio-tx-enable failed\",\"child_status\":%d}\n",
                EVENT, status);
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
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

    rc = run_tx_enable(max_duration_ms, tx_attenuation_db);
    if (rc == 0) {
        printf("{\"event\":\"%s\",\"ok\":true,\"request\":\"", EVENT);
        json_escape(stdout, request_path);
        printf("\",\"fixture_id\":\"");
        json_escape(stdout, fixture_id);
        printf("\",\"max_tx_duration_ms\":%ld,\"tx_attenuation_db\":%.6g,\"writes_hardware\":true,\"starts_rf_tx\":true,\"bounded\":true,\"delegated_to\":\"fieldmesh-radio-tx-enable\"}\n",
               max_duration_ms, tx_attenuation_db);
    }

out:
    free(json);
    return rc;
}
