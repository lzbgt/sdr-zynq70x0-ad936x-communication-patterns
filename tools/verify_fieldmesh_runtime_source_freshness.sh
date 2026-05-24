#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

fresh_strings="$work_dir/fresh_strings.txt"
stale_strings="$work_dir/stale_strings.txt"
report="$work_dir/report.ndjson"

cat >"$fresh_strings" <<'EOF'
fieldmesh_ctrl_write
--fw-dma-config-if-idle
--fw-dma-arm-if-ready
--fw-dma-stop-if-active
--fw-dma-status-idle-self-test
--fw-dma-action-policy-self-test
firmware_dma_not_idle
firmware_dma_not_ready_for_arm
fault_free
drop_counters_clear
idle
stop_needed
ready_for_arm
config_allowed
arm_allowed
stop_write_needed
EOF

cat >"$stale_strings" <<'EOF'
fieldmesh_ctrl_write
--fw-dma-config
--fw-dma-arm
--fw-dma-stop
fault_free
EOF

FIELDMESH_RUNTIME_STRINGS_FILE_Z203="$stale_strings" \
FIELDMESH_RUNTIME_ARTIFACT_Z203="/tmp/z203.rootfs.tar.gz" \
FIELDMESH_RUNTIME_STRINGS_FILE_Z103="$fresh_strings" \
FIELDMESH_RUNTIME_ARTIFACT_Z103="/tmp/z103.rootfs.tar.gz" \
    "$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" all >"$report"

python3 - "$report" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line]
if len(rows) != 2:
    raise SystemExit(f"expected two freshness rows, got {len(rows)}")

by_variant = {row.get("variant"): row for row in rows}
for variant in ("z203", "z103"):
    if variant not in by_variant:
        raise SystemExit(f"missing {variant} freshness row: {rows!r}")
    row = by_variant[variant]
    if row.get("event") != "fieldmesh_runtime_source_freshness":
        raise SystemExit(f"{variant}: bad event: {row!r}")
    if row.get("writes_hardware") is not False:
        raise SystemExit(f"{variant}: freshness report must be read-only: {row!r}")
    if row.get("artifact_source") != "strings_file":
        raise SystemExit(f"{variant}: fixture report did not use strings_file: {row!r}")
    if row.get("artifact") != f"/tmp/{variant}.rootfs.tar.gz":
        raise SystemExit(f"{variant}: fixture report did not preserve artifact label: {row!r}")
    if row.get("source_has_current_fw_dma_contract") is not True:
        raise SystemExit(f"{variant}: source contract is stale: {row!r}")

stale = by_variant["z203"]
if stale.get("artifact_has_current_fw_dma_contract") is not False:
    raise SystemExit(f"z203 stale fixture was not detected: {stale!r}")
if stale.get("runtime_rebuild_needed") is not True:
    raise SystemExit(f"z203 stale fixture did not request rebuild: {stale!r}")
for token in ("--fw-dma-config-if-idle", "--fw-dma-arm-if-ready",
              "--fw-dma-stop-if-active", "--fw-dma-status-idle-self-test",
              "--fw-dma-action-policy-self-test",
              "firmware_dma_not_ready_for_arm", "config_allowed",
              "arm_allowed", "stop_write_needed"):
    if token not in stale.get("missing_artifact_tokens", []):
        raise SystemExit(f"z203 stale fixture missing expected missing token {token}: {stale!r}")

fresh = by_variant["z103"]
if fresh.get("artifact_has_current_fw_dma_contract") is not True:
    raise SystemExit(f"z103 fresh fixture was not accepted: {fresh!r}")
if fresh.get("runtime_rebuild_needed") is not False:
    raise SystemExit(f"z103 fresh fixture incorrectly requested rebuild: {fresh!r}")
if fresh.get("missing_artifact_tokens") != []:
    raise SystemExit(f"z103 fresh fixture reported missing tokens: {fresh!r}")
PY

FIELDMESH_RUNTIME_STRINGS_FILE_Z203="$stale_strings" \
    "$repo_root/tools/report_fieldmesh_runtime_source_freshness.sh" z203 --require-current \
    >"$work_dir/require_current.json" 2>"$work_dir/require_current.err" && {
        echo "freshness reporter --require-current accepted stale runtime strings" >&2
        exit 1
    }

python3 - "$repo_root/tools/verify_fieldmesh_runtime_artifacts.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "report_fieldmesh_runtime_source_freshness.sh",
    "FIELDMESH_RUNTIME_STRINGS_FILE_Z203",
    "FIELDMESH_RUNTIME_STRINGS_FILE_Z103",
    "FIELDMESH_RUNTIME_ARTIFACT_Z203",
    "FIELDMESH_RUNTIME_ARTIFACT_Z103",
    "FIELDMESH_REQUIRE_CURRENT_FW_DMA_RUNTIME",
    "require_current_fw_dma_runtime",
    "freshness_args+=(\"--require-current\")",
    "env \"$freshness_env\"",
]
for token in required:
    if token not in script:
        raise SystemExit(f"runtime artifact verifier missing freshness token: {token}")
if script.index("tar -xOf \"$rootfs_tar\" ./usr/bin/fieldmesh-ctrl-write") > script.index("report_fieldmesh_runtime_source_freshness.sh"):
    raise SystemExit("runtime artifact verifier must extract fieldmesh-ctrl-write strings before freshness report")
PY

printf 'fieldmesh_runtime_source_freshness=pass\n'
