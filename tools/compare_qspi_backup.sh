#!/usr/bin/env bash
set -euo pipefail

backup_dir="${1:-resources/firmware/qspi-live-backup-20260511-211046}"
shift || true

if [[ ! -d "$backup_dir" ]]; then
  echo "Backup directory not found: $backup_dir" >&2
  exit 1
fi

variants=("$@")
if [[ "${#variants[@]}" == "0" ]]; then
  variants=(resources/firmware/qspi-1r1t resources/firmware/qspi-2r2t)
fi

for file in mtd0.bin mtd1.bin mtd3.bin; do
  if [[ ! -f "$backup_dir/$file" ]]; then
    echo "Missing backup file: $backup_dir/$file" >&2
    exit 1
  fi
done

echo "Backup: $backup_dir"
echo

for factory_dir in "${variants[@]}"; do
  if [[ ! -d "$factory_dir" ]]; then
    echo "Skipping missing factory dir: $factory_dir" >&2
    continue
  fi

  echo "Factory: $factory_dir"

  boot_size="$(stat -c '%s' "$factory_dir/boot.bin")"
  if cmp -s -n "$boot_size" "$factory_dir/boot.bin" "$backup_dir/mtd0.bin"; then
    echo "  boot.bin: MATCHES mtd0 prefix ($boot_size bytes)"
  else
    echo "  boot.bin: differs from mtd0 prefix"
  fi

  env_size="$(( $(stat -c '%s' "$factory_dir/uboot-env.dfu") - 16 ))"
  if cmp -s -n "$env_size" "$factory_dir/uboot-env.dfu" "$backup_dir/mtd1.bin"; then
    echo "  uboot-env.dfu payload: MATCHES mtd1 prefix ($env_size bytes)"
  else
    echo "  uboot-env.dfu payload: differs from mtd1 prefix"
  fi

  pluto_size="$(( $(stat -c '%s' "$factory_dir/pluto.dfu") - 16 ))"
  if cmp -s -n "$pluto_size" "$factory_dir/pluto.dfu" "$backup_dir/mtd3.bin"; then
    echo "  pluto.dfu payload: MATCHES mtd3 prefix ($pluto_size bytes)"
  else
    echo "  pluto.dfu payload: differs from mtd3 prefix"
  fi

  echo
done
