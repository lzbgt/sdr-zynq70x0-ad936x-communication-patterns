#!/usr/bin/env bash
set -euo pipefail

vivado_root="${VIVADO_ROOT:-/opt/Xilinx/2025.1/Vivado}"
settings="$vivado_root/settings64.sh"
license_path="${XILINXD_LICENSE_FILE:-/opt/Xilinx/licenses/vivado_lic2037.lic:/opt/Xilinx/licenses/xilinx_ise_vivado.lic:/opt/Xilinx/licenses/vivado2018+IPs.lic}"

if [[ ! -r "$settings" ]]; then
  echo "Vivado settings file not found: $settings" >&2
  exit 1
fi

if [[ ! -e /usr/lib/libtinfo.so.5 ]]; then
  cat >&2 <<'EOF'
Missing /usr/lib/libtinfo.so.5.

On this Arch WSL host the verified compatibility fix is:

  ln -s /usr/lib/libtinfo.so.6 /usr/lib/libtinfo.so.5

EOF
  exit 1
fi

export XILINXD_LICENSE_FILE="$license_path"

# shellcheck disable=SC1090
source "$settings"

echo "XILINXD_LICENSE_FILE=$XILINXD_LICENSE_FILE"
echo "vivado=$(command -v vivado)"
echo "bootgen=$(command -v bootgen)"
if command -v xsct >/dev/null 2>&1; then
  echo "xsct=$(command -v xsct)"
else
  echo "xsct=not installed"
fi

vivado -version
bootgen -help >/dev/null

tmp_tcl="$(mktemp /tmp/vivado-empty-XXXXXX.tcl)"
trap 'rm -f "$tmp_tcl"' EXIT

vivado -mode batch -source "$tmp_tcl" -nojournal -nolog -notrace
