# FieldMesh Native TCP/IP Gateway

Status: production requirement and current daemon capability contract.

## Objective

FieldMesh must be usable by normal client applications without a custom IM,
video, or radio SDK integration. A camera, robot computer, ship computer, PLC,
or Windows/Linux/macOS application should be able to use ordinary TCP/IP sockets
through a local FieldMesh board.

The default product mode is therefore a routed Layer-3 gateway:

```text
client app -> host TCP/UDP/IP -> local board eth0/usb0
  -> board routing/firewall/QoS -> swarm0 TUN
  -> meshd -> BLR MAC/PHY over RF
  -> peer meshd -> peer swarm0 -> peer host TCP/UDP/IP
```

The golden IM/video app remains a proof of SDK and UX capability. It is not the
only product API. Native TCP/IP is the customer-facing default.

## Operating Modes

FieldMesh boards must support two product modes:

1. **SDK mode.** A client app links the SDK or talks to the board daemon for
   explicit FieldMesh operations: peer discovery, AP election, RTLS/topology,
   messaging, video session control, radio policy, provisioning, diagnostics,
   and admin operations. This is the mode used by the golden IM/video app when
   it wants FieldMesh-specific UX and control-plane visibility.
2. **Native IP gateway mode.** The board appears to client applications as an
   ordinary IP gateway. Apps use normal TCP/UDP/ICMP sockets and do not need to
   know about radio frames, BLR MAC, AP relay policy, RTLS, or the SDK. The
   board daemon owns `swarm0`, packetizes IP traffic into FieldMesh classes,
   receives RF/adapter packets back into `swarm0`, and exposes normal routes on
   the host-facing USB Ethernet or physical Ethernet interface.

The preferred product path is board-owned gateway mode: the host sees a normal
network interface and route to the FieldMesh board. A host-side virtual NIC
driver, such as Wintun/TAP/utun/tun, is an optional packaging layer for desktop
apps that want a local virtual adapter, but it must feed the same board daemon
and BLR packet path. It is not a replacement for the board's native routed
gateway.

## Requirements

- `swarm0` is created and owned on the Zynq board, not on the host PC.
- Client applications use ordinary IPv4/IPv6 sockets: TCP, UDP, ICMP, RTP,
  SRT-like streams, SSH, HTTP, MQTT, ROS, or vendor protocols.
- The board daemon advertises `supports_native_ip_gateway=1`,
  `supports_tcp_ip_client_apps=1`, `native_client_ip_mode=routed_l3_swarm0`,
  and `native_client_ip_interface=swarm0`.
- Host-facing interfaces remain normal OS networking: USB Ethernet, physical
  Ethernet, Wi-Fi, or an embedded LAN.
- The default is routed Layer-3, not transparent Layer-2 bridging.
- TAP/bridge mode is optional compatibility only, with explicit broadcast and
  multicast controls.
- IIO is not in the customer payload path. It remains RF admin, calibration,
  diagnostics, and conducted-test infrastructure.

## Addressing Model

Each physical board has a unique 6-byte EUI. IP addressing is assigned above
that identity:

- board-local mesh interface: `swarm0`;
- mesh IPv4 planning subnet: `10.77.0.0/16` until a deployment changes it;
- optional IPv6 ULA prefix: deployment-provisioned;
- peer routes: per-board `/32` or site subnet routes for IPv4, and equivalent
  IPv6 routes;
- host-facing IP: configured on USB/physical Ethernet and advertised to the
  client as the gateway.

The EUI is radio identity. IP addresses are routing configuration. They must
not be hardcoded into the app or SDK.

## TCP Behavior

TCP must be supported as a first-class payload, but the radio should not pretend
to be Ethernet or Wi-Fi. The gateway is responsible for:

- MTU selection for `swarm0`;
- TCP MSS clamping on host-facing ingress when needed;
- fragmentation/reassembly below the IP packet boundary when RF frame MTU is
  smaller than the IP packet;
- ACK and small-control-packet prioritization so TCP does not self-collapse
  under asymmetric load;
- duplicate and stale-fragment suppression;
- route failover without silently reordering active flows beyond the configured
  window;
- exposing counters for retransmission pressure, queue age, dropped stale
  fragments, RTT estimate, and selected route.

## QoS Mapping

The daemon classifies native IP packets before they enter BLR RF frames:

| IP traffic | FieldMesh class | Notes |
| --- | --- | --- |
| control, emergency, SSH keepalive, TCP SYN/FIN/RST | C0 | Low latency, protected. |
| telemetry, ICMP, routing, small ACKs | C1 | Periodic/protected. |
| video base, real-time RTP/SRT base layer | C2 | Bounded latency, drop stale. |
| video enhancement, rich sensor streams | C3 | Opportunistic. |
| file transfer, logs, updates | C4 | Backpressure first. |

The classifier may use DSCP, port policy, stream hints, and application
registration. Unknown TCP defaults to C4 until policy promotes it.

## Security

Native IP support does not bypass FieldMesh security:

- board control remains mutually authenticated and authorized;
- RF packets are authenticated and encrypted according to the joined network
  policy;
- client subnets and routes are policy objects, not implicit trust;
- management operations such as EUI changes require admin authorization;
- bridge/TAP mode must not be enabled without explicit policy because it
  expands the attack and broadcast surface.

## Verification Gates

Minimum production gates for native TCP/IP:

- daemon HELLO advertises native IP capability and `swarm0` mode;
- board creates and rolls back `swarm0` under guarded `CAP_NET_ADMIN`;
- daemon burst-pumps multiple TUN callback packets through the FieldMesh
  adapter with the request-supplied peer EUI;
- daemon drains multiple FieldMesh adapter packets back into board-local
  `swarm0`, proving the RF/adapter-to-client-kernel direction;
- SDK stream queues preserve same-class bursts instead of collapsing them into
  a single last-packet slot;
- daemon owns a guarded TUN event-loop step that performs both directions in
  one bounded operation and reports `next_boundary=continuous_tun_event_loop`;
- host route to a remote mesh peer works through the local board;
- `ping`/ICMP succeeds through the radio path;
- TCP `iperf3` or an equivalent socket test passes with measured throughput,
  RTT, retransmits, and drop counters;
- UDP video traffic and TCP bulk traffic together preserve C0/C1 latency;
- AP relay and graph relay preserve TCP sessions across route changes within
  the specified disruption budget;
- transparent bridge mode is separately gated and disabled by default.
