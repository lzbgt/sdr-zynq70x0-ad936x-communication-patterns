#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/examples/jtag-hello"
out_dir="${OUT_DIR:-$repo_root/.config/jtag-hello}"
elf="$out_dir/jtag-hello.elf"

for cmd in arm-none-eabi-gcc arm-none-eabi-size arm-none-eabi-objdump; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

mkdir -p "$out_dir"

arm-none-eabi-gcc \
  -mcpu=cortex-a9 \
  -marm \
  -ffreestanding \
  -fno-builtin \
  -fno-stack-protector \
  -nostdlib \
  -Wl,-T,"$src_dir/linker.ld" \
  -Wl,-Map,"$out_dir/jtag-hello.map" \
  "$src_dir/start.S" \
  "$src_dir/hello.c" \
  -o "$elf"

arm-none-eabi-size "$elf"
arm-none-eabi-objdump -h "$elf" >"$out_dir/jtag-hello.sections.txt"
arm-none-eabi-objdump -d "$elf" >"$out_dir/jtag-hello.disasm.txt"

echo "Built $elf"
