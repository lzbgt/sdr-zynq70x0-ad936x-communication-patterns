#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-}"
board_ip="${BOARD_IP:-${2:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
reboot_after="${REBOOT_AFTER:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/frm-install-$variant-$(date +%Y%m%d-%H%M%S)}"

case "$variant" in
  z203)
    frm="${FRM:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.frm}"
    expected_mode="2r2t"
    expected_hint="z203|z7020|2r2t"
    ;;
  z103)
    frm="${FRM:-$repo_root/.config/fieldmesh/runtime-package-z103/fit-work/build/pluto.frm}"
    expected_mode="1r1t"
    expected_hint="z103|z7010|ad9363|1r1t"
    ;;
  *)
    echo "usage: $0 <z203|z103> [board-ip]" >&2
    exit 2
    ;;
esac

if [[ ! -f "$frm" ]]; then
  echo "Missing FieldMesh package: $frm" >&2
  exit 1
fi
if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing required command: sshpass" >&2
  exit 1
fi

mkdir -p "$out_dir"
remote="${ssh_user}@${board_ip}"
remote_frm="/tmp/fieldmesh-${variant}.frm"
remote_itb="/tmp/fieldmesh-${variant}.itb"
itb="${FRM_ITB:-${frm%.frm}.itb}"
ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

sha256sum "$frm" > "$out_dir/package.sha256"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" '
  set -e
  echo "fieldmesh_frm_identity_begin"
  echo "hostname=$(hostname 2>/dev/null || true)"
  echo "uname=$(uname -a 2>/dev/null || true)"
  printf "model="
  cat /proc/device-tree/model 2>/dev/null | tr "\000" " " || true
  echo
  fw_printenv hostname mode ipaddr ipaddr_host netmask fit_size 2>/dev/null || true
  cat /proc/mtd 2>/dev/null || true
  if [ -x /sbin/update_frm.sh ]; then
    echo "update_frm=present"
  else
    echo "update_frm=missing"
  fi
  if command -v fieldmeshctl >/dev/null 2>&1; then
    echo "fieldmeshctl=present"
  else
    echo "fieldmeshctl=missing"
  fi
  echo "fieldmesh_frm_identity_end"
' > "$out_dir/identity.txt"

if ! grep -qiE "(^mode=${expected_mode}$|${expected_hint})" "$out_dir/identity.txt"; then
  echo "Reachable board identity does not match expected $variant" >&2
  cat "$out_dir/identity.txt" >&2
  exit 1
fi
if ! grep -q '^update_frm=present$' "$out_dir/identity.txt"; then
  echo "Reachable board is missing /sbin/update_frm.sh" >&2
  exit 1
fi
if ! grep -Eq 'mtd3: .*"qspi-linux"' "$out_dir/identity.txt"; then
  echo "Reachable board did not expose mtd3 qspi-linux" >&2
  exit 1
fi

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_frm_install_plan","variant":"$variant","host":"$board_ip","frm":"$frm","remote_frm":"$remote_frm","apply":$apply,"allow_flash_writes":$allow_flash,"reboot_after":$reboot_after}
EOF_PLAN

if [[ "$apply" != "1" ]]; then
  cat "$out_dir/plan.json"
  echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 to flash mtd3." >&2
  echo "Capture directory: $out_dir" >&2
  exit 0
fi
if [[ "$allow_flash" != "1" ]]; then
  cat "$out_dir/plan.json"
  echo "Refusing flash write without ALLOW_FLASH_WRITES=1" >&2
  exit 1
fi

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" -O "$frm" "$remote:$remote_frm"
set +e
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "set -e; sha256sum '$remote_frm' 2>/dev/null || md5sum '$remote_frm'; /sbin/update_frm.sh '$remote_frm'; fw_printenv fit_size mode ipaddr ipaddr_host 2>/dev/null || true; sync" \
  > "$out_dir/update_frm.log"
update_rc=$?
set -e
if [[ "$update_rc" -ne 0 ]] || grep -qE '(^|[[:space:]])Failed([[:space:]]|$)' "$out_dir/update_frm.log"; then
  if [[ -f "$itb" ]]; then
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" -O "$itb" "$remote:$remote_itb"
    set +e
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
      "set -e; command -v flashcp >/dev/null; sha256sum '$remote_itb' 2>/dev/null || md5sum '$remote_itb'; flashcp -v '$remote_itb' /dev/mtd3; sync" \
      > "$out_dir/flashcp.log" 2>&1
    flashcp_rc=$?
    set -e
    if [[ "$flashcp_rc" -ne 0 ]]; then
      cat "$out_dir/update_frm.log" >&2
      cat "$out_dir/flashcp.log" >&2
      echo "Firmware install failed: update_frm_rc=$update_rc flashcp_rc=$flashcp_rc" >&2
      exit 1
    fi
  else
    cat "$out_dir/update_frm.log" >&2
    echo "Firmware install failed and missing FIT fallback: $itb" >&2
    exit 1
  fi
fi

if [[ "$reboot_after" == "1" ]]; then
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "sync; reboot" \
    > "$out_dir/reboot.log" 2>&1 || true
fi

echo "fieldmesh_frm_install=$variant"
echo "Capture directory: $out_dir"
