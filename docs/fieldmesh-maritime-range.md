# FieldMesh Maritime Range Model

This note defines how to estimate ship-to-ship FieldMesh range over sea before
field measurement data exists. It is a planning model, not a regulatory
transmit-power claim.

## Practical Estimate

For Z103/Z203-class FieldMesh links over sea, the first reliable product target
should be split by RF front end:

- **1-3 km** for low-power lab-style links, small antennas, MHz-class channels,
  and no external PA/LNA margin.
- **10-30 km** for a production ship fit with legal external PA, 10-15 dBi
  antennas mounted around 10 m above sea level, 0.5-2 MHz channels, and
  15-25 dB fade margin.
- **30-50 km** with taller antennas, narrower bandwidth, good SNR, and
  directional or higher-gain antennas.
- Longer links require lower data rate, more antenna height, more antenna gain,
  relay/AP ships, or shore infrastructure.

The maximum reliable range is usually the lower of:

1. radio horizon, and
2. link-budget range after fade margin.

## Radio Horizon

For sea-level paths, use the standard effective-Earth radio horizon estimate:

```text
horizon_km = 4.12 * (sqrt(tx_height_m) + sqrt(rx_height_m))
```

Examples:

```text
5 m + 5 m antennas     ~= 18.4 km
10 m + 10 m antennas   ~= 26.1 km
20 m + 20 m antennas   ~= 36.9 km
30 m + 30 m antennas   ~= 45.1 km
```

This is why antenna placement often matters more than another small PHY tweak
for ships.

## Link Budget

Free-space path loss:

```text
FSPL_dB = 32.44 + 20*log10(freq_MHz) + 20*log10(distance_km)
```

Receiver sensitivity:

```text
sensitivity_dBm =
  -174 + 10*log10(bandwidth_Hz)
  + receiver_noise_figure_dB
  + required_SNR_dB
  + implementation_loss_dB
```

Received power:

```text
rx_power_dBm =
  tx_power_dBm + tx_gain_dBi + rx_gain_dBi
  - cable_and_misc_losses_dB
  - FSPL_dB
```

A link is treated as reliable only when:

```text
rx_power_dBm >= sensitivity_dBm + fade_margin_dB
```

For moving ships, a **15-25 dB fade margin** is a reasonable first planning
range. Sea reflections, ship motion, antenna blockage, polarization mismatch,
spray, and interference can consume margin quickly.

## Calculator

Use `tools/fieldmesh_range_estimator.py` to make assumptions explicit:

```sh
tools/fieldmesh_range_estimator.py \
  --freq-mhz 2400 \
  --bandwidth-hz 1000000 \
  --tx-power-dbm 30 \
  --tx-gain-dbi 14 \
  --rx-gain-dbi 14 \
  --losses-db 4 \
  --rx-nf-db 6 \
  --required-snr-db 8 \
  --implementation-loss-db 3 \
  --fade-margin-db 18 \
  --tx-height-m 10 \
  --rx-height-m 10
```

With those production-planning defaults, the model is horizon-limited near
26 km. With low-power lab defaults such as 20 dBm TX power, 6 dBi antennas,
2 MHz bandwidth, 10 dB SNR, and 20 dB fade margin, the same calculator returns
roughly 1 km and is link-budget limited. Increasing bandwidth or required SNR
lowers the link-budget range; increasing antenna height raises only the
horizon; increasing antenna gain or lowering bandwidth raises only the link
budget.

## FieldMesh Behavior Over Sea

The AP/broker architecture should use this range model dynamically:

- favor AP candidates with high antenna height, relay capability, stable power,
  and central RTLS/topology position;
- prefer direct routes only when measured RSSI/SNR, packet loss, and timing
  stability meet the stream class;
- switch to AP relay or scheduled relay when two ships cannot hold a direct
  path;
- use RTLS/GPS velocity and heading to predict whether a route will survive the
  next lease window.

For ships, the most useful production metric is not just maximum distance. It
is reliable route lifetime for the next control/video/telemetry lease interval.
