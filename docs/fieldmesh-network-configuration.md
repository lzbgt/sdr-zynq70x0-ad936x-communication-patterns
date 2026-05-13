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

Prototype commands should be explicit and scriptable:

```sh
fieldmeshctl profile show
fieldmeshctl profile set node-id z203-hub network-id fieldmesh-lab
fieldmeshctl net usb set --device-ip 192.168.20.1 --host-ip 192.168.20.10 --prefix 24
fieldmeshctl ap policy set hybrid --preferred z203-hub --allow-emergency-1r1t yes
fieldmeshctl join credential set --network fieldmesh-lab --psk-file /mnt/jffs2/fieldmesh.psk
fieldmeshctl radio profile set maritime-2m --freq-mhz 2400 --bandwidth-hz 1000000
fieldmeshctl profile validate
fieldmeshctl profile apply --persist
fieldmeshctl profile rollback
```

The CLI must print machine-readable JSON when `--json` is passed, because it
will be used by host-side test runners.

## SDK Shape

The SDK should expose the same profile as a C ABI:

```c
fieldmesh_get_network_profile(ctx, &profile);
fieldmesh_set_network_profile(ctx, &profile);
fieldmesh_validate_network_profile(ctx, &profile, &report);
fieldmesh_apply_network_profile(ctx, &profile, FIELDMESH_PROFILE_PERSIST);
```

Applications should not shell out for normal runtime control. The CLI is for
humans, manufacturing, provisioning, and recovery. The SDK is for application
control.

## Initial Two-Board Host Plan

For the current Z203/Z103 lab setup:

1. Keep Z203 on `192.168.2.1/24` until the 2R2T installed runtime is verified.
2. Move Z103 USB Ethernet to a second subnet, for example
   `192.168.3.1/24`, with host-side `192.168.3.10/24`.
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
