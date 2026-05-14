#!/bin/sh

fm_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

fm_error() {
    event="$1"
    message="$2"
    printf '{"event":"%s","ok":false,"error":"%s"}\n' \
        "$event" "$(fm_json_escape "$message")" >&2
    exit 1
}

fm_require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fm_error "$2" "missing command: $1"
}

fm_float_ge() {
    awk "BEGIN { exit !(($1) >= ($2)) }"
}

fm_require_live_hardware() {
    event="$1"
    [ "${FIELD_MESH_EXECUTE_LIVE_TX:-0}" = "1" ] ||
        fm_error "$event" "FIELD_MESH_EXECUTE_LIVE_TX=1 is required"
    [ "${FIELD_MESH_ALLOW_HARDWARE_WRITES:-0}" = "1" ] ||
        fm_error "$event" "FIELD_MESH_ALLOW_HARDWARE_WRITES=1 is required"
    [ -n "${FIELD_MESH_FIXTURE_ID:-}" ] ||
        fm_error "$event" "FIELD_MESH_FIXTURE_ID is required"
    [ -n "${FIELD_MESH_FIXTURE_ATTENUATION_DB:-}" ] ||
        fm_error "$event" "FIELD_MESH_FIXTURE_ATTENUATION_DB is required"
    fm_require_cmd awk "$event"
    fm_float_ge "$FIELD_MESH_FIXTURE_ATTENUATION_DB" 30 ||
        fm_error "$event" "fixture attenuation must be >= 30 dB"
}

fm_require_live_rf() {
    event="$1"
    fm_require_live_hardware "$event"
    [ "${FIELD_MESH_ALLOW_RF_TX:-0}" = "1" ] ||
        fm_error "$event" "FIELD_MESH_ALLOW_RF_TX=1 is required"
    [ -n "${FIELD_MESH_MAX_TX_DURATION_MS:-}" ] ||
        fm_error "$event" "FIELD_MESH_MAX_TX_DURATION_MS is required"
}

fm_iio_attr() {
    event="$1"
    shift
    if [ "${FIELD_MESH_BACKEND_DRY_RUN:-0}" = "1" ]; then
        printf '{"event":"%s_command","ok":true,"dry_run":true,"argv":"%s"}\n' \
            "$event" "$(fm_json_escape "iio_attr $*")"
        return 0
    fi
    fm_require_cmd iio_attr "$event"
    iio_attr "$@"
}

fm_sleep_ms() {
    event="$1"
    duration_ms="$2"
    if [ "${FIELD_MESH_BACKEND_DRY_RUN:-0}" = "1" ]; then
        printf '{"event":"%s_sleep","ok":true,"dry_run":true,"duration_ms":%s}\n' \
            "$event" "$duration_ms"
        return 0
    fi
    if command -v usleep >/dev/null 2>&1; then
        usleep "$((duration_ms * 1000))"
        return 0
    fi
    if command -v busybox >/dev/null 2>&1 && busybox usleep 1000 >/dev/null 2>&1; then
        busybox usleep "$((duration_ms * 1000))"
        return 0
    fi
    fm_error "$event" "bounded millisecond sleep requires usleep or busybox usleep"
}
