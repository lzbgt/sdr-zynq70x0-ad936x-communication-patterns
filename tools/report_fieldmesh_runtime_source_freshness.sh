#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

variant="${1:-all}"
require_current=0
if [[ "${2:-}" == "--require-current" ]]; then
    require_current=1
elif [[ $# -gt 1 ]]; then
    echo "usage: $0 [all|z203|z103] [--require-current]" >&2
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
    local artifact_override_var
    local artifact_label
    local rootfs_tar
    local extracted_strings

    upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    strings_override_var="FIELDMESH_RUNTIME_STRINGS_FILE_${upper}"
    strings_override="${!strings_override_var:-}"
    artifact_override_var="FIELDMESH_RUNTIME_ARTIFACT_${upper}"
    artifact_label="${!artifact_override_var:-$strings_override}"

    if [[ -n "$strings_override" ]]; then
        python3 - "$repo_root" "$name" "$strings_override" "strings_file" "$require_current" "$artifact_label" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
variant = sys.argv[2]
strings_path = Path(sys.argv[3])
artifact_source = sys.argv[4]
require_current = sys.argv[5] == "1"
artifact_label = sys.argv[6]

source = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
artifact = strings_path.read_text(encoding="utf-8", errors="replace")

source_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
)
artifact_tokens = (
    "--fw-dma-status-idle-self-test",
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
)

missing_source = [token for token in source_tokens if token not in source]
missing_artifact = [token for token in artifact_tokens if token not in artifact]
event = {
    "event": "fieldmesh_runtime_source_freshness",
    "variant": variant,
    "artifact": artifact_label,
    "artifact_source": artifact_source,
    "writes_hardware": False,
    "source_has_current_fw_dma_contract": not missing_source,
    "artifact_has_current_fw_dma_contract": not missing_artifact,
    "runtime_rebuild_needed": bool(missing_artifact),
    "missing_source_tokens": missing_source,
    "missing_artifact_tokens": missing_artifact,
    "expected_artifact_token_count": len(artifact_tokens),
}
print(json.dumps(event, sort_keys=True))
if require_current and (missing_source or missing_artifact):
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

    extracted_strings="$(mktemp)"
    tmp_files+=("$extracted_strings")
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-ctrl-write | strings >"$extracted_strings"
    python3 - "$repo_root" "$name" "$extracted_strings" "rootfs_tar" "$require_current" "$rootfs_tar" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
variant = sys.argv[2]
strings_path = Path(sys.argv[3])
artifact_source = sys.argv[4]
require_current = sys.argv[5] == "1"
artifact = sys.argv[6]

source = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
artifact_strings = strings_path.read_text(encoding="utf-8", errors="replace")

source_tokens = (
    "--fw-dma-status-idle-self-test",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
)
artifact_tokens = (
    "--fw-dma-status-idle-self-test",
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
)

missing_source = [token for token in source_tokens if token not in source]
missing_artifact = [token for token in artifact_tokens if token not in artifact_strings]
event = {
    "event": "fieldmesh_runtime_source_freshness",
    "variant": variant,
    "artifact": artifact,
    "artifact_source": artifact_source,
    "writes_hardware": False,
    "source_has_current_fw_dma_contract": not missing_source,
    "artifact_has_current_fw_dma_contract": not missing_artifact,
    "runtime_rebuild_needed": bool(missing_artifact),
    "missing_source_tokens": missing_source,
    "missing_artifact_tokens": missing_artifact,
    "expected_artifact_token_count": len(artifact_tokens),
}
print(json.dumps(event, sort_keys=True))
if require_current and (missing_source or missing_artifact):
    raise SystemExit(1)
PY
    rm -f "$extracted_strings"
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
