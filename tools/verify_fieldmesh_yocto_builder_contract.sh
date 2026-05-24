#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builder_user="${YOCTO_BUILDER_USER:-yoctobuilder}"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
scripts = [
    repo / "tools/yocto_arm_as_builder.sh",
    repo / "tools/yocto_z103_as_builder.sh",
    repo / "tools/prepare_vendor_source_for_yocto.sh",
]
docs = [
    repo / "docs/yocto-arm-firmware.md",
    repo / "docs/verification.md",
]

for path in scripts:
    text = path.read_text(encoding="utf-8")
    required = [
        'builder_group="${YOCTO_BUILDER_GROUP:-$builder_user}"',
        'getent group "$builder_group"',
        'id -g "$builder_user"',
        "must not use root as its primary group",
        '"$builder_user:$builder_group"',
    ]
    for token in required:
        if token not in text:
            raise SystemExit(f"{path} missing Yocto builder contract token: {token}")
    banned = [
        "useradd -m -g root",
        "$builder_user:root",
        "yoctobuilder:root",
    ]
    for token in banned:
        if token in text:
            raise SystemExit(f"{path} still contains root-primary builder token: {token}")

doc_text = "\n".join(path.read_text(encoding="utf-8") for path in docs)
for token in [
    "useradd -m -g yoctobuilder",
    "primary group `root`",
    "host-user-contaminated",
]:
    if token not in doc_text:
        raise SystemExit(f"Yocto builder docs missing contract token: {token}")

if "useradd -m -g root" in doc_text or "yoctobuilder:root" in doc_text:
    raise SystemExit("Yocto builder docs still recommend root-primary ownership")
PY

if id "$builder_user" >/dev/null 2>&1; then
    if [ "$(id -g "$builder_user")" = "0" ]; then
        echo "$builder_user must not use root as its primary group" >&2
        exit 1
    fi
fi

printf 'fieldmesh_yocto_builder_contract=pass\n'
