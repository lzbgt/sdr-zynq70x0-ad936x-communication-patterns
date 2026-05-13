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

- board identity: `node_id`, board class, friendly name;
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

The first persistent writer is host-side:
`tools/apply_fieldmesh_network_profile_ssh.py`. It reaches a board over SSH,
collects local identity evidence, requires an explicit Z203/Z103 variant match,
requires `fieldmeshctl` and `fw_setenv` by default, saves a rollback backup,
and only writes U-Boot environment keys when both `--apply` and
`--allow-persistent-writes` are present.

Current commands are explicit and scriptable:

```sh
fieldmeshctl profile show
fieldmeshctl profile validate \
  --node-id z103-endpoint \
  --network-id fieldmesh-lab \
  --friendly-name "Z103 endpoint" \
  --usb-device-ip 192.168.3.1 \
  --usb-host-ip 192.168.3.10 \
  --prefix 24 \
  --ap-policy hybrid \
  --preferred-ap-id z203-hub
fieldmeshctl profile apply \
  --node-id z103-endpoint \
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
  --node-id z103-endpoint \
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
  --node-id z103-endpoint \
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

The SDK should expose the same profile as a C ABI:

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
control.

The first ABI covers:

- board identity: `node_id`, `network_id`, friendly name;
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
   readiness on both boards, while explicitly asserting that inter-board IP
   routing is not part of the design.

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
  `hostname=z103-endpoint`, `ipaddr=192.168.3.1`, `ipaddr_host=192.168.3.10`,
  `fieldmesh_node_id=z103-endpoint`, `fieldmesh_network_id=fieldmesh-lab`,
  `fieldmesh_preferred_ap=z203-hub`, and `fieldmesh_ap_policy=hybrid`;
- a BusyBox/u-boot-tools quirk was found: `fw_setenv -s FILE` returned success
  but wrote empty values, so the writer now applies each key with individual
  `fw_setenv key value` calls;
- after reboot, `192.168.2.1` resolved to Z203 and `192.168.3.1` resolved to
  Z103;
- refreshed Z103 firmware now makes `fieldmeshctl profile show` report the
  persistent profile from U-Boot env.
- the split subnets are host management paths only; the radio data-plane gate
  is now tracked separately by `tools/run_fieldmesh_two_board_radio_gate.sh`.
