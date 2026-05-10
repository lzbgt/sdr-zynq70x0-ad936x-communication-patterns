#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$repo_root/yocto/builds/sdr-z203-arm"
builder_user="${YOCTO_BUILDER_USER:-yoctobuilder}"

if ! id "$builder_user" >/dev/null 2>&1; then
    echo "Missing build user: $builder_user" >&2
    echo "Create it with: useradd -m -g root -s /bin/bash $builder_user" >&2
    exit 1
fi

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
source yocto/layers/poky/oe-init-build-env '$build_dir' >/tmp/sdr-z203-yocto-env-user.log
${quoted_cmd}
"

