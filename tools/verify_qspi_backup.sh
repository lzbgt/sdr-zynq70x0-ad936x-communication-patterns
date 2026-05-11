#!/usr/bin/env bash
set -euo pipefail

backup_dir="${1:-}"

if [[ -z "$backup_dir" ]]; then
  echo "Usage: $0 <qspi-backup-dir>" >&2
  exit 2
fi

if [[ ! -d "$backup_dir" ]]; then
  echo "Backup directory not found: $backup_dir" >&2
  exit 1
fi

for file in board-info.txt SHA256SUMS mtd0.bin mtd1.bin mtd2.bin mtd3.bin; do
  if [[ ! -f "$backup_dir/$file" ]]; then
    echo "Missing backup file: $backup_dir/$file" >&2
    exit 1
  fi
done

(
  cd "$backup_dir"
  sha256sum -c SHA256SUMS
)

awk '
  /^mtd[0-9]+:/ {
    part = substr($1, 1, length($1) - 1)
    printf "%s %d\n", part, strtonum("0x" $2)
  }
' "$backup_dir/board-info.txt" | while read -r part expected_size; do
  image="$backup_dir/$part.bin"
  if [[ ! -f "$image" ]]; then
    echo "Missing image for $part: $image" >&2
    exit 1
  fi

  actual_size="$(stat -c '%s' "$image")"
  if [[ "$actual_size" != "$expected_size" ]]; then
    echo "$part size mismatch: expected $expected_size, got $actual_size" >&2
    exit 1
  fi
done

for part in mtd0 mtd1 mtd2 mtd3; do
  size="$(stat -c '%s' "$backup_dir/$part.bin")"
  if [[ "$size" == "0" ]]; then
    echo "$part backup is empty" >&2
    exit 1
  fi
done

echo "QSPI backup verified: $backup_dir"
