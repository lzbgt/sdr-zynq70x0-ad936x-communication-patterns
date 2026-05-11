#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hdl_project="${HDL_PROJECT:-$repo_root/.config/vivado-hdl/hdl/projects/pluto}"

bitstream="$hdl_project/pluto.runs/impl_1/system_top.bit"
xsa="$hdl_project/pluto.sdk/system_top.xsa"
timing="$hdl_project/pluto.runs/impl_1/system_top_timing_summary_routed.rpt"
route="$hdl_project/pluto.runs/impl_1/system_top_route_status.rpt"
drc="$hdl_project/pluto.runs/impl_1/system_top_drc_routed.rpt"
log="$hdl_project/pluto_vivado.log"

require_file() {
  if [[ ! -s "$1" ]]; then
    echo "Missing or empty required file: $1" >&2
    exit 1
  fi
}

require_file "$bitstream"
require_file "$xsa"
require_file "$timing"
require_file "$route"
require_file "$drc"
require_file "$log"

if rg -n '^(ERROR:|CRITICAL WARNING: .*Timing Constraints NOT met|.*FAILED$)' "$log" "$hdl_project/pluto.runs/impl_1/runme.log" >/tmp/sdr-z203-hdl-errors.txt; then
  cat /tmp/sdr-z203-hdl-errors.txt >&2
  exit 1
fi

if ! rg -q 'route_design completed successfully|Routing Is Done' "$hdl_project/pluto.runs/impl_1/runme.log"; then
  echo "Implementation route completion marker not found" >&2
  exit 1
fi

if ! rg -q 'write_bitstream completed successfully|write_bitstream Complete|Writing bitstream' "$hdl_project/pluto.runs/impl_1/runme.log"; then
  echo "Bitstream completion marker not found" >&2
  exit 1
fi

echo "HDL project: $hdl_project"
find "$bitstream" "$xsa" "$timing" "$route" "$drc" -maxdepth 0 -printf '%p %s bytes\n'
sha256sum "$bitstream" "$xsa"

if rg -n 'WNS=|Timing constraints are met|All user specified timing constraints are met|VIOLATED|Timing constraints are not met' "$timing" | sed -n '1,40p'; then
  :
fi
