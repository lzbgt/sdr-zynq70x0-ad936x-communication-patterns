#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/sdk"
mkdir -p "$out_dir"

cc="${CC:-cc}"
"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_sdk_header_smoke.c" \
    -c -o "$out_dir/fieldmesh_sdk_header_smoke.o"

echo "fieldmesh_sdk_header_check=pass"
