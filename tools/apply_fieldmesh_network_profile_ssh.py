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
    "fieldmesh_gnss_nmea_device",
    "fieldmesh_gnss_nmea_baud",
    "fieldmesh_gnss_pps_lock",
    "fieldmesh_gnss_nmea_max_reports",
)

IDENTITY_STORE_PATHS = (
    "/mnt/jffs2/fieldmesh/device_eui",
    "/etc/fieldmesh/device_eui",
)

GNSS_BAUDS = (4800, 9600, 19200, 38400, 57600, 115200)


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
    gnss_nmea_device: str
    gnss_nmea_baud: int
    gnss_pps_lock: int
    gnss_nmea_max_reports: int


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
    parser.add_argument("--gnss-nmea-device", default="",
                        help="Optional deployed GNSS NMEA device, for example /dev/ttyPS1")
    parser.add_argument("--gnss-nmea-baud", type=int, default=9600,
                        choices=GNSS_BAUDS)
    parser.add_argument("--gnss-pps-lock", type=int, default=0, choices=(0, 1))
    parser.add_argument("--gnss-nmea-max-reports", type=int, default=0,
                        help="0 means continuous reporting; bounded values are for verification")
    parser.add_argument("--gnss-only", action="store_true",
                        help="Only persist GNSS service files; do not modify U-Boot env or identity")
    parser.add_argument("--allow-missing-gnss-device", action="store_true",
                        help="Allow planning/apply before the configured GNSS device exists")
    parser.add_argument("--allow-console-gnss-device", action="store_true",
                        help="Allow using the active console tty as GNSS input")
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
    gnss_device = args.gnss_nmea_device.strip()
    if gnss_device:
        if not gnss_device.startswith("/dev/"):
            raise SystemExit("gnss-nmea-device must be an absolute /dev path")
        if any(ch.isspace() for ch in gnss_device):
            raise SystemExit("gnss-nmea-device must not contain whitespace")
    if args.gnss_nmea_max_reports < 0 or args.gnss_nmea_max_reports > 1024:
        raise SystemExit("gnss-nmea-max-reports must be in 0..1024")
    if args.gnss_only and not gnss_device:
        raise SystemExit("--gnss-only requires --gnss-nmea-device")
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
        gnss_nmea_device=gnss_device,
        gnss_nmea_baud=args.gnss_nmea_baud,
        gnss_pps_lock=args.gnss_pps_lock,
        gnss_nmea_max_reports=args.gnss_nmea_max_reports,
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
printf 'cmdline='
cat /proc/cmdline 2>/dev/null || true
echo
printf 'model='
cat /proc/device-tree/model 2>/dev/null | tr '\\000' ' ' || true
echo
fw_printenv hostname mode ethaddr ipaddr ipaddr_host netmask ipaddr_eth netmask_eth qspiboot fieldmesh_device_eui 2>/dev/null || true
for path in /mnt/jffs2/fieldmesh/device_eui /etc/fieldmesh/device_eui; do
  if [ -f "$path" ]; then
    printf '%s=' "$path"
    sed -n '1p' "$path" 2>/dev/null | tr -d '\\r\\n\\t '
    echo
  fi
done
serials="$(ls /dev/ttyPS* /dev/ttyUSB* /dev/ttyACM* /dev/ttyS* 2>/dev/null | tr '\\n' ',' | sed 's/,$//')"
echo "serial_devices=$serials"
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
    if profile.gnss_nmea_device:
        lines.extend([
            f"fieldmesh_gnss_nmea_device {profile.gnss_nmea_device}",
            f"fieldmesh_gnss_nmea_baud {profile.gnss_nmea_baud}",
            f"fieldmesh_gnss_pps_lock {profile.gnss_pps_lock}",
            f"fieldmesh_gnss_nmea_max_reports {profile.gnss_nmea_max_reports}",
        ])
    return lines


def identity_store_lines(profile: Profile) -> list[str]:
    return [f"{path} {profile.device_eui}" for path in IDENTITY_STORE_PATHS]


def gnss_store_lines(profile: Profile) -> list[str]:
    if not profile.gnss_nmea_device:
        return []
    return [
        f"fieldmesh_gnss_nmea_device {profile.gnss_nmea_device}",
        f"fieldmesh_gnss_nmea_baud {profile.gnss_nmea_baud}",
        f"fieldmesh_gnss_pps_lock {profile.gnss_pps_lock}",
        f"fieldmesh_gnss_nmea_max_reports {profile.gnss_nmea_max_reports}",
        f"/mnt/jffs2/fieldmesh/gnss_nmea_device {profile.gnss_nmea_device}",
        f"/mnt/jffs2/fieldmesh/gnss_nmea_baud {profile.gnss_nmea_baud}",
        f"/mnt/jffs2/fieldmesh/gnss_pps_lock {profile.gnss_pps_lock}",
        f"/mnt/jffs2/fieldmesh/gnss_nmea_max_reports {profile.gnss_nmea_max_reports}",
        f"/etc/fieldmesh/gnss_nmea_device {profile.gnss_nmea_device}",
        f"/etc/fieldmesh/gnss_nmea_baud {profile.gnss_nmea_baud}",
        f"/etc/fieldmesh/gnss_pps_lock {profile.gnss_pps_lock}",
        f"/etc/fieldmesh/gnss_nmea_max_reports {profile.gnss_nmea_max_reports}",
    ]


def validate_identity(args: argparse.Namespace, identity_text: str, profile: Profile) -> dict[str, object]:
    identity = parse_kv_lines(identity_text)
    errors = []
    if not variant_matches(args.variant, identity_text, identity):
        errors.append(f"identity does not match expected variant {args.variant}")
    if not args.gnss_only and identity.get("fw_setenv") != "present":
        errors.append("fw_setenv is missing")
    if (
        not args.gnss_only
        and identity.get("fieldmeshctl") != "present"
        and not args.allow_missing_fieldmeshctl
    ):
        errors.append("fieldmeshctl is missing; refusing persistent profile writes")
    if identity.get("persistent_backup") != "writable" and not args.allow_volatile_backup:
        errors.append("/mnt/jffs2 is not writable for persistent rollback backup")
    if profile.gnss_nmea_device:
        serial_devices = {
            item for item in identity.get("serial_devices", "").split(",") if item
        }
        cmdline = identity.get("cmdline", "")
        if (
            profile.gnss_nmea_device not in serial_devices
            and not args.allow_missing_gnss_device
        ):
            errors.append(
                f"gnss_nmea_device {profile.gnss_nmea_device} is not present on the board"
            )
        if (
            f"console={profile.gnss_nmea_device.rsplit('/', 1)[-1]}" in cmdline
            and not args.allow_console_gnss_device
        ):
            errors.append(
                f"gnss_nmea_device {profile.gnss_nmea_device} is the active console"
            )
    return {
        "identity": identity,
        "errors": errors,
        "safe_to_apply": not errors,
    }


def gnss_apply_commands(profile: Profile) -> str:
    if not profile.gnss_nmea_device:
        return ""
    gnss_values = {
        "gnss_nmea_device": profile.gnss_nmea_device,
        "gnss_nmea_baud": str(profile.gnss_nmea_baud),
        "gnss_pps_lock": str(profile.gnss_pps_lock),
        "gnss_nmea_max_reports": str(profile.gnss_nmea_max_reports),
    }
    commands = ["mkdir -p /mnt/jffs2/fieldmesh"]
    for key, value in gnss_values.items():
        quoted_value = shlex.quote(value)
        commands.append(f"fw_setenv fieldmesh_{key} {quoted_value} 2>/dev/null || true")
        commands.extend([
            f"printf '%s\\n' {quoted_value} > /mnt/jffs2/fieldmesh/{key}.tmp",
            f"chmod 0644 /mnt/jffs2/fieldmesh/{key}.tmp",
            f"mv /mnt/jffs2/fieldmesh/{key}.tmp /mnt/jffs2/fieldmesh/{key}",
        ])
    commands.append("if mkdir -p /etc/fieldmesh 2>/dev/null; then")
    for key, value in gnss_values.items():
        quoted_value = shlex.quote(value)
        commands.extend([
            f"  printf '%s\\n' {quoted_value} > /etc/fieldmesh/{key}.tmp",
            f"  chmod 0644 /etc/fieldmesh/{key}.tmp",
            f"  mv /etc/fieldmesh/{key}.tmp /etc/fieldmesh/{key}",
        ])
    commands.append("fi")
    return "\n".join(commands)


def apply_script(profile: Profile, allow_volatile: bool, reboot: bool,
                 gnss_only: bool = False) -> str:
    backup_root = "/mnt/jffs2/fieldmesh-profile-backups"
    fallback_root = "/tmp/fieldmesh-profile-backups"
    set_commands = "\n".join(
        f"fw_setenv {shlex.quote(key)} {shlex.quote(value)}"
        for key, value in (line.split(" ", 1) for line in fw_setenv_lines(profile))
    )
    keys = " ".join(shlex.quote(key) for key in ENV_KEYS)
    reboot_cmd = "reboot" if reboot else "true"
    device_eui = shlex.quote(profile.device_eui)
    gnss_commands = gnss_apply_commands(profile)
    if gnss_only:
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
backup="$backup_root/gnss-profile-$stamp.env"
for path in /mnt/jffs2/fieldmesh/gnss_nmea_device /mnt/jffs2/fieldmesh/gnss_nmea_baud /mnt/jffs2/fieldmesh/gnss_pps_lock /mnt/jffs2/fieldmesh/gnss_nmea_max_reports /etc/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_baud /etc/fieldmesh/gnss_pps_lock /etc/fieldmesh/gnss_nmea_max_reports; do
  if [ -f "$path" ]; then
    printf '%s=' "$path" >> "$backup"
    sed -n '1p' "$path" 2>/dev/null | tr -d '\\r\\n\\t ' >> "$backup"
    echo >> "$backup"
  fi
done
fw_printenv fieldmesh_device_eui >> "$backup" 2>/dev/null || true
fw_setenv fieldmesh_device_eui {device_eui} 2>/dev/null || true
mkdir -p /mnt/jffs2/fieldmesh
printf '%s\\n' {device_eui} > /mnt/jffs2/fieldmesh/device_eui.tmp
chmod 0644 /mnt/jffs2/fieldmesh/device_eui.tmp
mv /mnt/jffs2/fieldmesh/device_eui.tmp /mnt/jffs2/fieldmesh/device_eui
if mkdir -p /etc/fieldmesh 2>/dev/null; then
  printf '%s\\n' {device_eui} > /etc/fieldmesh/device_eui.tmp
  chmod 0644 /etc/fieldmesh/device_eui.tmp
  mv /etc/fieldmesh/device_eui.tmp /etc/fieldmesh/device_eui
fi
{gnss_commands}
printf 'backup_path=%s\\n' "$backup"
printf 'fieldmesh_device_eui=%s\\n' {device_eui}
for path in /mnt/jffs2/fieldmesh/gnss_nmea_device /mnt/jffs2/fieldmesh/gnss_nmea_baud /mnt/jffs2/fieldmesh/gnss_pps_lock /mnt/jffs2/fieldmesh/gnss_nmea_max_reports /etc/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_baud /etc/fieldmesh/gnss_pps_lock /etc/fieldmesh/gnss_nmea_max_reports; do
  if [ -f "$path" ]; then
    printf '%s=' "$path"
    sed -n '1p' "$path" 2>/dev/null | tr -d '\\r\\n\\t '
    echo
  fi
done
sync
{reboot_cmd}
"""
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
identity_root=/mnt/jffs2/fieldmesh
mkdir -p "$identity_root"
{set_commands}
printf '%s\\n' {device_eui} > "$identity_root/device_eui.tmp"
chmod 0644 "$identity_root/device_eui.tmp"
mv "$identity_root/device_eui.tmp" "$identity_root/device_eui"
if mkdir -p /etc/fieldmesh 2>/dev/null; then
  printf '%s\\n' {device_eui} > /etc/fieldmesh/device_eui.tmp
  chmod 0644 /etc/fieldmesh/device_eui.tmp
  mv /etc/fieldmesh/device_eui.tmp /etc/fieldmesh/device_eui
fi
{gnss_commands}
printf 'backup_path=%s\\n' "$backup"
printf 'identity_store_path=%s\\n' "$identity_root/device_eui"
fw_printenv hostname ethaddr ipaddr ipaddr_host netmask ipaddr_eth netmask_eth fieldmesh_device_eui fieldmesh_node_id fieldmesh_network_id fieldmesh_preferred_ap fieldmesh_ap_policy 2>/dev/null || true
for path in /mnt/jffs2/fieldmesh/device_eui /etc/fieldmesh/device_eui /mnt/jffs2/fieldmesh/gnss_nmea_device /mnt/jffs2/fieldmesh/gnss_nmea_baud /mnt/jffs2/fieldmesh/gnss_pps_lock /mnt/jffs2/fieldmesh/gnss_nmea_max_reports /etc/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_baud /etc/fieldmesh/gnss_pps_lock /etc/fieldmesh/gnss_nmea_max_reports; do
  if [ -f "$path" ]; then
    printf '%s=' "$path"
    sed -n '1p' "$path" 2>/dev/null | tr -d '\\r\\n\\t '
    echo
  fi
done
sync
{reboot_cmd}
"""


def rollback_script(backup_path: str, reboot: bool) -> str:
    reboot_cmd = "reboot" if reboot else "true"
    return f"""set -eu
backup={shlex.quote(backup_path)}
test -f "$backup"
restore_eui=""
while IFS='=' read -r key value; do
  [ -n "$key" ] || continue
  fw_setenv "$key" "$value"
  [ "$key" = "fieldmesh_device_eui" ] && restore_eui="$value"
done < "$backup"
if [ -n "$restore_eui" ]; then
  mkdir -p /mnt/jffs2/fieldmesh
  printf '%s\\n' "$restore_eui" > /mnt/jffs2/fieldmesh/device_eui.tmp
  chmod 0644 /mnt/jffs2/fieldmesh/device_eui.tmp
  mv /mnt/jffs2/fieldmesh/device_eui.tmp /mnt/jffs2/fieldmesh/device_eui
  if mkdir -p /etc/fieldmesh 2>/dev/null; then
    printf '%s\\n' "$restore_eui" > /etc/fieldmesh/device_eui.tmp
    chmod 0644 /etc/fieldmesh/device_eui.tmp
    mv /etc/fieldmesh/device_eui.tmp /etc/fieldmesh/device_eui
  fi
fi
printf 'rollback_backup_path=%s\\n' "$backup"
fw_printenv {' '.join(shlex.quote(key) for key in ENV_KEYS)} 2>/dev/null || true
for path in /mnt/jffs2/fieldmesh/device_eui /etc/fieldmesh/device_eui /mnt/jffs2/fieldmesh/gnss_nmea_device /mnt/jffs2/fieldmesh/gnss_nmea_baud /mnt/jffs2/fieldmesh/gnss_pps_lock /mnt/jffs2/fieldmesh/gnss_nmea_max_reports /etc/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_baud /etc/fieldmesh/gnss_pps_lock /etc/fieldmesh/gnss_nmea_max_reports; do
  if [ -f "$path" ]; then
    printf '%s=' "$path"
    sed -n '1p' "$path" 2>/dev/null | tr -d '\\r\\n\\t '
    echo
  fi
done
sync
{reboot_cmd}
"""


def main() -> int:
    args = parse_args()
    profile = validate_profile(args)
    identity_text = collect_identity(args)
    identity_result = validate_identity(args, identity_text, profile)
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
            "gnss_nmea_device": profile.gnss_nmea_device,
            "gnss_nmea_baud": profile.gnss_nmea_baud if profile.gnss_nmea_device else 0,
            "gnss_pps_lock": profile.gnss_pps_lock if profile.gnss_nmea_device else 0,
            "gnss_nmea_max_reports": profile.gnss_nmea_max_reports if profile.gnss_nmea_device else 0,
        },
        "fw_setenv": fw_setenv_lines(profile),
        "identity_store": identity_store_lines(profile),
        "gnss_store": gnss_store_lines(profile),
        "gnss_only": bool(args.gnss_only),
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

    output = run_ssh(
        args,
        apply_script(profile, args.allow_volatile_backup, args.reboot, args.gnss_only),
    )
    print(json.dumps({**plan, "event": "fieldmesh_network_profile_apply",
                      "remote_output": output.splitlines()}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
