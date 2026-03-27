# PTP IEEE 1588 Hardware Timestamping in OpenNIC Shell

## Overview

PTP (Precision Time Protocol, IEEE 1588) hardware timestamping lets the FPGA stamp every packet with nanosecond-resolution timestamps at the exact moment it crosses the wire. This implementation integrates Corundum PTP modules into the OpenNIC shell, enabling clock synchronization via standard tools like `ptp4l` and `phc2sys`.

## Architecture

```
 Software (ptp4l)                    AXI-Lite @ BAR2+0x18000
     |                                    |
     v                                    v
 ptp_subsystem_register ──── ptp_clock (250 MHz, 96-bit counter)
                                 |
                    ┌────────────┴────────────┐
                    v                         v
             ptp_clock_cdc             ptp_clock_cdc
             (-> 322 MHz)              (-> 322 MHz)
                    |                         |
                 CMAC 0                    CMAC 1
```

## Source Files

All PTP RTL lives in `src/ptp_subsystem/`:

| File | Description |
|------|-------------|
| `ptp_clock.v` | Master 96-bit PTP clock running at 250 MHz. Increments by a programmable period (nominally 4 ns) each cycle. Supports time loading, periodic adjustment, and drift correction. Generates PPS output. |
| `ptp_clock_cdc.v` | Phase-locked clock domain crossing from 250 MHz to each CMAC port's 322 MHz domain. Uses a PI controller and 3-stage synchronizers to maintain nanosecond-accurate time across domains. |
| `ptp_ts_extract.v` | Extracts timestamp from AXI-Stream `tuser` on the first beat of each RX frame. |
| `ptp_perout.v` | Periodic pulse generator synchronized to PTP time. Available but not currently instantiated in the subsystem. |
| `ptp_subsystem.sv` | Top-level integration: instantiates the master clock, one CDC per port, TX timestamp async FIFOs, and the register block. |
| `ptp_subsystem_register.sv` | AXI-Lite register file for software control: time set/get, adjustments, drift, and per-port TX timestamp FIFOs. |
| `stats_dma_latency.v` | Generic latency counter for DMA statistics (not PTP-specific). |

Sideband CDC for timestamps/tags is in `src/packet_adapter/`:

| File | Relevant Logic |
|------|----------------|
| `packet_adapter_rx.sv` | Captures 80-bit RX timestamp on first beat, crosses 322->250 MHz via async FIFO |
| `packet_adapter_tx.sv` | Captures 16-bit TX PTP tag on first beat, crosses 250->322 MHz via async FIFO |

## Timestamp Format

The PTP clock maintains a 96-bit timestamp:

```
 [95:48]  seconds (48 bits)
 [47:46]  2'b00 padding
 [45:16]  nanoseconds (30 bits)
 [15:0]   fractional nanoseconds (16 bits)
```

When crossing to CMAC domains, the upper 16 bits of seconds are dropped, yielding an 80-bit timestamp.

## Timestamp Datapath

### RX (Ingress)

```
CMAC RX (322 MHz)
    | [80-bit timestamp on s_axis_rx_tuser_ptp_ts]
    v
packet_adapter_rx
    |-- Captures timestamp on first beat (322 MHz domain)
    |-- Stores in async FIFO on packet completion
    v   (322 MHz -> 250 MHz, depth=64, CDC_SYNC_STAGES=2)
box_250mhz
    |-- Timestamp available in m_axis_rx_tuser_ptp_ts
    v
(QDMA descriptor integration NOT YET DONE)
```

Key points:
- CMAC provides 80-bit timestamp inline on every beat of `s_axis_rx_tuser`
- Only the first-beat timestamp is captured (one per packet)
- Async FIFO in FWFT mode ensures timestamp persists for all beats of the same packet
- **Limitation**: Timestamps reach `box_250mhz` but are not yet plumbed into QDMA completion descriptors, so software cannot receive per-packet RX timestamps through the normal datapath

### TX (Egress)

```
Software (250 MHz)
    | [16-bit PTP tag on s_axis_tx_tuser_ptp_tag]
    v
packet_adapter_tx
    |-- Captures tag on first beat (250 MHz domain)
    |-- Async FIFO (250 MHz -> 322 MHz, depth=64, CDC_SYNC_STAGES=2)
    v
CMAC TX (322 MHz)
    |-- Transmits packet, returns {80-bit timestamp, 16-bit tag}
    v
ptp_subsystem TX Timestamp FIFO
    |-- Async FIFO (322 MHz -> 250 MHz, depth=16, CDC_SYNC_STAGES=3)
    v
ptp_subsystem_register
    |-- Software polls per-port FIFO, matches tag to skb
```

Key points:
- Software assigns a 16-bit tag to each TX packet requiring a timestamp
- CMAC hardware timestamps the packet at the moment of transmission and returns the tag for matching
- Per-port FIFOs (16 entries) hold completed TX timestamps until software reads them
- TX timestamping is fully functional end-to-end

## Register Map

All registers are at BAR2 + 0x18000 (within the system address map).

### Global PTP Clock Control (offset 0x000)

| Address | R/W | Field | Bits | Description |
|---------|-----|-------|------|-------------|
| 0x000 | RW/RO | CTRL | [0] RW | PTP enable |
| 0x000 | RO | CTRL | [1] | Adjustment active |
| 0x000 | RO | CTRL | [31:16] | Version (0x0100) |
| 0x010 | RO | TS_S_LO | [31:0] | Current seconds[31:0] — **reading triggers atomic snapshot** |
| 0x014 | RO | TS_S_HI | [15:0] | Snapshotted seconds[47:32] |
| 0x018 | RO | TS_NS | [29:0] | Snapshotted nanoseconds |
| 0x01C | RO | TS_FNS | [15:0] | Snapshotted fractional nanoseconds |
| 0x020 | RW | SET_S_LO | [31:0] | Set seconds[31:0] |
| 0x024 | RW | SET_S_HI | [15:0] | Set seconds[47:32] |
| 0x028 | RW | SET_NS | [29:0] | Set nanoseconds |
| 0x030 | WO | SET_VALID | [0] | Write 1 to load new time (triggers ts_step) |
| 0x040 | RW | PERIOD_NS | [3:0] | Clock period nanoseconds (4 for 250 MHz) |
| 0x044 | RW | PERIOD_FNS | [15:0] | Clock period fractional nanoseconds |
| 0x048 | WO | PERIOD_VALID | [0] | Write 1 to apply period change |
| 0x050 | RW | ADJ_NS | [3:0] | Adjustment nanoseconds per cycle |
| 0x054 | RW | ADJ_FNS | [15:0] | Adjustment fractional nanoseconds |
| 0x058 | RW | ADJ_COUNT | [15:0] | Number of cycles to apply adjustment |
| 0x05C | WO | ADJ_VALID | [0] | Write 1 to start adjustment |
| 0x060 | RW | DRIFT_NS | [3:0] | Drift correction nanoseconds |
| 0x064 | RW | DRIFT_FNS | [15:0] | Drift correction fractional nanoseconds |
| 0x068 | RW | DRIFT_RATE | [15:0] | Apply drift every N cycles (0 = disabled) |
| 0x06C | WO | DRIFT_VALID | [0] | Write 1 to apply drift config |

### Per-Port TX Timestamp FIFOs

Port 0 base: 0x1000, Port 1 base: 0x2000

| Offset | R/W | Field | Bits | Description |
|--------|-----|-------|------|-------------|
| 0x000 | RO | TX_TS_LO | [31:0] | Returned TX timestamp[31:0] |
| 0x004 | RO | TX_TS_HI | [31:0] | Returned TX timestamp[79:32] |
| 0x008 | RO | TX_TS_TAG | [15:0] | Returned TX tag (matches software-injected tag) |
| 0x00C | RW | TX_TS_VALID | [0] RO | FIFO has valid entry; write 1 to pop |

TX timestamp format within the 80-bit FIFO entry:
- `[79:48]` = seconds[31:0]
- `[47:46]` = 2'b00 (padding)
- `[45:16]` = nanoseconds[29:0]
- `[15:0]` = fractional nanoseconds[15:0]

## Clock Domain Crossing (CDC) Strategy

### Three-Clock Architecture

| Clock | Frequency | Domain |
|-------|-----------|--------|
| `axis_aclk` | 250 MHz | Datapath backbone, master PTP clock |
| `cmac_clk` | 322 MHz | Per-port CMAC interface |
| `axil_aclk` | 125 MHz | AXI-Lite control, used as sample clock for CDC phase detection |

### ptp_clock_cdc: Phase-Locked Time Replication

The most critical CDC path replicates the 250 MHz master time into each 322 MHz CMAC domain:

1. **Phase/Frequency Detector** (sample clock domain at 125 MHz):
   - Monitors edge transitions on both source and destination sides
   - Accumulates phase error, decimated by 2^LOG_RATE (LOG_RATE=3, every 8 samples)
   - Generates `locked` status when error is zero for 128 consecutive samples

2. **PI Controller** (output clock domain at 322 MHz):
   - **Proportional**: `phase_inc += sample_acc * 2^4` (when locked) or `* 2^10` (unlocked, for fast acquisition)
   - **Integral**: `error_int += sample_acc` to track cumulative error
   - Adjusts the rate at which the destination timestamp counter increments

3. **Metastability Protection**:
   - 3-stage synchronizer chains for all cross-domain signals
   - Edge detection on synchronized signals

4. **Step Time Safety**:
   - When software writes `SET_VALID`, `ptp_ts_step` pulses
   - CDC detects step and resets lock detectors, preventing transient errors

### Sideband Async FIFOs

All packet-level timestamp/tag data crosses via Xilinx XPM async FIFOs with Gray-coded pointers:

| Path | Direction | Width | Depth | CDC Stages | Purpose |
|------|-----------|-------|-------|------------|---------|
| RX timestamp | 322->250 MHz | 80 bits | 64 | 2 | Per-packet RX timestamp |
| TX tag | 250->322 MHz | 16 bits | 64 | 2 | Per-packet TX PTP tag |
| TX timestamp return | 322->250 MHz | 96 bits (80 TS + 16 tag) | 16 | 3 | CMAC-returned TX timestamp |

## Software Interface (Driver Side)

The driver (`open-nic-driver/onic_ptp.c`) registers a Linux PTP clock device and implements:

| PTP Clock Op | Register Interaction |
|---|---|
| `adjtime` | Writes ADJ_NS, ADJ_FNS, ADJ_COUNT, then ADJ_VALID |
| `adjfine` | Writes DRIFT_NS, DRIFT_FNS, DRIFT_RATE, then DRIFT_VALID |
| `gettime64` | Reads TS_S_LO (triggers snapshot), then TS_S_HI, TS_NS, TS_FNS |
| `settime64` | Writes SET_S_LO, SET_S_HI, SET_NS, then SET_VALID |
| TX timestamp retrieval | Polls TX_TS_VALID per port, reads TX_TS_LO/HI/TAG, writes 1 to pop |

### Typical Software Usage

```
# Synchronize FPGA PTP clock to a PTP grandmaster
ptp4l -i onic0 -H -2

# Synchronize system clock to FPGA PTP clock
phc2sys -s onic0 -c CLOCK_REALTIME -O 0
```

## Driver Integration Status

The Linux driver (`open-nic-driver/`) has the following PTP components implemented:

| Component | File(s) | Status |
|-----------|---------|--------|
| PTP clock registration | `onic_ptp.c`, `onic_ptp.h` | Complete -- registers `struct ptp_clock_info`, creates `/dev/ptpN` |
| Clock ops: adjfine, adjtime, gettime64, settime64 | `onic_ptp.c` | Complete -- mapped to AXI-Lite PTP registers |
| IOCTL dispatch (SIOCSHWTSTAMP/SIOCGHWTSTAMP) | `onic_netdev.c` | Complete |
| ethtool get_ts_info | `onic_ethtool.c` | Complete -- reports `SOF_TIMESTAMPING_TX_HARDWARE`, `SOF_TIMESTAMPING_RX_HARDWARE` |
| Probe/remove lifecycle | `onic_main.c` | Complete -- `onic_ptp_init()` / `onic_ptp_cleanup()` |
| TX TS FIFO poll scaffolding | `onic_ptp.c` | Scaffolding present, not connected to QDMA TX path |
| RX timestamp extraction from QDMA C2H | -- | **Not started** -- blocked on FPGA-side QDMA descriptor integration |
| TX PTP tag injection into QDMA H2C | -- | **Not started** -- blocked on FPGA-side QDMA descriptor integration |

The driver can register the PTP clock and perform time get/set/adjust operations. Per-packet timestamping (both RX and TX) is blocked on QDMA descriptor modifications on the FPGA side.

---

## Two-Shell Latency Measurement

### Overview

The primary test and measurement scenario uses two OpenNIC Shell instances (two FPGA cards, or two ports on one card) connected back-to-back with a direct QSFP28 cable or DAC. This eliminates switch-induced jitter and allows precise characterization of the PTP implementation.

### Back-to-Back Connection Topology

```
  Shell A (PTP Master)             Shell B (PTP Slave)
  ┌──────────────────┐            ┌──────────────────┐
  │  CMAC 0          │────QSFP────│  CMAC 0          │
  │  PTP clock A     │  direct    │  PTP clock B     │
  │  ptp4l master    │  cable     │  ptp4l slave     │
  └──────────────────┘            └──────────────────┘
        onic0                           onic0
```

Both shells run identical bitstreams with the PTP subsystem. Each has its own independent PTP hardware clock. The slave's clock is disciplined to track the master via PTP message exchange.

### ptp4l Master/Slave Configuration

Master side:
```
ptp4l -i onic0 -H -2 --masterOnly=1 -m
```

Slave side:
```
ptp4l -i onic0 -H -2 --slaveOnly=1 -m
```

Flags:
- `-H` : use hardware timestamping (reads from `/dev/ptpN`)
- `-2` : Layer 2 (IEEE 802.3) transport -- avoids IP routing, ARP, and UDP overhead
- `-m` : print messages to stdout for monitoring
- `--masterOnly=1` / `--slaveOnly=1` : forces role to avoid BMCA negotiation delay

Once converged, `ptp4l` on the slave side reports offset and frequency correction. Typical sub-microsecond convergence is expected with hardware timestamping.

### Measurement Methods

**One-way latency** (requires synchronized clocks):
- After `ptp4l` has converged the slave clock to the master, both PTP clocks agree on the current time within nanoseconds.
- Send a test packet from A to B. Compare the TX hardware timestamp on A to the RX hardware timestamp on B.
- Formula: `Latency_one_way = T_rx_B - T_tx_A`
- Accuracy depends on PTP clock synchronization quality (typically <100 ns offset after convergence).

**Round-trip latency** (single clock, no synchronization needed):
- Send a packet from A to B; B immediately echoes it back to A.
- Both TX and RX timestamps are taken from A's PTP clock.
- Formula: `RTT = T_rx_echo_A - T_tx_original_A`
- One-way estimate: `RTT / 2` (assumes symmetric path).
- Does not require `ptp4l` or clock synchronization.

**Wire-to-wire (forwarding) latency** (single shell):
- A packet arrives at CMAC RX and is forwarded out CMAC TX on the same or different port.
- Both timestamps come from the same PTP clock (or phase-locked CDC copies).
- Formula: `Forwarding_latency = T_tx_timestamp - T_rx_timestamp`
- Measures the FPGA pipeline delay for packet forwarding.

### What Each Method Requires

| Method | RX TS needed | TX TS needed | Clock sync needed | Shells needed |
|--------|-------------|-------------|-------------------|---------------|
| One-way | Yes (on receiver) | Yes (on sender) | Yes (ptp4l converged) | 2 |
| Round-trip | Yes (on sender) | Yes (on sender) | No | 2 (one echoes) |
| Wire-to-wire | Yes | Yes | No | 1 (forwarding) |

---

## Current Limitations

1. **RX timestamps do not reach the driver**: Timestamps travel from the CMAC through `packet_adapter_rx` sideband FIFO and arrive at `box_250mhz` on `m_axis_rx_tuser_ptp_ts`. However, they are **not embedded into QDMA C2H completion descriptors**. Until the QDMA C2H descriptor path is modified to include the 80-bit RX timestamp, the driver cannot extract per-packet RX timestamps. This blocks `ptp4l` slave mode (which requires RX timestamps on incoming Sync messages) and all RX-side latency measurements.

2. **TX PTP tag not injected from driver to FPGA**: The driver has TX TS FIFO polling scaffolding, but there is no path from the QDMA H2C descriptor metadata into the `packet_adapter_tx` sideband FIFO. The driver cannot assign a 16-bit PTP tag to outgoing packets. This blocks TX timestamping and the `SO_TIMESTAMPING` TX path. The CMAC-side TX timestamp return path (CMAC -> async FIFO -> register bank) is fully wired; only the tag injection from the host side is missing.

3. **No synthesis has been run**: The FPGA design has not been through Vivado synthesis. Port width mismatches, unconnected signals, and timing violations may exist. This must be resolved before any hardware testing.

4. **TX timestamp FIFO depth**: Only 16 entries per port. High-rate TX timestamping could overflow if software does not poll fast enough. For `ptp4l` at default 1-second Sync intervals this is not a concern, but custom high-rate applications may need FIFO depth increase or interrupt-driven retrieval.

5. **ptp_perout not instantiated**: The periodic output module (`ptp_perout.v`) is available in the source tree but not instantiated in `ptp_subsystem.sv`. PPS (pulse-per-second) output is not available until it is wired up.
