#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hdl_project="${HDL_PROJECT:-$repo_root/.config/z103-vivado-hdl/hdl/projects/pluto}"

HDL_PROJECT="$hdl_project" "$repo_root/tools/verify_pluto_hdl_build.sh"
