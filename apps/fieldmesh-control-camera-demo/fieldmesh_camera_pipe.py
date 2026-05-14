#!/usr/bin/env python3
"""Host camera/preview process-pipe helper for fieldmesh-control-camera-demo.

The C++ app owns FieldMesh control/data-plane policy through the pure-C SDK.
This helper keeps platform camera dependencies outside that SDK boundary by
providing commands that either copy deterministic byte streams for tests or
describe FFmpeg/GStreamer capture and preview commands for real hosts.
"""

from __future__ import annotations

import argparse
import json
import shlex
import sys
from pathlib import Path


def shell_join(args: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in args)


def copy_file_to_stdout(path: Path) -> int:
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                return 0
            sys.stdout.buffer.write(chunk)


def copy_stdin_to_file(path: Path) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as sink:
        while True:
            chunk = sys.stdin.buffer.read(1024 * 1024)
            if not chunk:
                return 0
            sink.write(chunk)


def ffmpeg_capture_command(args: argparse.Namespace) -> str:
    common = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "warning",
    ]
    if args.platform == "windows":
        source = [
            "-f",
            "dshow",
            "-framerate",
            str(args.fps),
            "-video_size",
            f"{args.width}x{args.height}",
            "-i",
            f"video={args.device}",
        ]
    elif args.platform == "macos":
        source = [
            "-f",
            "avfoundation",
            "-framerate",
            str(args.fps),
            "-video_size",
            f"{args.width}x{args.height}",
            "-i",
            args.device,
        ]
    else:
        source = [
            "-f",
            "v4l2",
            "-framerate",
            str(args.fps),
            "-video_size",
            f"{args.width}x{args.height}",
            "-i",
            args.device,
        ]
    encode = [
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-tune",
        "zerolatency",
        "-b:v",
        f"{args.bitrate_kbps}k",
        "-f",
        "mpegts",
        "pipe:1",
    ]
    return shell_join(common + source + encode)


def ffmpeg_preview_command() -> str:
    return shell_join(
        [
            "ffplay",
            "-hide_banner",
            "-loglevel",
            "warning",
            "-fflags",
            "nobuffer",
            "-flags",
            "low_delay",
            "-framedrop",
            "-",
        ]
    )


def gstreamer_capture_command(args: argparse.Namespace) -> str:
    if args.platform == "windows":
        source = f"ksvideosrc device-name={shlex.quote(args.device)}"
    elif args.platform == "macos":
        source = f"avfvideosrc device-index={shlex.quote(args.device)}"
    else:
        source = f"v4l2src device={shlex.quote(args.device)}"
    return (
        f"gst-launch-1.0 -q {source} ! "
        f"video/x-raw,width={args.width},height={args.height},framerate={args.fps}/1 ! "
        "videoconvert ! x264enc tune=zerolatency speed-preset=ultrafast "
        f"bitrate={args.bitrate_kbps} key-int-max={args.fps} ! "
        "mpegtsmux ! fdsink fd=1"
    )


def gstreamer_preview_command() -> str:
    return (
        "gst-launch-1.0 -q fdsrc fd=0 ! tsdemux ! h264parse ! avdec_h264 ! "
        "videoconvert ! autovideosink sync=false"
    )


def native_placeholder_capture_command(args: argparse.Namespace) -> str:
    helper = "fieldmesh-native-camera-capture"
    return shell_join(
        [
            helper,
            "--device",
            args.device,
            "--width",
            str(args.width),
            "--height",
            str(args.height),
            "--fps",
            str(args.fps),
            "--bitrate-kbps",
            str(args.bitrate_kbps),
            "--stdout",
        ]
    )


def native_placeholder_preview_command() -> str:
    return shell_join(["fieldmesh-native-camera-preview", "--stdin"])


def build_preset(args: argparse.Namespace) -> dict[str, object]:
    if args.backend == "ffmpeg":
        camera_command = ffmpeg_capture_command(args)
        preview_command = ffmpeg_preview_command()
    elif args.backend == "gstreamer":
        camera_command = gstreamer_capture_command(args)
        preview_command = gstreamer_preview_command()
    else:
        camera_command = native_placeholder_capture_command(args)
        preview_command = native_placeholder_preview_command()

    app_command = shell_join(
        [
            args.app,
            "--camera-command",
            camera_command,
            "--preview-command",
            preview_command,
            "--chunk-size",
            str(args.chunk_size),
        ]
    )
    return {
        "event": "fieldmesh_camera_pipe_preset",
        "platform": args.platform,
        "backend": args.backend,
        "device": args.device,
        "width": args.width,
        "height": args.height,
        "fps": args.fps,
        "bitrate_kbps": args.bitrate_kbps,
        "chunk_size": args.chunk_size,
        "camera_command": camera_command,
        "preview_command": preview_command,
        "app_command": app_command,
        "sdk_abi": "pure_c",
        "capture_boundary": "external_encoded_byte_stream",
        "preview_boundary": "external_preview_command",
    }


def add_common_preset_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--platform", choices=("linux", "windows", "macos"), required=True)
    parser.add_argument("--backend", choices=("ffmpeg", "gstreamer", "native"), required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--bitrate-kbps", type=int, default=900)
    parser.add_argument("--chunk-size", type=int, default=640)
    parser.add_argument("--app", default="fieldmesh-control-camera-demo")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    capture_file = subparsers.add_parser("capture-file")
    capture_file.add_argument("--input", required=True)

    preview_file = subparsers.add_parser("preview-file")
    preview_file.add_argument("--output", required=True)

    preset = subparsers.add_parser("preset")
    add_common_preset_args(preset)

    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.command == "capture-file":
        return copy_file_to_stdout(Path(args.input))
    if args.command == "preview-file":
        return copy_stdin_to_file(Path(args.output))
    if args.command == "preset":
        print(json.dumps(build_preset(args), sort_keys=True))
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
