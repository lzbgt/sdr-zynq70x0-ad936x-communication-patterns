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
  FIELDMESH_DISCOVERY_CANDIDATES=host:port,host:port
  FIELDMESH_WSLG_START_DAEMONS=1|0
  FIELDMESH_WSLG_FORCE_STAGE_DAEMONS=1|0

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

if [ -z "$profile" ] && [ -z "${FIELDMESH_DISCOVERY_CANDIDATES:-}" ]; then
    export FIELDMESH_DISCOVERY_CANDIDATES="${FIELDMESH_DISCOVERY_CANDIDATES:-192.168.1.10:55441,192.168.3.1:55441,192.168.3.1:55442,192.168.2.1:55441,192.168.2.1:55442,127.0.0.1:55441,127.0.0.1:55442}"
fi

start_daemon_if_needed() {
    host="$1"
    port="$2"
    requests="${3:-2000}"
    timeout_ms="${4:-3000}"
    staged_bin="/tmp/fieldmesh-state-daemon-demo-imgui"
    rootfs_tar=""

    set +e
    python3 - "$host" "$port" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(0.18)
try:
    sock.sendto(b"FIELDMESH_HELLO v1", (host, port))
    data, _ = sock.recvfrom(2048)
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
raise SystemExit(0 if b'"event":"sdk_daemon_hello"' in data else 1)
PY
    probe_rc=$?
    set -e
    if [ "$probe_rc" -eq 0 ]; then
        return 0
    fi

    if ! command -v sshpass >/dev/null 2>&1; then
        return 0
    fi
    if ! ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
        return 0
    fi

    if [ "${FIELDMESH_WSLG_FORCE_STAGE_DAEMONS:-0}" = "1" ]; then
        case "$host" in
            192.168.3.*)
                rootfs_tar="$repo_root/yocto/builds/sdr-z103-arm/tmp/deploy/images/sdr-z103-zynq7/sdr-z103-arm-image-sdr-z103-zynq7.rootfs.tar.gz"
                ;;
            *)
                rootfs_tar="$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz"
                ;;
        esac
        if [ -f "$rootfs_tar" ]; then
            tmp_daemon="/tmp/fieldmesh-state-daemon-demo-imgui.$$"
            tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-state-daemon-demo > "$tmp_daemon"
            chmod 0755 "$tmp_daemon"
            sshpass -p "${SSH_PASS:-analog}" scp \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR \
                "$tmp_daemon" "${SSH_USER:-root}@$host:$staged_bin" \
                >/dev/null 2>&1 || true
            rm -f "$tmp_daemon"
        fi
    fi
    sshpass -p "${SSH_PASS:-analog}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${SSH_USER:-root}@$host" \
        "pkill -f 'fieldmesh-state-daemon-demo.*serve 0.0.0.0 $port' 2>/dev/null || true; \
         daemon=''; \
         if [ '${FIELDMESH_WSLG_FORCE_STAGE_DAEMONS:-0}' = '1' ] && [ -x '$staged_bin' ]; then daemon='$staged_bin'; fi; \
         [ -n \"\$daemon\" ] || daemon=\$(command -v fieldmesh-state-daemon-demo || true); \
         [ -n \"\$daemon\" ] && \
         nohup \"\$daemon\" serve 0.0.0.0 '$port' '$requests' '$timeout_ms' \
         > '/tmp/fieldmesh_imgui_${port}.ndjson' 2>&1 &" \
        >/dev/null 2>&1 || true
}

if [ -z "$profile" ] && [ "${FIELDMESH_WSLG_START_DAEMONS:-1}" = "1" ]; then
    old_ifs="$IFS"
    IFS=',; '
    for endpoint in $FIELDMESH_DISCOVERY_CANDIDATES; do
        case "$endpoint" in
            *:*)
                start_daemon_if_needed "${endpoint%:*}" "${endpoint##*:}" || true
                ;;
        esac
    done
    IFS="$old_ifs"
fi

needs_build=0
if [ ! -x "$gui_app" ]; then
    needs_build=1
else
    for src in \
        "$app_dir/fieldmesh_imgui_control_app.cpp" \
        "$app_dir/fieldmesh_imgui_glfw_main.cpp" \
        "$app_dir/fieldmesh_imgui_embedded_python.cpp" \
        "$app_dir/fieldmesh_imgui_embedded_resources.h" \
        "$app_dir/Makefile" \
        "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
        "$repo_root/sdk/c/include/fieldmesh_sdk.h"
    do
        if [ "$src" -nt "$gui_app" ]; then
            needs_build=1
            break
        fi
    done
fi

if [ "$needs_build" -eq 1 ]; then
    if [ "$auto_build" -eq 1 ] && [ -f "$imgui_dir/imgui.cpp" ]; then
        echo "fieldmesh-wslg: building GUI binary with IMGUI_DIR=$imgui_dir" >&2
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
