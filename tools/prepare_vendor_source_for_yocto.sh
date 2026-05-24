#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="${1:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
builder_user="${YOCTO_BUILDER_USER:-yoctobuilder}"
builder_group="${YOCTO_BUILDER_GROUP:-$builder_user}"

if [ ! -d "$vendor_root" ]; then
    echo "Vendor source root not found: $vendor_root" >&2
    exit 1
fi

if ! id "$builder_user" >/dev/null 2>&1; then
    echo "Missing build user: $builder_user" >&2
    echo "Create it with: groupadd -f $builder_group && useradd -m -g $builder_group -s /bin/bash $builder_user" >&2
    exit 1
fi
if ! getent group "$builder_group" >/dev/null 2>&1; then
    echo "Missing build group: $builder_group" >&2
    echo "Create it with: groupadd -f $builder_group" >&2
    exit 1
fi
if [ "$(id -g "$builder_user")" = "0" ]; then
    echo "$builder_user must not use root as its primary group; run: usermod -g $builder_group $builder_user" >&2
    exit 1
fi

chmod -R u+rwX,go+rX "$(dirname "$vendor_root")"
chown -R "$builder_user:$builder_group" "$(dirname "$vendor_root")"

su -s /usr/bin/bash "$builder_user" -c "
set -euo pipefail
make -C '$vendor_root/linux' ARCH=arm mrproper
make -C '$vendor_root/u-boot-xlnx' ARCH=arm distclean
"

"$repo_root/tools/repair_vendor_source_links.sh" "$vendor_root"
chmod -R u+rwX,go+rX "$(dirname "$vendor_root")"
chown -R "$builder_user:$builder_group" "$(dirname "$vendor_root")"
