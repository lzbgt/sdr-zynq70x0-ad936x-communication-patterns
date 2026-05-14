#!/usr/bin/env python3
"""Subprocess test harness for the FieldMesh ImGui control app.

The production GUI embeds Python in-process as module ``fieldmesh_imgui``.
This file is deliberately only a CI/headless test harness for environments
without Python development headers or a windowing backend. It must not be
documented as the user-facing app Python API.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory


@dataclass(frozen=True)
class FieldMeshGuiSnapshot:
    raw: dict

    @property
    def selected_board_eui(self) -> str:
        return str(self.raw["selected_board_eui"])

    @property
    def selected_ap_eui(self) -> str:
        return str(self.raw["selected_ap_eui"])

    @property
    def camera_dst_eui(self) -> str:
        return str(self.raw["camera_dst_eui"])

    @property
    def selected_conversation_eui(self) -> str:
        return str(self.raw["selected_conversation_eui"])

    @property
    def last_message_text(self) -> str:
        return str(self.raw["last_message_text"])

    @property
    def messages_sent(self) -> int:
        return int(self.raw["messages_sent"])

    @property
    def camera_publish_enabled(self) -> bool:
        return bool(self.raw["camera_publish_enabled"])

    @property
    def video_invite_pending(self) -> bool:
        return bool(self.raw["video_invite_pending"])

    @property
    def connected_to_board(self) -> bool:
        return bool(self.raw["connected_to_board"])

    @property
    def current_page(self) -> str:
        return str(self.raw["current_page"])

    @property
    def camera_preview_enabled(self) -> bool:
        return bool(self.raw["camera_preview_enabled"])

    @property
    def operation_status(self) -> str:
        return str(self.raw["operation_status"])

    @property
    def bundled_trust_bundle(self) -> bool:
        return bool(self.raw["bundled_trust_bundle"])

    @property
    def user_runs_shell_scripts(self) -> bool:
        return bool(self.raw["user_runs_shell_scripts"])


class FieldMeshGuiClient:
    def __init__(self, app: str | Path, profile: str | Path | None = None):
        self.app = Path(app)
        self.profile = Path(profile) if profile else None

    def snapshot(self, *args: str) -> FieldMeshGuiSnapshot:
        with TemporaryDirectory(prefix="fieldmesh-imgui-api-") as tmp:
            output = Path(tmp) / "snapshot.json"
            command = [
                str(self.app),
                "--self-test",
            ]
            if self.profile:
                command.extend(["--profile", str(self.profile)])
            command.extend([
                "--snapshot-output",
                str(output),
                *args,
            ])
            subprocess.run(command, check=True)
            return FieldMeshGuiSnapshot(json.loads(output.read_text(encoding="utf-8")))

    def browse_peers(self) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-browse")

    def select_board(self, device_eui: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-select-board", device_eui)

    def elect_ap(self, device_eui: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-elect-ap", device_eui)

    def open_chat(self, peer_eui: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-open-chat", peer_eui)

    def send_message(self, text: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-send-message", text)

    def publish_camera(self, dst_device_eui: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-publish-camera", dst_device_eui)

    def subscribe_camera(self, src_device_eui: str) -> FieldMeshGuiSnapshot:
        return self.snapshot("--api-subscribe-camera", src_device_eui)
