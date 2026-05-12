#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="${1:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
builder_user="${YOCTO_BUILDER_USER:-yoctobuilder}"

if [ ! -d "$vendor_root" ]; then
    echo "Vendor source root not found: $vendor_root" >&2
    exit 1
fi

if ! id "$builder_user" >/dev/null 2>&1; then
    echo "Missing build user: $builder_user" >&2
    echo "Create it with: useradd -m -g root -s /bin/bash $builder_user" >&2
    exit 1
fi

chmod -R u+rwX,go+rX "$(dirname "$vendor_root")"
chown -R "$builder_user:root" "$(dirname "$vendor_root")"

su -s /usr/bin/bash "$builder_user" -c "
set -euo pipefail
make -C '$vendor_root/linux' ARCH=arm mrproper
make -C '$vendor_root/u-boot-xlnx' ARCH=arm distclean
"

"$repo_root/tools/repair_vendor_source_links.sh" "$vendor_root"
chmod -R u+rwX,go+rX "$(dirname "$vendor_root")"
chown -R "$builder_user:root" "$(dirname "$vendor_root")"
