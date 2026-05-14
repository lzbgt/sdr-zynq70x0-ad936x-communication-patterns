#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-source-apply"

rm -rf "$work_dir"
mkdir -p "$work_dir"

probe_z203="$work_dir/fieldmesh-udp-probe-z203"
probe_z103="$work_dir/fieldmesh-udp-probe-z103"
OUT="$probe_z203" "$repo_root/tools/build_fieldmesh_udp_probe_host.sh" \
  "$repo_root/meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" >/dev/null
OUT="$probe_z103" "$repo_root/tools/build_fieldmesh_udp_probe_host.sh" \
  "$repo_root/meta-sdr-z103/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" >/dev/null

mem_file="$work_dir/ctrl-window.bin"
preflight="$work_dir/preflight_assert.json"
truncate -s 65536 "$mem_file"
printf '\001\020\115\106' | dd of="$mem_file" bs=1 seek=0 conv=notrunc status=none
cat >"$preflight" <<'JSON'
{"event":"fieldmesh_sidecar_preflight_assert","ok":true,"ctrl_id":"0x464d1001"}
JSON

"$probe_z203" rf-guard-scan --ctrl-mem-file "$mem_file" \
  >"$work_dir/rf_guard_scan_before.ndjson"

if "$probe_z203" rf-source-apply \
  --ctrl-mem-file "$mem_file" \
  --preflight-assert "$preflight" \
  --allow-rf-source-select \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  >/dev/null 2>&1; then
  echo "rf-source-apply accepted missing --allow-live-writes" >&2
  exit 1
fi

if "$probe_z203" rf-source-apply \
  --ctrl-mem-file "$mem_file" \
  --preflight-assert "$preflight" \
  --allow-live-writes \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  >/dev/null 2>&1; then
  echo "rf-source-apply accepted missing --allow-rf-source-select" >&2
  exit 1
fi

if "$probe_z203" rf-source-apply \
  --ctrl-mem-file "$mem_file" \
  --preflight-assert "$preflight" \
  --allow-live-writes \
  --allow-rf-source-select \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  >/dev/null 2>&1; then
  echo "rf-source-apply accepted missing --target-is-zynq-board" >&2
  exit 1
fi

"$probe_z203" rf-source-apply \
  --ctrl-mem-file "$mem_file" \
  --preflight-assert "$preflight" \
  --allow-live-writes \
  --allow-rf-source-select \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  >"$work_dir/rf_source_apply.ndjson"

"$probe_z203" rf-guard-scan --ctrl-mem-file "$mem_file" \
  >"$work_dir/rf_guard_scan_after.ndjson"

"$probe_z103" rf-guard-scan --ctrl-mem-file "$mem_file" \
  >"$work_dir/rf_guard_scan_z103.ndjson"

python3 - "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

work = Path(sys.argv[1])

def rows(name):
    return [
        json.loads(line)
        for line in (work / name).read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

before = rows("rf_guard_scan_before.ndjson")
apply = rows("rf_source_apply.ndjson")
after = rows("rf_guard_scan_after.ndjson")
z103 = rows("rf_guard_scan_z103.ndjson")

if before[-1].get("event") != "rf_guard_scan_end" or before[-1].get("ok") is not True:
    raise SystemExit("initial RF guard scan failed")

write = next((row for row in apply if row.get("event") == "rf_source_apply_write"), None)
rollback = next((row for row in apply if row.get("event") == "rf_source_apply_rollback"), None)
end = next((row for row in apply if row.get("event") == "rf_source_apply_end"), None)
if not write or write.get("source_control") != "0x00000001":
    raise SystemExit("RF source apply did not select FieldMesh DAC source")
if write.get("selects_fieldmesh_dac_source") is not True:
    raise SystemExit("RF source apply did not report source selection")
if write.get("sets_ad936x_tx_enable") is not False or write.get("starts_rf_tx") is not False:
    raise SystemExit("RF source apply crossed the AD936x/RF TX safety boundary")
if not rollback or rollback.get("ok") is not True or rollback.get("source_control") != "0x00000000":
    raise SystemExit("RF source apply did not roll back source control")
if not end or end.get("ok") is not True or end.get("rolled_back") is not True:
    raise SystemExit("RF source apply did not end cleanly")

after_regs = {
    row.get("name"): row.get("value")
    for row in after
    if row.get("event") == "rf_guard_reg"
}
for name in (
    "rf_guard_control",
    "rf_current_epoch",
    "rf_current_slot",
    "rf_tx_epoch",
    "rf_tx_slot",
    "rf_dac_source_control",
):
    if after_regs.get(name) != "0x00000000":
        raise SystemExit(f"RF/DAC register {name} was not rolled back")
if z103[-1].get("event") != "rf_guard_scan_end" or z103[-1].get("ok") is not True:
    raise SystemExit("Z103 mirrored probe failed RF guard scan")

print(json.dumps({
    "event": "fieldmesh_rf_source_apply_check",
    "ok": True,
    "writes_source_register": True,
    "sets_ad936x_tx_enable": False,
    "starts_rf_tx": False,
    "rolled_back": True,
}, sort_keys=True))
PY
