#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-$repo_root/.config/fieldmesh/verify-connected-board-installer}"

rm -rf "$work_dir"
mkdir -p "$work_dir/bin" "$work_dir/out"

cat > "$work_dir/bin/fake_z203_qspi_integrity_fail.sh" <<'EOF_FAKE_DIAG'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?OUT_DIR is required}"
mkdir -p "$out_dir"
cat > "$out_dir/summary.json" <<'EOF_SUMMARY'
{
  "event": "fieldmesh_z203_qspi_integrity_diag",
  "qspi_integrity_pass": false,
  "safe_z203_install_mode": "sd",
  "diagnosis": "synthetic failed integrity gate for installer refusal verification"
}
EOF_SUMMARY
echo fieldmesh_fake_z203_qspi_integrity=fail
EOF_FAKE_DIAG

cat > "$work_dir/bin/fake_pluto_frm_install.sh" <<'EOF_FAKE_INSTALL'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected installer call: $*" >> "${FIELDMESH_FAKE_INSTALL_MARKER:?missing marker path}"
exit 77
EOF_FAKE_INSTALL

chmod +x "$work_dir/bin/fake_z203_qspi_integrity_fail.sh" "$work_dir/bin/fake_pluto_frm_install.sh"

set +e
APPLY=1 \
ALLOW_FLASH_WRITES=1 \
Z203_INSTALL_MODE=qspi \
REBOOT_AFTER=0 \
Z203_IP=192.0.2.203 \
Z103_IP=192.0.2.103 \
OUT_DIR="$work_dir/out/install-refusal" \
DIAGNOSE_Z203_QSPI_INTEGRITY_SH="$work_dir/bin/fake_z203_qspi_integrity_fail.sh" \
INSTALL_FIELDMESH_PLUTO_FRM_SH="$work_dir/bin/fake_pluto_frm_install.sh" \
FIELDMESH_FAKE_INSTALL_MARKER="$work_dir/fake-install-called.txt" \
    "$repo_root/tools/install_fieldmesh_connected_boards.sh" \
    > "$work_dir/refusal.stdout" 2> "$work_dir/refusal.stderr"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
    echo "installer unexpectedly passed forced Z203 QSPI failure" >&2
    exit 1
fi
if [ -e "$work_dir/fake-install-called.txt" ]; then
    echo "installer started a board package update after Z203 QSPI refusal" >&2
    cat "$work_dir/fake-install-called.txt" >&2
    exit 1
fi
if [ -e "$work_dir/out/install-refusal/z103_install.log" ]; then
    echo "installer created z103_install.log before refusing Z203 QSPI" >&2
    exit 1
fi
if [ -e "$work_dir/out/install-refusal/resolved_plan.json" ]; then
    echo "installer wrote resolved_plan.json for a refused forced-QSPI plan" >&2
    exit 1
fi
python3 - "$work_dir/out/install-refusal/plan.json" "$work_dir/out/install-refusal/z203-qspi-integrity-precheck/summary.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if plan.get("z203_damaged_qspi_override_supported") is not False:
    raise SystemExit("normal installer must not support damaged Z203 QSPI override")
if plan.get("z203_install_mode") != "qspi":
    raise SystemExit("test did not exercise forced qspi mode")
if summary.get("qspi_integrity_pass") is not False:
    raise SystemExit("synthetic integrity gate did not fail")
PY
grep -q "refusing normal QSPI install before starting any board update" "$work_dir/refusal.stderr"

echo "fieldmesh_connected_board_installer_refusal_guard=pass"
