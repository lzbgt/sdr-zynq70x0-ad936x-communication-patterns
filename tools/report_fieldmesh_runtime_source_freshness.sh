#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

variant="${1:-all}"
require_mode="none"
if [[ "${2:-}" == "--require-current" ]]; then
    require_mode="all"
elif [[ "${2:-}" == "--require-current-fw-dma" ]]; then
    require_mode="fw_dma"
elif [[ "${2:-}" == "--require-current-rf-guard" ]]; then
    require_mode="rf_guard"
elif [[ "${2:-}" == "--require-current-sidecar-addr" ]]; then
    require_mode="sidecar_addr"
elif [[ $# -gt 1 ]]; then
    echo "usage: $0 [all|z203|z103] [--require-current|--require-current-fw-dma|--require-current-rf-guard|--require-current-sidecar-addr]" >&2
    exit 2
fi

tmp_files=()
cleanup() {
    if [[ ${#tmp_files[@]} -gt 0 ]]; then
        rm -f "${tmp_files[@]}"
    fi
}
trap cleanup EXIT

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

report_variant() {
    local name="$1"
    local upper
    local strings_override_var
    local strings_override
    local udp_strings_override_var
    local udp_strings_override
    local artifact_override_var
    local artifact_label
    local rootfs_tar
    local extracted_ctrl_strings
    local extracted_udp_strings

    upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    strings_override_var="FIELDMESH_RUNTIME_STRINGS_FILE_${upper}"
    strings_override="${!strings_override_var:-}"
    udp_strings_override_var="FIELDMESH_RUNTIME_UDP_PROBE_STRINGS_FILE_${upper}"
    udp_strings_override="${!udp_strings_override_var:-}"
    artifact_override_var="FIELDMESH_RUNTIME_ARTIFACT_${upper}"
    artifact_label="${!artifact_override_var:-$strings_override}"

    if [[ -n "$strings_override" ]]; then
        if [[ -z "$udp_strings_override" ]]; then
            udp_strings_override="$strings_override"
        fi
        python3 - "$repo_root" "$name" "$strings_override" "$udp_strings_override" "strings_file" "$require_mode" "$artifact_label" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
variant = sys.argv[2]
ctrl_strings_path = Path(sys.argv[3])
udp_strings_path = Path(sys.argv[4])
artifact_source = sys.argv[5]
require_mode = sys.argv[6]
artifact_label = sys.argv[7]

ctrl_source = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
rf_guard_source = (
    (repo / "sdk/c/include/fieldmesh_rf_guard_ctrl.h").read_text(encoding="utf-8") +
    (repo / "meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")
)
ctrl_artifact = ctrl_strings_path.read_text(encoding="utf-8", errors="replace")
udp_artifact = udp_strings_path.read_text(encoding="utf-8", errors="replace")

fw_dma_source_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "default firmware-DMA BASE",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
)
fw_dma_artifact_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "default firmware-DMA BASE",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "stop_needed",
    "ready_for_arm",
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
)
rf_guard_source_tokens = (
    "fieldmesh_rf_guard_control_tx_enabled",
    "fieldmesh_rf_guard_control_tx_armed",
    "fieldmesh_rf_guard_control_schedule_enabled",
    "fieldmesh_rf_guard_status_tx_enabled",
    "fieldmesh_rf_guard_status_tx_armed",
    "fieldmesh_rf_guard_status_schedule_enabled",
    "fieldmesh_rf_guard_status_reserved",
    "fieldmesh_rf_guard_drop_counters_clear",
    "fieldmesh_rf_guard_status_fault_free",
    "fieldmesh_rf_guard_dac_source_selected",
    "fieldmesh_rf_guard_dac_active",
)
rf_guard_artifact_tokens = (
    "control_tx_enabled",
    "control_tx_armed",
    "control_schedule_enabled",
    "control_armed",
    "status_tx_enabled",
    "status_tx_armed",
    "status_schedule_enabled",
    "status_fault",
    "status_reserved",
    "drop_counters_clear",
    "fault_free",
    "dac_source_selected",
    "dac_active",
)
sidecar_addr_source_tokens = (
    "fieldmesh_sidecar_addr_self_test",
    "sidecar-addr-self-test",
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "FIELDMESH_SIDECAR_TX_DMA_BASE",
    "FIELDMESH_SIDECAR_RX_DMA_BASE",
    "FIELDMESH_SIDECAR_FIRMWARE_RING_BASE",
    "fieldmesh_sidecar_addr_default_map_valid",
)
sidecar_addr_artifact_tokens = (
    "sidecar-addr-self-test",
    "fieldmesh_sidecar_addr_self_test",
    "native_c_contract",
    "firmware_ring_base",
    "writes_hardware",
)

missing_fw_dma_source = [token for token in fw_dma_source_tokens if token not in ctrl_source]
missing_fw_dma_artifact = [token for token in fw_dma_artifact_tokens if token not in ctrl_artifact]
missing_rf_guard_source = [token for token in rf_guard_source_tokens if token not in rf_guard_source]
missing_rf_guard_artifact = [token for token in rf_guard_artifact_tokens if token not in udp_artifact]
missing_sidecar_addr_source = [token for token in sidecar_addr_source_tokens if token not in rf_guard_source]
missing_sidecar_addr_artifact = [token for token in sidecar_addr_artifact_tokens if token not in udp_artifact]
missing_source = missing_fw_dma_source + missing_rf_guard_source + missing_sidecar_addr_source
missing_artifact = missing_fw_dma_artifact + missing_rf_guard_artifact + missing_sidecar_addr_artifact
event = {
    "event": "fieldmesh_runtime_source_freshness",
    "variant": variant,
    "artifact": artifact_label,
    "artifact_source": artifact_source,
    "writes_hardware": False,
    "source_has_current_fw_dma_contract": not missing_fw_dma_source,
    "artifact_has_current_fw_dma_contract": not missing_fw_dma_artifact,
    "source_has_current_rf_guard_contract": not missing_rf_guard_source,
    "artifact_has_current_rf_guard_contract": not missing_rf_guard_artifact,
    "source_has_current_sidecar_addr_contract": not missing_sidecar_addr_source,
    "artifact_has_current_sidecar_addr_contract": not missing_sidecar_addr_artifact,
    "runtime_rebuild_needed": bool(missing_artifact),
    "missing_source_tokens": missing_source,
    "missing_artifact_tokens": missing_artifact,
    "expected_artifact_token_count": len(fw_dma_artifact_tokens) + len(rf_guard_artifact_tokens) + len(sidecar_addr_artifact_tokens),
    "expected_fw_dma_artifact_token_count": len(fw_dma_artifact_tokens),
    "expected_rf_guard_artifact_token_count": len(rf_guard_artifact_tokens),
    "expected_sidecar_addr_artifact_token_count": len(sidecar_addr_artifact_tokens),
}
print(json.dumps(event, sort_keys=True))
if (
    (require_mode == "all" and (missing_source or missing_artifact)) or
    (require_mode == "fw_dma" and (missing_fw_dma_source or missing_fw_dma_artifact)) or
    (require_mode == "rf_guard" and (missing_rf_guard_source or missing_rf_guard_artifact)) or
    (require_mode == "sidecar_addr" and (missing_sidecar_addr_source or missing_sidecar_addr_artifact))
):
    raise SystemExit(1)
PY
        return
    fi

    fieldmesh_resolve_image_paths "$name" "$repo_root"
    rootfs_tar="$FIELDMESH_ROOTFS_TAR"
    if [[ ! -f "$rootfs_tar" ]]; then
        echo "Missing rootfs tar for $name: $rootfs_tar" >&2
        exit 1
    fi

    extracted_ctrl_strings="$(mktemp)"
    extracted_udp_strings="$(mktemp)"
    tmp_files+=("$extracted_ctrl_strings" "$extracted_udp_strings")
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-ctrl-write | strings >"$extracted_ctrl_strings"
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-udp-probe | strings >"$extracted_udp_strings"
    python3 - "$repo_root" "$name" "$extracted_ctrl_strings" "$extracted_udp_strings" "rootfs_tar" "$require_mode" "$rootfs_tar" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
variant = sys.argv[2]
ctrl_strings_path = Path(sys.argv[3])
udp_strings_path = Path(sys.argv[4])
artifact_source = sys.argv[5]
require_mode = sys.argv[6]
artifact = sys.argv[7]

ctrl_source = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
rf_guard_source = (
    (repo / "sdk/c/include/fieldmesh_rf_guard_ctrl.h").read_text(encoding="utf-8") +
    (repo / "meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c").read_text(encoding="utf-8")
)
ctrl_artifact = ctrl_strings_path.read_text(encoding="utf-8", errors="replace")
udp_artifact = udp_strings_path.read_text(encoding="utf-8", errors="replace")

fw_dma_source_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
)
fw_dma_artifact_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "stop_needed",
    "ready_for_arm",
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
)
rf_guard_source_tokens = (
    "fieldmesh_rf_guard_control_tx_enabled",
    "fieldmesh_rf_guard_control_tx_armed",
    "fieldmesh_rf_guard_control_schedule_enabled",
    "fieldmesh_rf_guard_status_tx_enabled",
    "fieldmesh_rf_guard_status_tx_armed",
    "fieldmesh_rf_guard_status_schedule_enabled",
    "fieldmesh_rf_guard_status_reserved",
    "fieldmesh_rf_guard_drop_counters_clear",
    "fieldmesh_rf_guard_status_fault_free",
    "fieldmesh_rf_guard_dac_source_selected",
    "fieldmesh_rf_guard_dac_active",
)
rf_guard_artifact_tokens = (
    "control_tx_enabled",
    "control_tx_armed",
    "control_schedule_enabled",
    "control_armed",
    "status_tx_enabled",
    "status_tx_armed",
    "status_schedule_enabled",
    "status_fault",
    "status_reserved",
    "drop_counters_clear",
    "fault_free",
    "dac_source_selected",
    "dac_active",
)
sidecar_addr_source_tokens = (
    "fieldmesh_sidecar_addr_self_test",
    "sidecar-addr-self-test",
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "FIELDMESH_SIDECAR_TX_DMA_BASE",
    "FIELDMESH_SIDECAR_RX_DMA_BASE",
    "FIELDMESH_SIDECAR_FIRMWARE_RING_BASE",
    "fieldmesh_sidecar_addr_default_map_valid",
)
sidecar_addr_artifact_tokens = (
    "sidecar-addr-self-test",
    "fieldmesh_sidecar_addr_self_test",
    "native_c_contract",
    "firmware_ring_base",
    "writes_hardware",
)

missing_fw_dma_source = [token for token in fw_dma_source_tokens if token not in ctrl_source]
missing_fw_dma_artifact = [token for token in fw_dma_artifact_tokens if token not in ctrl_artifact]
missing_rf_guard_source = [token for token in rf_guard_source_tokens if token not in rf_guard_source]
missing_rf_guard_artifact = [token for token in rf_guard_artifact_tokens if token not in udp_artifact]
missing_sidecar_addr_source = [token for token in sidecar_addr_source_tokens if token not in rf_guard_source]
missing_sidecar_addr_artifact = [token for token in sidecar_addr_artifact_tokens if token not in udp_artifact]
missing_source = missing_fw_dma_source + missing_rf_guard_source + missing_sidecar_addr_source
missing_artifact = missing_fw_dma_artifact + missing_rf_guard_artifact + missing_sidecar_addr_artifact
event = {
    "event": "fieldmesh_runtime_source_freshness",
    "variant": variant,
    "artifact": artifact,
    "artifact_source": artifact_source,
    "writes_hardware": False,
    "source_has_current_fw_dma_contract": not missing_fw_dma_source,
    "artifact_has_current_fw_dma_contract": not missing_fw_dma_artifact,
    "source_has_current_rf_guard_contract": not missing_rf_guard_source,
    "artifact_has_current_rf_guard_contract": not missing_rf_guard_artifact,
    "source_has_current_sidecar_addr_contract": not missing_sidecar_addr_source,
    "artifact_has_current_sidecar_addr_contract": not missing_sidecar_addr_artifact,
    "runtime_rebuild_needed": bool(missing_artifact),
    "missing_source_tokens": missing_source,
    "missing_artifact_tokens": missing_artifact,
    "expected_artifact_token_count": len(fw_dma_artifact_tokens) + len(rf_guard_artifact_tokens) + len(sidecar_addr_artifact_tokens),
    "expected_fw_dma_artifact_token_count": len(fw_dma_artifact_tokens),
    "expected_rf_guard_artifact_token_count": len(rf_guard_artifact_tokens),
    "expected_sidecar_addr_artifact_token_count": len(sidecar_addr_artifact_tokens),
}
print(json.dumps(event, sort_keys=True))
if (
    (require_mode == "all" and (missing_source or missing_artifact)) or
    (require_mode == "fw_dma" and (missing_fw_dma_source or missing_fw_dma_artifact)) or
    (require_mode == "rf_guard" and (missing_rf_guard_source or missing_rf_guard_artifact)) or
    (require_mode == "sidecar_addr" and (missing_sidecar_addr_source or missing_sidecar_addr_artifact))
):
    raise SystemExit(1)
PY
    rm -f "$extracted_ctrl_strings" "$extracted_udp_strings"
}

require_cmd python3
require_cmd tar
require_cmd strings

case "$variant" in
    all)
        report_variant z203
        report_variant z103
        ;;
    z203|z103)
        report_variant "$variant"
        ;;
    *)
        echo "usage: $0 [all|z203|z103] [--require-current]" >&2
        exit 2
        ;;
esac
