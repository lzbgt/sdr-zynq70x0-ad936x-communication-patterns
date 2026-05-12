#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${1:-$repo_root/meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c}"
out="${OUT:-$repo_root/.config/fieldmesh/fieldmesh-udp-probe-host}"

mkdir -p "$(dirname "$out")"
cc="${CC:-gcc}"

"$cc" -std=c11 -Wall -Wextra -Werror -O2 "$src" -o "$out"
echo "$out"
