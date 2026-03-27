# PTP IEEE 1588 Timestamping & Latency Measurement Integration Plan

## Context

OpenNIC Shell currently has **zero PTP/timestamp infrastructure**. The Corundum FPGA framework has a mature, proven PTP subsystem with nanosecond-precision hardware timestamping. This plan integrates Corundum's PTP modules into OpenNIC Shell to enable:
- IEEE 1588 hardware timestamping on TX and RX packets
- Latency measurement (wire-to-host, host-to-wire, wire-to-wire)
- PTP clock synchronization via Linux `ptp4l`

---

## How Latency Measurement Works

### The Principle
Every packet gets a **hardware timestamp** at two points — the moment it hits the wire (MAC level) and the moment software touches it. The difference = latency.

### Measurement Types

| Metric | Formula | Where Measured |
|--------|---------|----------------|
| **Wire-to-host** (RX latency) | `T_sw_receive - T_rx_mac_timestamp` | RX PTP TS at CMAC, software reads it from descriptor |
| **Host-to-wire** (TX latency) | `T_tx_mac_timestamp - T_sw_submit` | Software records submit time, TX PTP TS returned from CMAC |
| **Wire-to-wire** (forwarding) | `T_tx_timestamp - T_rx_timestamp` | Both captured in hardware on a forwarded packet |
| **One-way network** | `T_rx_remote - T_tx_local` | Requires PTP-synchronized clocks on both endpoints |
| **Round-trip** | `T_rx_reply - T_tx_request` | Single clock, no sync needed |

### How It Works in Hardware (Corundum's Approach)

1. **PTP Hardware Clock (PHC)**: A free-running 96-bit counter increments every clock cycle by a configurable period (ns + fractional ns). This is the single time source.

2. **RX path**: When the CMAC receives a packet, the current PHC time is captured and embedded in the AXI-Stream `tuser` sideband. It travels with the packet all the way to the driver, which extracts it from the completion descriptor and sets `skb_hwtstamps(skb)->hwtstamp`.

3. **TX path**: The driver tags each TX packet with a 16-bit identifier. When the CMAC transmits the packet, it captures the PHC time and returns it paired with the tag via a FIFO. The driver matches the tag to the original SKB and delivers the timestamp back to the socket.

4. **Software (ptp4l)**: The Linux PTP daemon uses `SO_TIMESTAMPING` to get these hardware timestamps, computes clock offset vs. a grandmaster, and adjusts the PHC via `adjfreq`/`adjtime` syscalls (mapped to AXI-Lite register writes).

5. **DMA latency stats** (optional): Corundum's `stats_dma_latency.v` uses tag-matching in hardware — records a cycle counter at DMA start, computes `finish_cycle - start_cycle` to measure PCIe DMA latency in clock cycles.

---

## Architecture Decision: Where Does the PTP Clock Run?

**250MHz (`axis_aclk`)** — the QDMA data path clock.

- Period = exactly 4.000 ns (`PERIOD_NS=4, PERIOD_FNS=0`) — zero fractional error
- Always present, stable, derived from PCIe refclk
- The 322MHz CMAC clock has period ~3.103 ns (messy fractional) and is per-port
- CDC modules (`ptp_clock_cdc`) distribute the time to each 322MHz CMAC domain

## Architecture Decision: CMAC Native PTP vs AXI-Stream Level

**Use Xilinx CMAC's built-in PTP timestamping** (best accuracy).

The CMAC IP has native PTP support via `CONFIG.ENABLE_TIME_STAMPING {1}`, which exposes:
- `ctl_tx_systemtimerin[79:0]` / `ctl_rx_systemtimerin[79:0]` — feed current time
- `rx_ptp_tstamp_out[79:0]` — RX timestamp captured at PCS level
- `tx_ptp_tstamp_out[79:0]` + `tx_ptp_tstamp_tag_out[15:0]` — TX timestamp + tag return
- `tx_ptp_1588op_in[1:0]` + `tx_ptp_tag_field_in[15:0]` — TX operation mode + tag

This gives sub-nanosecond accuracy inside the MAC, vs ~3ns at AXI-Stream level.

---

## Modules to Borrow from Corundum

Copy these into `src/ptp_subsystem/`:

| File | Source Path | Purpose |
|------|-------------|---------|
| `ptp_clock.v` | `corundum/fpga/lib/eth/rtl/ptp_clock.v` | 96-bit freerunning HW clock |
| `ptp_clock_cdc.v` | `corundum/fpga/lib/eth/rtl/ptp_clock_cdc.v` | Clock domain crossing for timestamps |
| `ptp_perout.v` | `corundum/fpga/lib/eth/rtl/ptp_perout.v` | PPS (pulse-per-second) output |
| `ptp_ts_extract.v` | `corundum/fpga/lib/eth/rtl/ptp_ts_extract.v` | Extract timestamp from tuser |
| `stats_dma_latency.v` | `corundum/fpga/common/rtl/stats_dma_latency.v` | Tag-based cycle-count latency |

These are self-contained Verilog modules with no external dependencies.

---

## Implementation Steps

### Step 1: Copy Corundum PTP Modules

Create `src/ptp_subsystem/` and copy the 5 modules listed above.

### Step 2: Enable PTP in CMAC IP Configuration

**Files (15 total):** All `src/cmac_subsystem/vivado_ip/cmac_usplus_*.tcl`

Add `CONFIG.ENABLE_TIME_STAMPING {1}` to each file's `set_property -dict` block. This causes the CMAC IP to generate PTP timestamp ports. Requires IP regeneration.

### Step 3: Create `src/ptp_subsystem/ptp_subsystem.sv`

Central coordination module:

```
ptp_clock (250MHz, axis_aclk)
  |-- PERIOD_NS=4, PERIOD_FNS=0 (exact 4ns at 250MHz)
  |-- 96-bit output: {seconds[47:0], 2'b0, nanoseconds[29:0], fns[15:0]}
  |
  +-- ptp_clock_cdc --> 322MHz cmac_clk[0] --> ptp_time_80[0] for CMAC port 0
  +-- ptp_clock_cdc --> 322MHz cmac_clk[1] --> ptp_time_80[1] for CMAC port 1
  |
  +-- AXI-Lite register bank (125MHz, CDC'd from 250MHz)
  |     Registers: set time, adjust freq, adjust offset, read snapshot
  |
  +-- TX TS FIFO per port (322MHz write from CMAC, 125MHz read via AXI-Lite)
  +-- stats_dma_latency per port (optional, 250MHz domain)
```

96-bit to 80-bit conversion for CMAC: `{ts_96[79:48], ts_96[45:16], ts_96[15:0]}` (seconds[31:0] + nanoseconds[29:0] padded to 32 + fns[15:0]).

### Step 4: Create `src/ptp_subsystem/ptp_subsystem_register.sv`

AXI-Lite register bank following the pattern of `src/packet_adapter/packet_adapter_register.sv`.

**Address map** (placed at `0x18000` in BAR2, in the gap between sysmon and box0):

```
0x18000 - PTP Global Registers:
  0x000: CTRL        [0]=enable [1]=adj_active(RO) [31:16]=version
  0x010: TS_S_LO     seconds[31:0]  (atomic snapshot on read)
  0x014: TS_S_HI     seconds[47:32]
  0x018: TS_NS       nanoseconds[29:0]
  0x01C: TS_FNS      fractional_ns[15:0]
  0x020: SET_S_LO    set seconds[31:0]
  0x024: SET_S_HI    set seconds[47:32]
  0x028: SET_NS      set nanoseconds
  0x030: SET_VALID   write 1 to apply
  0x040: PERIOD_NS   clock period ns[3:0]
  0x044: PERIOD_FNS  clock period fns[15:0]
  0x048: PERIOD_VALID
  0x050: ADJ_NS      offset adjustment
  0x054: ADJ_FNS
  0x058: ADJ_COUNT
  0x05C: ADJ_VALID
  0x060: DRIFT_NS    frequency drift correction
  0x064: DRIFT_FNS
  0x068: DRIFT_RATE
  0x06C: DRIFT_VALID

0x19000 - Per-Port 0 Registers:
  0x000: TX_TS_LO    returned TX timestamp[31:0]
  0x004: TX_TS_HI    returned TX timestamp[79:32]
  0x008: TX_TS_TAG   returned TX tag[15:0]
  0x00C: TX_TS_VALID [0]=valid, write 1 to pop FIFO
  0x020: LATENCY_RX  last RX-to-DMA latency (cycles)
  0x024: LATENCY_TX  last DMA-to-TX latency (cycles)

0x1A000 - Per-Port 1 Registers (same layout)
```

### Step 5: Modify CMAC Wrapper — Connect PTP Ports

**File:** `src/cmac_subsystem/cmac_subsystem_cmac_wrapper.sv`

Add to module ports:
```systemverilog
input  [79:0] ptp_time,         // from PTP subsystem CDC output
output [79:0] tx_ptp_ts,        // TX timestamp return from CMAC
output [15:0] tx_ptp_ts_tag,    // TX tag return
output        tx_ptp_ts_valid,  // TX TS valid pulse
output [79:0] rx_ptp_ts,        // RX timestamp from CMAC
input  [15:0] tx_ptp_tag_in,    // TX tag from packet metadata
input   [1:0] tx_ptp_1588op_in  // TX PTP operation (2'b10 = 2-step)
```

Connect to the `cmac_usplus_0` / `cmac_usplus_1` instances:
```verilog
.ctl_tx_systemtimerin       (ptp_time),
.ctl_rx_systemtimerin       (ptp_time),
.tx_ptp_1588op_in           (tx_ptp_1588op_in),
.tx_ptp_tag_field_in        (tx_ptp_tag_in),
.tx_ptp_tstamp_out          (tx_ptp_ts),
.tx_ptp_tstamp_tag_out      (tx_ptp_ts_tag),
.tx_ptp_tstamp_valid_out    (tx_ptp_ts_valid),
.rx_ptp_tstamp_out          (rx_ptp_ts),
```

### Step 6: Modify CMAC Subsystem — Propagate PTP & Widen tuser

**File:** `src/cmac_subsystem/cmac_subsystem.sv`

- Add PTP ports to module interface
- Embed RX PTP timestamp into tuser: widen `m_axis_cmac_rx_tuser` from 1-bit (err) to 81-bit (err + 80-bit TS)
- Carry TX PTP tag in `s_axis_cmac_tx_tuser`: widen from 1-bit to 17-bit (err + 16-bit tag)
- Update `TUSER_W` on internal register slices and `axi_stream_rx_drain`

### Step 7: Widen tuser Through box_322mhz

**File:** `src/box_322mhz/box_322mhz.sv`

Update all CMAC-facing and adapter-facing AXI-Stream ports to use widened tuser (81-bit RX, 17-bit TX). The default p2p plugin must pass the wider tuser through.

### Step 8: Widen tuser Through packet_adapter

**Files:** `src/packet_adapter/packet_adapter.sv`, `packet_adapter_rx.sv`, `packet_adapter_tx.sv`

**RX direction** (322MHz -> 250MHz): The `axi_stream_packet_buffer` Xilinx FIFO IP needs `TUSER_WIDTH` increased to carry the 80-bit timestamp. On the 250MHz output, reconstruct as `{ptp_ts[79:0], size[15:0], src[15:0], dst[15:0]}`.

**TX direction** (250MHz -> 322MHz): Carry the 16-bit PTP tag through the CDC FIFO.

**Alternative (less invasive):** Use a sideband 1-entry-per-packet FIFO for timestamps, synchronized with packet delivery. Avoids touching the main data FIFO width.

### Step 9: Widen tuser Through box_250mhz

**File:** `src/box_250mhz/box_250mhz.sv`

Update adapter-facing and QDMA-facing tuser to include PTP timestamp field.

### Step 10: Add PTP to Address Map

**Files:**
- `src/system_config/system_config_address_map.sv` — add PTP slave port to AXI crossbar
- `src/system_config/system_config.sv` — add PTP AXI-Lite output ports

### Step 11: Integrate in Top-Level

**File:** `src/open_nic_shell.sv`

- Instantiate `ptp_subsystem`
- Wire PTP time outputs to each `cmac_subsystem`
- Wire TX timestamp returns from CMAC back to PTP subsystem
- Wire AXI-Lite from address map to PTP subsystem
- Add PTP reset pair to shell reset infrastructure

### Step 12: Build System

**File:** `script/build.tcl`

The build system auto-discovers `src/*/` directories, so `src/ptp_subsystem/` will be found automatically. May need `src/ptp_subsystem/vivado_ip/vivado_ip.tcl` if additional Xilinx IPs are needed (e.g., async FIFO for TX TS FIFO).

### Step 13: Driver Integration (Conceptual — separate repo)

The Linux driver needs:
1. **PTP HW clock driver**: Register `struct ptp_clock_info` with `adjfreq`, `adjtime`, `gettime64`, `settime64` callbacks mapped to AXI-Lite PTP registers
2. **RX timestamping**: Extract 80-bit PTP TS from widened QDMA C2H completion metadata, set `skb_hwtstamps(skb)->hwtstamp`
3. **TX timestamping**: On `SKBTX_HW_TSTAMP`, set PTP tag in H2C descriptor; poll TX TS FIFO via AXI-Lite for matching tag
4. **Latency reporting**: Read `stats_dma_latency` counters via ethtool/sysfs

---

## Critical Files Summary

| File | Action |
|------|--------|
| `src/ptp_subsystem/` (new dir) | Create: ptp_subsystem.sv, ptp_subsystem_register.sv, + copied Corundum modules |
| `src/cmac_subsystem/vivado_ip/cmac_usplus_*.tcl` (15 files) | Add `CONFIG.ENABLE_TIME_STAMPING {1}` |
| `src/cmac_subsystem/cmac_subsystem_cmac_wrapper.sv` | Add PTP port connections to CMAC IP |
| `src/cmac_subsystem/cmac_subsystem.sv` | Propagate PTP signals, widen tuser |
| `src/box_322mhz/box_322mhz.sv` | Widen tuser |
| `src/packet_adapter/packet_adapter*.sv` | Widen tuser through CDC |
| `src/box_250mhz/box_250mhz.sv` | Widen tuser |
| `src/system_config/system_config_address_map.sv` | Add PTP address range |
| `src/system_config/system_config.sv` | Add PTP AXI-Lite ports |
| `src/open_nic_shell.sv` | Instantiate ptp_subsystem, wire everything |

## Dependency Order

```
Step 1 (copy modules) + Step 2 (CMAC TCL) -- can be parallel
  |
Step 3-4 (ptp_subsystem + registers)
  |
Step 5 (cmac_wrapper) -- depends on Step 2 for new CMAC ports
  |
Step 6 (cmac_subsystem) -> Step 7 (box_322) -> Step 8 (packet_adapter) -> Step 9 (box_250)
  |
Step 10 (address map) -- independent of Steps 5-9
  |
Step 11 (top-level) -- depends on all above
  |
Step 12 (build) + Step 13 (driver) -- last
```

## Verification

1. **Synthesis**: Run Vivado synthesis for AU200 target to check for port mismatches and timing
2. **Simulation**: Write a testbench that feeds the PTP clock, sends a packet through CMAC loopback, and verifies RX timestamp matches TX timestamp within MAC pipeline delay
3. **Hardware test**: Read PTP clock via AXI-Lite, verify it increments at 4ns/tick. Check `ptp4l` can synchronize. Send timestamped packets and verify `SO_TIMESTAMPING` returns valid hardware timestamps
4. **Latency**: Measure wire-to-host latency by comparing RX HW timestamp to `ktime_get_real()` at NAPI poll time
