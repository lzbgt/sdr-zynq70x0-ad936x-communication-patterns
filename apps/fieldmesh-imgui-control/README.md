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
- embedded public command-CA trust metadata, auth policy schema, and codec
  defaults, so normal users launch the app instead of running shell scripts;
- runtime identity from peer discovery, provisioning, or an external profile,
  never hardcoded app EUIs or board endpoints compiled into the app;
- an in-process embedded Python module named `fieldmesh_imgui`, matching the
  standard desktop-app pattern used by tools such as KiCad. It exposes app
  actions directly from inside the GUI process rather than shelling out to the
  executable.

The app bundle may include public trust anchors, certificate fingerprints,
profile schema, codec presets, and policy metadata. It must not compile in
deployment identity such as app/device EUIs, board hostnames, daemon IPs, or
fixed peer lists. That information comes from discovery, provisioning, or an
external runtime profile used by tests. The app also must not bundle the
command CA private key. Per-device private keys should live in the OS key
store, secure element, or board-side secure storage.

The default `make check` target builds a dependency-free headless check that
verifies the GUI state model, ImGui render source, embedded resource contract,
and embedded Python API source. In CI, `fieldmesh_imgui_pyapi.py` is only a
subprocess test harness for the headless binary; it is not the production app
Python API. To build the Dear ImGui app-core target, provide an ImGui checkout:

```sh
make -C apps/fieldmesh-imgui-control gui IMGUI_DIR=/path/to/imgui
```

To build a visible desktop window, use the GLFW/OpenGL3 platform backend. This
links Dear ImGui's standard `imgui_impl_glfw` and `imgui_impl_opengl3`
backends, then runs the same FieldMesh IM app state and render function:

```sh
make -C apps/fieldmesh-imgui-control gui-glfw IMGUI_DIR=/path/to/imgui
```

To build the GUI with the embedded Python interpreter and in-process
`fieldmesh_imgui` module, use Python development headers/libs:

```sh
make -C apps/fieldmesh-imgui-control gui-glfw-python IMGUI_DIR=/path/to/imgui
```

On Arch Linux under WSL, GUI windows are bridged to the Windows host by WSLg.
The app still runs as a Linux process in WSL; WSLg exposes windows through its
X11/Wayland sockets and audio/GPU bridge. The FieldMesh launcher sets the same
bridge environment used by the adjacent `../wsl-archlinux-gui` reference. Once
the GLFW/OpenGL3 binary is built or packaged, launch it through this bridge:

```sh
tools/run_fieldmesh_imgui_wslg.sh --check-bridge

make -C apps/fieldmesh-imgui-control gui-glfw-python IMGUI_DIR=/path/to/imgui

GUI_APP=.config/fieldmesh/imgui-control-build/fieldmesh-imgui-control-glfw \
tools/run_fieldmesh_imgui_wslg.sh --detach \
    --profile apps/fieldmesh-imgui-control/testdata/golden_lab.profile \
    --instance fieldmesh-peer-a

GUI_APP=.config/fieldmesh/imgui-control-build/fieldmesh-imgui-control-glfw \
tools/run_fieldmesh_imgui_wslg.sh --detach \
    --profile apps/fieldmesh-imgui-control/testdata/golden_lab.profile \
    --instance fieldmesh-peer-b
```

Those two instances should appear as normal Windows desktop windows after the
platform backend is linked. In a packaged product this WSLg environment setup
belongs in the desktop shortcut/app bundle, not in an operator shell workflow.

Platform backends such as GLFW, SDL, DirectX, Metal, or Vulkan stay outside the
pure-C SDK. The app core should call the same daemon operations that the
command-line harness verifies: `FIELDMESH_HELLO`,
`FIELDMESH_APP_CONTROL_CAMERA`, `FIELDMESH_CAMERA_SESSION_PLAN`,
`FIELDMESH_ROUTE_METRICS`, `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and
`FIELDMESH_CAMERA_STREAM_CHUNK`.

The shell scripts and `testdata/golden_lab.profile` are developer/CI gates, not
the end-user workflow. Two symmetric instances can be smoke-tested without a
display during development:

```sh
./tools/run_fieldmesh_two_imgui_instances.sh
```
