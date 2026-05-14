#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  run_fieldmesh_imgui_wslg.sh [--check-bridge]
  run_fieldmesh_imgui_wslg.sh [--detach] [--no-build] [--profile PATH] [--instance NAME] [--] [app-args...]

Environment:
  GUI_APP=/path/to/fieldmesh-imgui-control
  IMGUI_DIR=/path/to/imgui
  PROFILE=/path/to/runtime.profile

Examples:
  tools/run_fieldmesh_imgui_wslg.sh --check-bridge
  tools/run_fieldmesh_imgui_wslg.sh --detach --profile apps/fieldmesh-imgui-control/testdata/golden_lab.profile
  tools/run_fieldmesh_imgui_wslg.sh --detach --instance peer-a -- --publish
  tools/run_fieldmesh_imgui_wslg.sh --detach --instance peer-b -- --preview
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="${BUILD_DIR:-$repo_root/.config/fieldmesh/imgui-control-build}"
gui_app="${GUI_APP:-$build_dir/fieldmesh-imgui-control-glfw}"
imgui_dir="${IMGUI_DIR:-$repo_root/.config/third_party/imgui}"
profile="${PROFILE:-}"
instance="fieldmesh-imgui"
detach=0
check_bridge=0
auto_build=1
app_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --check-bridge)
            check_bridge=1
            shift
            ;;
        --detach)
            detach=1
            shift
            ;;
        --no-build)
            auto_build=0
            shift
            ;;
        --profile)
            profile="${2:-}"
            if [ -z "$profile" ]; then
                echo "--profile requires PATH" >&2
                exit 2
            fi
            shift 2
            ;;
        --instance)
            instance="${2:-}"
            if [ -z "$instance" ]; then
                echo "--instance requires NAME" >&2
                exit 2
            fi
            shift 2
            ;;
        --)
            shift
            app_args+=("$@")
            break
            ;;
        *)
            app_args+=("$1")
            shift
            ;;
    esac
done

if [ -d /usr/lib/wsl/lib ]; then
    export LD_LIBRARY_PATH="/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

if [ -S /tmp/.X11-unix/X0 ] || [ -S /mnt/wslg/.X11-unix/X0 ]; then
    export DISPLAY="${DISPLAY:-:0}"
else
    echo "fieldmesh-wslg: WSLg X11 socket not found" >&2
    exit 1
fi

if [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    runtime_dir="${XDG_RUNTIME_DIR:-/tmp/wslg-runtime-$(id -u)}"
    mkdir -p "$runtime_dir"
    chmod 700 "$runtime_dir" 2>/dev/null || true
    export XDG_RUNTIME_DIR="$runtime_dir"
    if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] &&
       [ ! -L "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
        ln -sf "/mnt/wslg/runtime-dir/$WAYLAND_DISPLAY" \
            "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
    fi
    if [ -e "/mnt/wslg/runtime-dir/$WAYLAND_DISPLAY.lock" ] &&
       [ ! -e "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock" ]; then
        ln -sf "/mnt/wslg/runtime-dir/$WAYLAND_DISPLAY.lock" \
            "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY.lock"
    fi
fi

if [ -S /mnt/wslg/PulseServer ]; then
    export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
fi

if [ "$check_bridge" -eq 1 ]; then
    printf 'fieldmesh_wslg_bridge=pass\n'
    printf 'display=%s\n' "${DISPLAY:-}"
    printf 'wayland_display=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'xdg_runtime_dir=%s\n' "${XDG_RUNTIME_DIR:-}"
    printf 'pulse_server=%s\n' "${PULSE_SERVER:-}"
    if [ -e /dev/dxg ]; then
        printf 'dxg=yes\n'
    else
        printf 'dxg=no\n'
    fi
    exit 0
fi

if [ ! -x "$gui_app" ]; then
    if [ "$auto_build" -eq 1 ] && [ -f "$imgui_dir/imgui.cpp" ]; then
        echo "fieldmesh-wslg: building missing GUI binary with IMGUI_DIR=$imgui_dir" >&2
        make -C "$app_dir" \
            BUILD_DIR="$build_dir" \
            gui-glfw-python \
            IMGUI_DIR="$imgui_dir" >/dev/null
    fi
fi

if [ ! -x "$gui_app" ]; then
    cat >&2 <<EOF
fieldmesh-wslg: GUI app binary not found or not executable:
  $gui_app

Build it first, or provide an ImGui checkout for automatic build:
  IMGUI_DIR=/path/to/imgui tools/run_fieldmesh_imgui_wslg.sh --profile ...

Expected default ImGui checkout:
  $imgui_dir

Manual build:
  make -C "$app_dir" gui-glfw-python IMGUI_DIR="$imgui_dir"

The headless CI binary is not a Windows-visible GUI window.
EOF
    exit 1
fi

if [ -n "$profile" ]; then
    app_args=(--profile "$profile" "${app_args[@]}")
fi

if [ "$detach" -eq 1 ]; then
    log_file="/tmp/${instance}.log"
    nohup setsid "$gui_app" "${app_args[@]}" >"$log_file" 2>&1 < /dev/null &
    pid=$!
    echo "Started $gui_app as PID $pid"
    echo "Instance: $instance"
    echo "Log: $log_file"
else
    exec "$gui_app" "${app_args[@]}"
fi
