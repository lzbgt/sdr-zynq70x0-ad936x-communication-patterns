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

The first shipped CLI surface is `/usr/bin/fieldmeshctl`. It is intentionally
non-mutating for now: it validates and accepts a profile into the SDK reference
context, reports whether persistence/reboot/rollback would be required, and
does not yet write init scripts, U-Boot environment, or host routing.

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
   `fieldmeshctl profile validate/apply` shape first and the later persistent
   OS writer once implemented.
3. Run the Z203 AP service on one PC/interface:

   ```sh
   fieldmesh-two-pc-flow-demo ap-service 0.0.0.0 49125 5 3000
   ```

4. Run the endpoint flow from the other PC/interface:

   ```sh
   fieldmesh-two-pc-flow-demo endpoint-flow 192.168.2.1 49125 3000
   ```

5. Once both control planes are distinct, replace deterministic demo responses
   with real AP admission, peer registry, route query, and stream transport.

## Safety

Profile application must be transactional:

- validate before writing;
- save previous profile;
- apply runtime changes;
- verify SSH/control-plane reachability if requested;
- roll back automatically on failure unless `--no-rollback` is passed.

No permanent credential writes should be enabled until recovery paths are
stable on both Z203 and Z103.

The current implementation stops before permanent writes. This is deliberate:
with both boards attached, plain `192.168.2.1` may resolve to either USB
gadget, so the next writer must identify the target board by USB interface,
serial, hostname, or an already-separated route before touching persistent
network state.
