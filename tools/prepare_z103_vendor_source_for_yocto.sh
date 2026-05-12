#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_root="${SDR_Z103_VENDOR_FW:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"

exec "$repo_root/tools/prepare_vendor_source_for_yocto.sh" "$vendor_root"
