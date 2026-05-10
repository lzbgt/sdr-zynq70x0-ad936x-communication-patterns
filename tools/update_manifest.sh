#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

find resources -type f ! -name 'MANIFEST.sha256' -print0 \
  | sort -z \
  | xargs -0 sha256sum > resources/MANIFEST.sha256

echo "Updated resources/MANIFEST.sha256"
