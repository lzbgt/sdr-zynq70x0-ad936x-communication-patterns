#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" "$@"
