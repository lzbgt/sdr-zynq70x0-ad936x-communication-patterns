#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-/mnt/c/baidunetdiskdownload/SDR-Z103/plutosdr-fw.zip}"
dest="${Z103_SOURCE_ROOT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw}"
force="${FORCE:-0}"

if [[ ! -f "$archive" ]]; then
  echo "Archive not found: $archive" >&2
  exit 1
fi

if [[ -e "$dest/plutosdr-fw" && "$force" != "1" ]]; then
  echo "Destination already exists: $dest/plutosdr-fw" >&2
  echo "Set FORCE=1 to replace it." >&2
  exit 1
fi

if [[ "$force" == "1" ]]; then
  rm -rf "$dest/plutosdr-fw"
fi

mkdir -p "$dest"
unzip -q "$archive" -d "$dest"

cat > "$dest/SOURCE.txt" <<EOF
archive=$archive
extracted_at=$(date -Iseconds)
EOF

echo "Extracted Z103 source to: $dest/plutosdr-fw"
