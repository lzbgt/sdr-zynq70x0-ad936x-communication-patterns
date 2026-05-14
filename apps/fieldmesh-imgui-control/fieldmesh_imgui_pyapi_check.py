#!/usr/bin/env python3
import sys

from fieldmesh_imgui_pyapi import FieldMeshGuiClient


def main() -> int:
    client = FieldMeshGuiClient(sys.argv[1], sys.argv[2])
    selected = client.select_board("020000000103")
    if selected.selected_board_eui != "020000000103":
        raise SystemExit("Python API board selection failed")
    if selected.connected_to_board is not True or selected.current_page != "chat":
        raise SystemExit("Python API board selection did not enter chat page")
    if not selected.bundled_trust_bundle:
        raise SystemExit("Python API did not expose bundled trust bundle")
    if selected.user_runs_shell_scripts:
        raise SystemExit("GUI workflow must not require shell scripts")
    elected = client.elect_ap("020000000103")
    if elected.selected_ap_eui != "020000000103":
        raise SystemExit("Python API AP election failed")
    chat = client.open_chat("020000000103")
    if chat.selected_conversation_eui != "020000000103":
        raise SystemExit("Python API open chat failed")
    message = client.send_message("hello from python")
    if message.messages_sent != 1 or message.last_message_text != "hello from python":
        raise SystemExit("Python API message send failed")
    publisher = client.publish_camera("020000000103")
    if publisher.camera_publish_enabled:
        raise SystemExit("Python API video invite must not force publish state")
    if not publisher.video_invite_pending or publisher.camera_dst_eui != "020000000103":
        raise SystemExit("Python API video invite action failed")
    if publisher.operation_status != "python_api_video_invite_sent":
        raise SystemExit("Python API video invite status failed")
    subscriber = client.subscribe_camera("020000000203")
    if not subscriber.camera_preview_enabled:
        raise SystemExit("Python API subscribe action failed")
    if subscriber.operation_status != "python_api_camera_subscribe_started":
        raise SystemExit("Python API subscribe status failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
