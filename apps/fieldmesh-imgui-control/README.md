# FieldMesh ImGui Golden IM App

This directory is the production GUI front-end boundary for the FieldMesh
golden demo app. It is shaped like a secure IM/video app: every instance is the
same peer app, and user actions decide which peer to chat with, which live video
stream to publish, and which stream to preview. It uses Dear ImGui for the
operator surface and keeps all transport/control work behind the pure-C SDK and
the board daemon protocol.

The GUI owns:

- board selection by daemon endpoint and device EUI;
- peer discovery and conversation selection;
- messaging over the FieldMesh data plane;
- control-plane actions: peer browse, AP election, explicit AP selection, and
  capability-policy operations;
- radio network topology viewing, separate from host Ethernet topology;
- relative co-location viewing from GNSS/BDS+GPS plus packet timing;
- live video publish and preview subscription controls;
- mandatory command-CA-derived certificate mutual authentication and scoped
  authorization for demo peer sessions, with room for optional app-specific
  security above the FieldMesh security layer;
- a bundled demo runtime profile and public command-CA trust metadata, so
  normal users launch the app instead of running shell scripts;
- embedded Python automation through `fieldmesh_imgui_pyapi.py`, which drives
  the same C++ app state/API surface in headless test mode.

The app bundle may include public trust anchors, certificate fingerprints,
default board profiles, daemon ports, codec presets, and policy metadata. It
must not bundle the command CA private key. Per-device private keys should live
in the OS key store, secure element, or board-side secure storage; the demo app
only carries derived certificate identity metadata needed to authenticate and
authorize sessions.

The default `make check` target builds a dependency-free headless check that
verifies the GUI state model and ImGui render source. To build the real Dear
ImGui target, provide an ImGui checkout:

```sh
make -C apps/fieldmesh-imgui-control gui IMGUI_DIR=/path/to/imgui
```

Platform backends such as GLFW, SDL, DirectX, Metal, or Vulkan stay outside the
pure-C SDK. The app core should call the same daemon operations that the
command-line harness verifies: `FIELDMESH_HELLO`,
`FIELDMESH_APP_CONTROL_CAMERA`, `FIELDMESH_CAMERA_SESSION_PLAN`,
`FIELDMESH_ROUTE_METRICS`, `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and
`FIELDMESH_CAMERA_STREAM_CHUNK`.

The shell scripts are developer/CI gates, not the end-user workflow. Two
symmetric instances can be smoke-tested without a display during development:

```sh
./tools/run_fieldmesh_two_imgui_instances.sh
```
