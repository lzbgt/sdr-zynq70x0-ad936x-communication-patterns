#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="$repo_root/.config/fieldmesh/imgui-control-build"
out_dir="$repo_root/.config/fieldmesh/imgui-control-check"

make -C "$app_dir" \
    BUILD_DIR="$build_dir" \
    OUT_DIR="$out_dir" \
    clean all check

SKIP_BUILD=1 \
    BUILD_DIR="$build_dir" \
    OUT_DIR="$out_dir/two-instances" \
    "$repo_root/tools/run_fieldmesh_two_imgui_instances.sh" >/dev/null

if [ -S /tmp/.X11-unix/X0 ] || [ -S /mnt/wslg/.X11-unix/X0 ]; then
    "$repo_root/tools/run_fieldmesh_imgui_wslg.sh" --check-bridge >/dev/null
fi

echo "fieldmesh_imgui_app_check=pass"
