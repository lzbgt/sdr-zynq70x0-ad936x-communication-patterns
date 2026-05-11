#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/yocto/builds/sdr-z203-arm/fit-work-vivado}"
hdl_project="${HDL_PROJECT:-$repo_root/.config/vivado-hdl/hdl/projects/pluto}"
bitstream="$hdl_project/pluto.runs/impl_1/system_top.bit"

export PATH="$repo_root/tools:$PATH"

run_arm="${RUN_ARM:-1}"
run_fpga="${RUN_FPGA:-1}"
run_audit="${RUN_AUDIT:-1}"
run_boot="${RUN_BOOT:-1}"

if [[ "$run_arm" == "1" ]]; then
  "$repo_root/tools/yocto_arm_as_builder.sh" bitbake sdr-z203-arm-image
fi

if [[ "$run_fpga" == "1" ]]; then
  "$repo_root/tools/build_pluto_hdl_vivado.sh"
fi

"$repo_root/tools/verify_pluto_hdl_build.sh"

if [[ "$run_audit" == "1" ]]; then
  "$repo_root/tools/audit_yocto_rootfs.sh"
fi

BITSTREAM="$bitstream" OUT_DIR="$out_dir" "$repo_root/tools/package_yocto_pluto_frm.sh"

if [[ "$run_boot" == "1" ]]; then
  "$repo_root/tools/build_sdr_z203_boot_artifacts.sh"
fi

echo
echo "Combined ARM+FPGA firmware package:"
find "$out_dir/build" -maxdepth 1 -type f \( -name 'pluto.itb' -o -name 'pluto.frm' -o -name 'pluto.frm.md5' \) -printf '%p %s bytes\n' | sort
sha256sum "$out_dir/build/pluto.itb" "$out_dir/build/pluto.frm"

echo
echo "Verified flash path for this board:"
echo "  sshpass -p '' scp -O $out_dir/build/pluto.frm root@192.168.2.1:/tmp/pluto.frm"
echo "  sshpass -p '' ssh root@192.168.2.1 '/sbin/update_frm.sh /tmp/pluto.frm && sync && reboot'"
echo
echo "Bootloader artifacts are generated under .config/boot-artifacts/boot."
echo "They are not flashed by this script."
