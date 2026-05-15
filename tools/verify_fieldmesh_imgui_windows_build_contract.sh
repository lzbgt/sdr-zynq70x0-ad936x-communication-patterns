#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="$repo_root/.config/fieldmesh/imgui-control-cmake"
out_dir="$repo_root/.config/fieldmesh/imgui-control-windows-contract"
cmake_file="$app_dir/CMakeLists.txt"
ps1="$repo_root/tools/build_fieldmesh_imgui_windows.ps1"

mkdir -p "$out_dir"

required_patterns=(
    'project\(fieldmesh_imgui_control LANGUAGES C CXX\)'
    'fieldmesh-imgui-control-headless'
    'fieldmesh-imgui-control-glfw'
    'FIELDMESH_IMGUI_BUILD_GLFW'
    'FIELDMESH_IMGUI_EMBED_PYTHON'
    'FIELDMESH_WITH_EMBEDDED_PYTHON'
    'find_package\(Python3 REQUIRED COMPONENTS Development\.Embed\)'
    'find_package\(glfw3 CONFIG QUIET\)'
    'OpenGL::GL'
    'fieldmesh_imgui_control_app\.cpp'
    'fieldmesh_imgui_glfw_main\.cpp'
    'fieldmesh_imgui_embedded_python\.cpp'
    'sdk/c/src/fieldmesh_sdk\.c'
)
for pattern in "${required_patterns[@]}"; do
    if ! rg -q "$pattern" "$cmake_file"; then
        echo "missing CMake contract pattern: $pattern" >&2
        exit 1
    fi
done

if ! rg -q 'Visual Studio 17 2022' "$ps1"; then
    echo "Windows build helper must default to Visual Studio 2022" >&2
    exit 1
fi
if ! rg -q 'CMAKE_TOOLCHAIN_FILE' "$ps1"; then
    echo "Windows build helper must support vcpkg/CMake toolchain files" >&2
    exit 1
fi

rm -rf "$build_dir"
cmake -S "$app_dir" -B "$build_dir" \
    -DFIELDMESH_IMGUI_BUILD_GLFW=OFF \
    -DFIELDMESH_IMGUI_EMBED_PYTHON=OFF >/dev/null
cmake --build "$build_dir" --target fieldmesh-imgui-control-headless --parallel 2 >/dev/null

snapshot="$out_dir/cmake_headless_snapshot.json"
"$build_dir/fieldmesh-imgui-control-headless" \
    --self-test \
    --profile "$app_dir/testdata/golden_lab.profile" \
    --snapshot-output "$snapshot" >/dev/null

python3 - "$snapshot" <<'PY'
import json
import sys

snapshot = json.load(open(sys.argv[1], encoding="utf-8"))
if snapshot.get("app_model") != "symmetric_im_peer":
    raise SystemExit("CMake headless app did not build the symmetric IM model")
if snapshot.get("python_api_module") != "fieldmesh_imgui":
    raise SystemExit("CMake headless app did not retain embedded Python API contract")
if snapshot.get("deployment_profile_embedded") is not False:
    raise SystemExit("CMake app build must not embed deployment profiles")
if snapshot.get("user_runs_shell_scripts") is not False:
    raise SystemExit("GUI product workflow must not require users to run scripts")
PY

if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
        "\$null = [scriptblock]::Create((Get-Content -Raw '$(wslpath -w "$ps1")')); 'powershell_syntax=ok'" \
        >"$out_dir/powershell_syntax.txt"
fi

echo "fieldmesh_imgui_windows_build_contract=pass"
