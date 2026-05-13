#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/tun-apply-run"
sdk_dir="$repo_root/.config/fieldmesh/sdk"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_sdk.sh" > "$work_dir/sdk_verify.log"

"$repo_root/tools/fieldmesh_tun_apply_run.py" \
  --tun-gateway-report "$sdk_dir/fieldmesh_tun_gateway_demo.ndjson" \
  --out-dir "$work_dir/run" \
  > "$work_dir/run_stdout.json"

python3 - "$work_dir/run/fieldmesh_tun_apply_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_tun_apply_run" or report.get("ok") is not True:
    raise SystemExit(f"bad TUN apply report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("default TUN apply runner must be dry-run")
if report.get("adapter_name") != "swarm0":
    raise SystemExit("TUN apply runner planned the wrong adapter")
if report.get("dst_device_eui") != "020000000103":
    raise SystemExit("TUN apply runner planned the wrong destination EUI")
if report.get("route_kind") != 1 or report.get("selected_mode") != 4:
    raise SystemExit("TUN apply runner did not preserve direct scheduled route")
safety = report["safety"]
for key in ("executes_commands", "writes_network", "allow_network_writes",
            "target_is_zynq_board", "cap_net_admin_confirmed", "uses_iio",
            "uses_tap", "uses_inter_board_ip_routing"):
    if safety[key] is not False:
        raise SystemExit(f"default safety key {key} must be false")
pre_names = [row["name"] for row in report["pre_state_commands"]]
if pre_names != [
    "pre_check_uid",
    "pre_check_tun_device",
    "pre_link_state",
    "pre_addr_state",
    "pre_route_state",
]:
    raise SystemExit(f"unexpected pre-state commands: {pre_names}")
apply_names = [row["name"] for row in report["apply_commands"]]
if apply_names != ["apply_01", "apply_02", "apply_03", "apply_04"]:
    raise SystemExit(f"unexpected apply command order: {apply_names}")
if report["apply_commands"][0]["argv"] != ["ip", "tuntap", "add", "dev", "swarm0", "mode", "tun"]:
    raise SystemExit("first TUN apply command must create swarm0 TUN")
if report["rollback_commands"][0]["argv"] != ["ip", "link", "delete", "swarm0"]:
    raise SystemExit("rollback command must delete swarm0")
script = Path(report["generated_script"])
if not script.exists():
    raise SystemExit(f"missing generated script: {script}")
script_text = script.read_text(encoding="utf-8")
for token in ("#!/bin/sh", "set -eu", "CONFIG_TUN",
              "test -c /dev/net/tun", "ip tuntap add dev swarm0 mode tun",
              "trap 'ip link delete swarm0"):
    if token not in script_text:
        raise SystemExit(f"generated script missing {token}")
print(json.dumps({
    "event": "fieldmesh_tun_apply_run_check",
    "ok": True,
    "commands": len(report["apply_commands"]),
    "pre_state": len(report["pre_state_commands"]),
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_tun_apply_run.py" \
  --tun-gateway-report "$sdk_dir/fieldmesh_tun_gateway_demo.ndjson" \
  --out-dir "$work_dir/missing-write-allow" \
  --execute-live-network \
  --target-is-zynq-board \
  --cap-net-admin-confirmed \
  >/dev/null 2>&1; then
  echo "TUN apply runner accepted live execution without --allow-network-writes" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_tun_apply_run.py" \
  --tun-gateway-report "$sdk_dir/fieldmesh_tun_gateway_demo.ndjson" \
  --out-dir "$work_dir/missing-target" \
  --execute-live-network \
  --allow-network-writes \
  --cap-net-admin-confirmed \
  >/dev/null 2>&1; then
  echo "TUN apply runner accepted live execution without --target-is-zynq-board" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_tun_apply_run.py" \
  --tun-gateway-report "$sdk_dir/fieldmesh_tun_gateway_demo.ndjson" \
  --out-dir "$work_dir/missing-cap" \
  --execute-live-network \
  --allow-network-writes \
  --target-is-zynq-board \
  >/dev/null 2>&1; then
  echo "TUN apply runner accepted live execution without --cap-net-admin-confirmed" >&2
  exit 1
fi
