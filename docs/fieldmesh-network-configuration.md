# FieldMesh Network Configuration Interface

FieldMesh firmware should expose network configuration through two surfaces:

- a local CLI for provisioning, recovery, and factory/debug workflows;
- the pure-C SDK/control-plane API for applications that browse, join, elect,
  route, stream, and read RTLS state.

Both surfaces should operate on the same persistent network profile.

## Why This Matters

Pluto-style images default to `192.168.2.1` on USB Ethernet. When both the
1R1T and 2R2T boards are attached to the same host, the host can see two
RNDIS devices with the same device-side address. That makes SSH, IIO, and SDK
traffic ambiguous unless each board is placed on a distinct subnet or attached
through a host/network path with explicit routing.

The firmware must therefore support configuration before two-board experiments:

- board identity: `device_eui`, `device_type`, `node_id`/hostname, and
  friendly name;
- network identity: `network_id`, AP policy, credential/cert/audit mode;
- USB Ethernet profile: device IP, host/DHCP range, netmask, hostname;
- physical Ethernet profile when present;
- AP preference/election policy;
- radio profile: frequency plan, bandwidth, stream class limits, legal region;
- RTLS/time profile: GPS/PPS source, timing calibration, packet-timing mode;
- persistence and rollback.

## CLI Shape

The first shipped board CLI surface is `/usr/bin/fieldmeshctl`. It validates
and accepts a profile into the SDK reference context, reports whether
persistence/reboot/rollback would be required, and does not itself write init
scripts, U-Boot environment, or host routing. On board images it also overlays
`profile show` from `fw_printenv` when those persistent keys are present, so
operators see the active USB subnet and FieldMesh identity instead of a
compiled SDK default.

`device_eui` is the stable compact device identity for routing, security, peer
databases, and AP election reports. It is six bytes encoded as 12 hex
characters. It is not the model/type code: multiple 2R2T or 1R1T boards share
the same `DTYPE` class, but must have different EUIs.

Because a board can boot either QSPI or SD images, the provisioned EUI is
mirrored into boot-source-neutral storage:

1. `/mnt/jffs2/fieldmesh/device_eui` is the FieldMesh identity mirror and is
   preferred by board init when present.
2. U-Boot environment key `fieldmesh_device_eui` is written when `fw_setenv`
   is available, so bootloader and recovery tooling see the same identity.
3. `/etc/fieldmesh/device_eui` is written as a local image seed when the active
   root filesystem is writable.

Daemon startup exports the first valid 12-hex EUI from that order as
`FIELDMESH_DEVICE_EUI`, and the daemon also reads those files directly when run
without the init wrapper. `node_id`, Linux hostname, and friendly name are human
labels only; they must not imply board capability or current role.

The first persistent writer is host-side:
`tools/apply_fieldmesh_network_profile_ssh.py`. It reaches a board over SSH,
collects local identity evidence, requires an explicit Z203/Z103 variant match,
requires `fieldmeshctl` and `fw_setenv` by default, saves a rollback backup,
and only writes persistent state when both `--apply` and
`--allow-persistent-writes` are present. A successful apply writes both the
U-Boot environment key and the identity mirrors above, so the same board EUI is
seen after either QSPI or SD boot.

Applications should use the SDK/daemon identity path instead of shelling out.
The SDK exposes `fieldmesh_set_daemon_device_identity()`, which sends
`FIELDMESH_DEVICE_IDENTITY_SET` to the selected board daemon. The request
contains the current EUI compare-and-swap guard, the new 12-hex EUI,
persistence and reboot flags, duplicate-observed-EUI rejection, and dry-run
mode. The board daemon validates the EUI, rejects duplicate observed peer EUIs
when requested, and refuses real writes unless it is running under authenticated
admin control with identity-write authorization. When authorized, the daemon
writes the same three identity stores: `/mnt/jffs2/fieldmesh/device_eui`,
U-Boot `fieldmesh_device_eui`, and writable `/etc/fieldmesh/device_eui`.

Current commands are explicit and scriptable:

```sh
fieldmeshctl profile show
fieldmeshctl profile validate \
  --device-eui 020000000103 \
  --node-id node-b \
  --network-id fieldmesh-lab \
  --friendly-name "Z103 lab board" \
  --usb-device-ip 192.168.3.1 \
  --usb-host-ip 192.168.3.10 \
  --prefix 24 \
  --ap-policy hybrid \
  --preferred-ap-id 020000000203
fieldmeshctl profile apply \
  --device-eui 020000000103 \
  --node-id node-b \
  --network-id fieldmesh-lab \
  --usb-device-ip 192.168.3.1 \
  --usb-host-ip 192.168.3.10 \
  --prefix 24 \
  --persist
fieldmeshctl profile rollback
```

Host-side persistent staging uses the same profile values:

```sh
tools/apply_fieldmesh_network_profile_ssh.py \
  --host 192.168.2.1 \
  --variant z103 \
  --device-eui 020000000103 \
  --node-id node-b \
  --network-id fieldmesh-lab \
  --usb-device-ip 192.168.3.1 \
  --usb-host-ip 192.168.3.10 \
  --prefix 24
```

That command only prints a JSON plan. A real write requires:

```sh
tools/apply_fieldmesh_network_profile_ssh.py \
  --host 192.168.2.1 \
  --variant z103 \
  --device-eui 020000000103 \
  --node-id node-b \
  --network-id fieldmesh-lab \
  --usb-device-ip 192.168.3.1 \
  --usb-host-ip 192.168.3.10 \
  --prefix 24 \
  --apply \
  --allow-persistent-writes \
  --reboot
```

The board must first be running a FieldMesh runtime that contains
`fieldmeshctl`. For Pluto-style QSPI images, the guarded installer is:

```sh
APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.2.1
```

The installer records target identity, package hash, update log, and reboot
output, and refuses to write unless the reachable board matches the requested
variant and exposes `mtd3 "qspi-linux"` plus `/sbin/update_frm.sh`.

The CLI currently prints NDJSON by default, because it is used directly by
host-side test runners and later board-side provisioning tools. The intended
production expansion is to add subcommands for credential storage, radio
profiles, persistent OS application, live reachability checks, and automatic
rollback.

## SDK Shape

The SDK should expose the same profile as a C ABI and should keep two layers
separate:

- **Host-facing Ethernet/IP layer:** portable socket API over USB Ethernet,
  physical Ethernet, or routed IP. This is where desktop, embedded Linux,
  Windows, and macOS applications browse APs, join, command roles, inspect
  topology, and send/receive application streams through the local board.
- **Local device/IIO layer:** board-local or trusted host tooling for AD936x
  PHY configuration, IIO scan/plan, IQ buffer tests, sidecar DMA readiness, and
  recovery diagnostics. This layer controls the local board/radio resources; it
  is not the board-to-board mesh network.

The application SDK normally uses the Ethernet/IP layer. For those clients,
there should be a pre-implemented FieldMesh mesh gateway daemon running on the
Zynq ARM Linux OS. The daemon listens on the configured SDK control port, owns
the board-local `swarm0` routed packet interface plus the local IIO/device
admin backend, and serves the FieldMesh Ethernet protocol to host
applications. Host apps do not need direct libiio access for normal operation,
and they do not host `swarm0`; they see ordinary IP routes through the board.
The IIO/device layer is still part of the product SDK boundary, but it should
be exposed as an explicit device-control backend with stronger safety and
permissions because it can configure RF and buffers.

The SDK ABI itself remains pure C. The board mesh gateway daemon and richer demo
clients/apps may be C++ implementations that link or wrap the C SDK ABI.

The profile API remains common:

```c
fieldmesh_get_network_profile(ctx, &profile);
fieldmesh_set_network_profile(ctx, &profile);
fieldmesh_validate_network_profile(ctx, &profile, &report);
fieldmesh_apply_network_profile(ctx, &profile, FIELDMESH_PROFILE_APPLY_PERSIST,
                                &report);
fieldmesh_rollback_network_profile(ctx);
```

Applications should not shell out for normal runtime control. The CLI is for
humans, manufacturing, provisioning, and recovery. The SDK is for application
control. Internal tools and the board mesh gateway daemon may use libiio or
board-local probes, but customer payload routing still stays on FieldMesh RF
once it leaves the host-facing local board link.

The first ABI covers:

- board identity: `device_eui`, `device_type`, `node_id`, `network_id`, and
  friendly name;
- USB Ethernet split-subnet planning: device IP, host IP, prefix;
- optional physical Ethernet addressing;
- AP policy: predefined, autonomous swarm, or hybrid;
- preferred AP ID and emergency 1R1T AP allowance;
- radio frequency and bandwidth metadata;
- validation report fields for reboot, persistence, and rollback handling.

## Initial Two-Board Host Plan

For the current Z203/Z103 lab setup:

1. Keep Z203 on `192.168.2.1/24` until the 2R2T installed runtime is verified.
2. Move Z103 USB Ethernet to a second subnet, for example
   `192.168.3.1/24`, with host-side `192.168.3.10/24`, using the
   `fieldmeshctl profile validate/apply` shape first and the guarded
   persistent SSH writer once the target is known.
The USB Ethernet addresses are host-facing management/control interfaces only.
They are not the board-to-board data network. Applications, SDK demos, and test
runners may use those host links to command each board, inspect state, and
collect captures, but Z203 and Z103 peer traffic must move over the FieldMesh
radio/sidecar data plane.

3. Run host-orchestrated board readiness from one PC or two PCs:

   ```sh
   Z203_IP=192.168.2.1 Z103_IP=192.168.3.1 \
     tools/run_fieldmesh_two_board_radio_gate.sh
   ```

   This verifies both host-facing management paths and sidecar packet DMA
   readiness on both boards, runs read-only AD936x IIO scan/plan capture on
   both boards, emits `rf_binding_plan.json`, and explicitly asserts that
   inter-board IP routing is not part of the design. The RF binding plan opens
   no IIO buffers and starts no RF TX; it is the last read-only gate before a
   conducted or shielded radio test.

4. Run the Z203 AP service on the PC/interface attached to Z203:

   ```sh
   fieldmesh-two-pc-flow-demo ap-service 0.0.0.0 49125 5 3000
   ```

5. Run the endpoint control flow from the PC/interface attached to Z103. The
   endpoint application commands the Z103 board locally, but the peer payload
   path must be FieldMesh RF, not `192.168.2.1` from the Z103 Linux network
   namespace:

   ```sh
   fieldmesh-two-pc-flow-demo endpoint-flow 192.168.2.1 49125 3000
   ```

6. Once both control planes are distinct, replace deterministic demo responses
   with real AP admission, peer registry, route query, and RF-backed stream
   transport.

## Two-Host Camera Stream Demo Target

The practical application demo should be one portable host app that can act as
source, sink, or both. The preferred production app can be C++ for camera,
preview, and UI work; Rust is also a good supported app target through a Rust
SDK/binding paired with the pure-C SDK ABI:

```text
Host A camera app
  -> USB Ethernet or physical Ethernet SDK data socket
  -> peer board A
  -> FieldMesh RF data plane
  -> peer board B
  -> USB Ethernet or physical Ethernet SDK data socket
  -> Host B preview app
```

Host A and Host B may be the same physical PC for lab testing, as long as the
test treats them as two logical hosts with separate board-facing interfaces and
separate app instances. The customer architecture remains the same when those
apps move to two different PCs or embedded hosts.

The demo has two planes:

- **Control plane:** SDK commands over host-facing USB/physical Ethernet:
  browse APs, join/audit, elect or command AP/proactive role, discover peers,
  open a stream, subscribe to a stream, query RTLS/link state, and adapt
  bitrate or route policy.
- **Data plane:** camera frames are packetized as prioritized FieldMesh streams
  and must cross the board-to-board RF path. Host-facing IP is only the ingress
  and egress API to each local board; it is not the inter-board network.

The topology viewer in this app is a radio topology viewer. It should show
AP/coordinator state, peer discovery, direct RF links, relay paths, scheduled
slots, RTLS/relative colocating confidence, and route quality. It should not
draw the host USB Ethernet or physical Ethernet links as mesh links.

Suggested stream classes:

- C0/C1: session control, keepalive, route changes, camera metadata, and
  bitrate-control feedback.
- C2: video base layer with bounded latency and drop-old-frame behavior.
- C3: enhancement frames or opportunistic quality increase.
- C4: file snapshots, logs, or bulk transfer.

The first implementation can use simple intra-frame chunks or JPEG/H.264/H.265
access units from a Windows camera pipeline. The SDK-facing ABI should stay C
and transport-neutral so the same application can run on Windows, Linux,
macOS, or embedded Linux. A later GUI can wrap the same SDK calls for camera
selection and preview.

## Safety

Profile application must be transactional:

- validate before writing;
- save previous profile;
- apply runtime changes;
- verify SSH/control-plane reachability if requested;
- roll back automatically on failure unless `--no-rollback` is passed.

No permanent credential writes should be enabled until recovery paths are
stable on both Z203 and Z103.

The board-local `fieldmeshctl` still stops before permanent writes; it is the
common CLI/SDK profile surface. The SSH writer is the guarded persistent path.
With both boards attached, plain `192.168.2.1` may resolve to either USB
gadget, so the writer refuses to write if the reachable target does not match
the requested variant or if `fieldmeshctl` is missing, unless the operator
intentionally overrides that guard. This still does not solve USB interface
selection by itself; it makes the actual write auditable once the target route
is known.

## Live Split-Subnet Status

The 2026-05-14 Z103 bring-up proved this path on hardware:

- the stock Z103 first refused the persistent writer because `fieldmeshctl` was
  missing;
- after the matched FieldMesh `pluto.frm` was installed, the writer applied
  `hostname=node-b`, `ipaddr=192.168.3.1`, `ipaddr_host=192.168.3.10`,
  `fieldmesh_device_eui=020000000103`, `fieldmesh_node_id=node-b`,
  `fieldmesh_network_id=fieldmesh-lab`,
  `fieldmesh_preferred_ap=020000000203`, and `fieldmesh_ap_policy=hybrid`;
- a BusyBox/u-boot-tools quirk was found: `fw_setenv -s FILE` returned success
  but wrote empty values, so the writer now applies each key with individual
  `fw_setenv key value` calls;
- after reboot, `192.168.2.1` resolved to Z203 and `192.168.3.1` resolved to
  Z103;
- refreshed Z103 firmware now makes `fieldmeshctl profile show` report the
  persistent profile from U-Boot env.
- the split subnets are host management paths only; the radio data-plane gate
  is now tracked separately by `tools/run_fieldmesh_two_board_radio_gate.sh`.
