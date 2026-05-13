#!/usr/bin/env python3
"""Safely plan or apply a FieldMesh network profile over SSH."""

from __future__ import annotations

import argparse
import ipaddress
import json
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path


ENV_KEYS = (
    "hostname",
    "mode",
    "ipaddr",
    "ipaddr_host",
    "netmask",
    "ipaddr_eth",
    "netmask_eth",
    "ethaddr",
    "fieldmesh_device_eui",
    "fieldmesh_node_id",
    "fieldmesh_network_id",
    "fieldmesh_preferred_ap",
    "fieldmesh_ap_policy",
)


@dataclass
class Profile:
    device_eui: str
    node_id: str
    network_id: str
    usb_device_ip: str
    usb_host_ip: str
    prefix: int
    ap_policy: str
    preferred_ap_id: str
    phy_device_ip: str
    phy_prefix: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plan/apply FieldMesh USB/PHY network profile changes over SSH"
    )
    parser.add_argument("--host", default="", help="Current reachable board IP/host")
    parser.add_argument("--ssh-user", default="root")
    parser.add_argument("--ssh-pass", default="analog")
    parser.add_argument("--variant", choices=("z203", "z103"), required=True)
    parser.add_argument("--device-eui", default="",
                        help="12 hex chars; defaults from board MAC/EUI convention")
    parser.add_argument("--node-id", required=True)
    parser.add_argument("--network-id", default="fieldmesh-lab")
    parser.add_argument("--usb-device-ip", required=True)
    parser.add_argument("--usb-host-ip", required=True)
    parser.add_argument("--prefix", type=int, default=24)
    parser.add_argument("--ap-policy", choices=("predefined", "autonomous-swarm", "hybrid"),
                        default="hybrid")
    parser.add_argument("--preferred-ap-id", default="020000000203")
    parser.add_argument("--phy-device-ip", default="")
    parser.add_argument("--phy-prefix", type=int, default=24)
    parser.add_argument("--mock-identity-file", default="")
    parser.add_argument("--allow-missing-fieldmeshctl", action="store_true")
    parser.add_argument("--allow-volatile-backup", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--rollback", action="store_true")
    parser.add_argument("--backup-path", default="")
    parser.add_argument("--allow-persistent-writes", action="store_true")
    parser.add_argument("--reboot", action="store_true")
    return parser.parse_args()


def validate_profile(args: argparse.Namespace) -> Profile:
    device_eui = args.device_eui or ("020000000203" if args.variant == "z203" else "020000000103")
    device_eui = device_eui.replace(":", "").replace("-", "")
    if len(device_eui) != 12 or any(ch not in "0123456789abcdefABCDEF" for ch in device_eui):
        raise SystemExit("device-eui must be 12 hex chars")
    usb_device = ipaddress.IPv4Address(args.usb_device_ip)
    usb_host = ipaddress.IPv4Address(args.usb_host_ip)
    if usb_device == usb_host:
        raise SystemExit("usb-device-ip and usb-host-ip must differ")
    if args.prefix <= 0 or args.prefix > 30:
        raise SystemExit("prefix must be in 1..30")
    if not args.node_id:
        raise SystemExit("node-id is required")
    if args.phy_device_ip:
        ipaddress.IPv4Address(args.phy_device_ip)
        if args.phy_prefix <= 0 or args.phy_prefix > 30:
            raise SystemExit("phy-prefix must be in 1..30 when phy-device-ip is set")
    return Profile(
        device_eui=device_eui,
        node_id=args.node_id,
        network_id=args.network_id,
        usb_device_ip=str(usb_device),
        usb_host_ip=str(usb_host),
        prefix=args.prefix,
        ap_policy=args.ap_policy,
        preferred_ap_id=args.preferred_ap_id,
        phy_device_ip=args.phy_device_ip,
        phy_prefix=args.phy_prefix,
    )


def netmask(prefix: int) -> str:
    return str(ipaddress.IPv4Network(f"0.0.0.0/{prefix}").netmask)


def ssh_command(args: argparse.Namespace) -> list[str]:
    base = []
    if args.ssh_pass:
        base.extend(["sshpass", "-p", args.ssh_pass])
    base.extend([
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{args.ssh_user}@{args.host}",
    ])
    return base


def run_ssh(args: argparse.Namespace, script: str) -> str:
    if not args.host:
        raise SystemExit("--host is required when not using --mock-identity-file")
    try:
        result = subprocess.run(
            ssh_command(args) + ["sh", "-s"],
            input=script,
            text=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            f"ssh command failed with rc={exc.returncode}\n{exc.stderr.strip()}"
        ) from exc
    return result.stdout


def collect_identity(args: argparse.Namespace) -> str:
    if args.mock_identity_file:
        return Path(args.mock_identity_file).read_text(encoding="utf-8")
    script = """
set -eu
echo "fieldmesh_identity_begin"
echo "hostname=$(hostname 2>/dev/null || true)"
echo "uname=$(uname -a 2>/dev/null || true)"
printf 'model='
cat /proc/device-tree/model 2>/dev/null | tr '\\000' ' ' || true
echo
fw_printenv hostname mode ethaddr ipaddr ipaddr_host netmask ipaddr_eth netmask_eth qspiboot fieldmesh_device_eui 2>/dev/null || true
if command -v fieldmeshctl >/dev/null 2>&1; then
  echo "fieldmeshctl=present"
else
  echo "fieldmeshctl=missing"
fi
if command -v fw_setenv >/dev/null 2>&1; then
  echo "fw_setenv=present"
else
  echo "fw_setenv=missing"
fi
if [ -w /mnt/jffs2 ] || mkdir -p /mnt/jffs2/.fieldmesh-test 2>/dev/null; then
  rmdir /mnt/jffs2/.fieldmesh-test 2>/dev/null || true
  echo "persistent_backup=writable"
else
  echo "persistent_backup=missing"
fi
echo "fieldmesh_identity_end"
"""
    return run_ssh(args, script)


def parse_kv_lines(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def variant_matches(variant: str, identity_text: str, identity: dict[str, str]) -> bool:
    haystack = identity_text.lower()
    mode = identity.get("mode", "").lower()
    if variant == "z203":
        return mode == "2r2t" or "z203" in haystack or "2r2t" in haystack
    return mode == "1r1t" or "z103" in haystack or "z7010" in haystack or "1r1t" in haystack


def fw_setenv_lines(profile: Profile) -> list[str]:
    lines = [
        f"hostname {profile.node_id}",
        f"ipaddr {profile.usb_device_ip}",
        f"ipaddr_host {profile.usb_host_ip}",
        f"netmask {netmask(profile.prefix)}",
        f"fieldmesh_device_eui {profile.device_eui}",
        f"fieldmesh_node_id {profile.node_id}",
        f"fieldmesh_network_id {profile.network_id}",
        f"fieldmesh_preferred_ap {profile.preferred_ap_id}",
        f"fieldmesh_ap_policy {profile.ap_policy}",
    ]
    if profile.phy_device_ip:
        lines.append(f"ipaddr_eth {profile.phy_device_ip}")
        lines.append(f"netmask_eth {netmask(profile.phy_prefix)}")
    return lines


def validate_identity(args: argparse.Namespace, identity_text: str) -> dict[str, object]:
    identity = parse_kv_lines(identity_text)
    errors = []
    if not variant_matches(args.variant, identity_text, identity):
        errors.append(f"identity does not match expected variant {args.variant}")
    if identity.get("fw_setenv") != "present":
        errors.append("fw_setenv is missing")
    if identity.get("fieldmeshctl") != "present" and not args.allow_missing_fieldmeshctl:
        errors.append("fieldmeshctl is missing; refusing persistent profile writes")
    if identity.get("persistent_backup") != "writable" and not args.allow_volatile_backup:
        errors.append("/mnt/jffs2 is not writable for persistent rollback backup")
    return {
        "identity": identity,
        "errors": errors,
        "safe_to_apply": not errors,
    }


def apply_script(profile: Profile, allow_volatile: bool, reboot: bool) -> str:
    backup_root = "/mnt/jffs2/fieldmesh-profile-backups"
    fallback_root = "/tmp/fieldmesh-profile-backups"
    set_commands = "\n".join(
        f"fw_setenv {shlex.quote(key)} {shlex.quote(value)}"
        for key, value in (line.split(" ", 1) for line in fw_setenv_lines(profile))
    )
    keys = " ".join(shlex.quote(key) for key in ENV_KEYS)
    reboot_cmd = "reboot" if reboot else "true"
    return f"""set -eu
backup_root={shlex.quote(backup_root)}
if ! mkdir -p "$backup_root" 2>/dev/null; then
  if [ {1 if allow_volatile else 0} -eq 1 ]; then
    backup_root={shlex.quote(fallback_root)}
    mkdir -p "$backup_root"
  else
    echo "persistent backup directory is not writable" >&2
    exit 12
  fi
fi
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$backup_root/profile-$stamp.env"
fw_printenv {keys} > "$backup" 2>/dev/null || true
{set_commands}
printf 'backup_path=%s\\n' "$backup"
fw_printenv hostname ethaddr ipaddr ipaddr_host netmask ipaddr_eth netmask_eth fieldmesh_device_eui fieldmesh_node_id fieldmesh_network_id fieldmesh_preferred_ap fieldmesh_ap_policy 2>/dev/null || true
sync
{reboot_cmd}
"""


def rollback_script(backup_path: str, reboot: bool) -> str:
    reboot_cmd = "reboot" if reboot else "true"
    return f"""set -eu
backup={shlex.quote(backup_path)}
test -f "$backup"
while IFS='=' read -r key value; do
  [ -n "$key" ] || continue
  fw_setenv "$key" "$value"
done < "$backup"
printf 'rollback_backup_path=%s\\n' "$backup"
fw_printenv {' '.join(shlex.quote(key) for key in ENV_KEYS)} 2>/dev/null || true
sync
{reboot_cmd}
"""


def main() -> int:
    args = parse_args()
    profile = validate_profile(args)
    identity_text = collect_identity(args)
    identity_result = validate_identity(args, identity_text)
    plan = {
        "event": "fieldmesh_network_profile_plan",
        "variant": args.variant,
        "host": args.host,
        "profile": {
            "device_eui": profile.device_eui,
            "node_id": profile.node_id,
            "network_id": profile.network_id,
            "usb_device_ip": profile.usb_device_ip,
            "usb_host_ip": profile.usb_host_ip,
            "netmask": netmask(profile.prefix),
            "ap_policy": profile.ap_policy,
            "preferred_ap_id": profile.preferred_ap_id,
            "phy_device_ip": profile.phy_device_ip,
            "phy_netmask": netmask(profile.phy_prefix) if profile.phy_device_ip else "",
        },
        "fw_setenv": fw_setenv_lines(profile),
        **identity_result,
    }

    if args.rollback:
        if not args.allow_persistent_writes:
            raise SystemExit("--rollback requires --allow-persistent-writes")
        if not args.backup_path:
            raise SystemExit("--rollback requires --backup-path")
        if identity_result["errors"]:
            print(json.dumps(plan, sort_keys=True))
            raise SystemExit("identity checks failed; refusing rollback")
        output = run_ssh(args, rollback_script(args.backup_path, args.reboot))
        print(json.dumps({**plan, "event": "fieldmesh_network_profile_rollback",
                          "remote_output": output.splitlines()}, sort_keys=True))
        return 0

    if not args.apply:
        print(json.dumps(plan, sort_keys=True))
        return 0 if not identity_result["errors"] else 1

    if not args.allow_persistent_writes:
        print(json.dumps(plan, sort_keys=True))
        raise SystemExit("--apply requires --allow-persistent-writes")
    if identity_result["errors"]:
        print(json.dumps(plan, sort_keys=True))
        raise SystemExit("identity checks failed; refusing apply")

    output = run_ssh(args, apply_script(profile, args.allow_volatile_backup, args.reboot))
    print(json.dumps({**plan, "event": "fieldmesh_network_profile_apply",
                      "remote_output": output.splitlines()}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
