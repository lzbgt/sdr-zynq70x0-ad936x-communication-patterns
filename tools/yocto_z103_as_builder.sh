#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${Z103_YOCTO_BUILD_DIR:-$repo_root/yocto/builds/sdr-z103-arm}"
vendor_tree="${SDR_Z103_VENDOR_FW:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
builder_user="${YOCTO_BUILDER_USER:-yoctobuilder}"

if ! id "$builder_user" >/dev/null 2>&1; then
    echo "Missing build user: $builder_user" >&2
    echo "Create it with: useradd -m -g root -s /bin/bash $builder_user" >&2
    exit 1
fi

"$repo_root/tools/setup_z103_yocto_build.sh"

if [ -d "$vendor_tree" ]; then
    chmod -R u+rwX,go+rX "$(dirname "$vendor_tree")"
    if ! su -s /usr/bin/bash "$builder_user" -c "test -w '$vendor_tree/linux' && test -w '$vendor_tree/u-boot-xlnx'" >/dev/null 2>&1; then
        chown -R "$builder_user:root" "$(dirname "$vendor_tree")"
    fi
fi

if [ -d "$repo_root/yocto" ]; then
    if ! su -s /usr/bin/bash "$builder_user" -c "test -w '$repo_root/yocto'" >/dev/null 2>&1; then
        chown -R "$builder_user:root" "$repo_root/yocto"
    fi
fi

if ! su -s /usr/bin/bash "$builder_user" -c "test -w '$build_dir'" >/dev/null 2>&1; then
    chown -R "$builder_user:root" "$build_dir"
fi

su -s /usr/bin/bash "$builder_user" -c \
    "git config --global --add safe.directory '$repo_root' >/dev/null 2>&1 || true"

if [ "$#" -eq 0 ]; then
    set -- bitbake -p
fi

printf -v quoted_cmd ' %q' "$@"

exec su -s /usr/bin/bash "$builder_user" -c "
set -e
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export https_proxy=\"\${https_proxy:-${https_proxy:-}}\"
export HTTPS_PROXY=\"\${HTTPS_PROXY:-${HTTPS_PROXY:-}}\"
cd '$repo_root'
source yocto/layers/poky/oe-init-build-env '$build_dir' >/tmp/sdr-z103-yocto-env-user.log
${quoted_cmd}
"
