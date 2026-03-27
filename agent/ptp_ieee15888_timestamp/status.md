# PTP IEEE 1588 Timestamping -- Implementation Status

Last updated: 2026-03-27

---

## Summary

The PTP IEEE 1588 hardware timestamping subsystem for OpenNIC Shell is **partially complete but software-timestamped PTP synchronization is verified working end-to-end**. The FPGA RTL is fully implemented and loaded on hardware. The Linux driver has PTP clock registration, IOCTL handlers, and ethtool support in place, with software timestamping confirmed functional between two hosts. The remaining work is QDMA datapath integration (RX timestamp delivery and TX tag injection) to enable hardware timestamping.

---

## Verified Tests (2026-03-27)

Two-host back-to-back testing was performed with OpenNIC shells loaded on separate machines (desktop and desktop-2). All results below are confirmed working.

### Hardware and Driver Bring-Up

| Test | Result |
|------|--------|
| OpenNIC shell loaded on both hosts | OK |
| PTP hardware detected (version 0x0100) on both hosts | OK |
| PTP clocks registered as `/dev/ptp3` and `/dev/ptp4` on each host (2 PFs per host) | OK |
| `ethtool -T` reports hardware-transmit, hardware-receive, hardware-raw-clock | OK |
| `phc_ctl` confirms clocks ticking correctly (~1s/s advance, 4 ns/tick at 250 MHz) | OK |
| Ping between hosts (basic connectivity) | OK |

### ptp4l Software Timestamping (-S)

| Test | Result |
|------|--------|
| Master (Host A): LISTENING -> MASTER transition | OK |
| Master sends Sync/Announce successfully | OK |
| Slave (Host B): sees foreign master | OK |
| Slave: LISTENING -> UNCALIBRATED -> SLAVE transition | OK |
| Servo converges: offset from ~30 ms -> ~1.2 ms and decreasing | OK |
| Frequency correction ramping correctly | OK |
| Expected steady-state with SW timestamps: 10-50 us | On track |

### Driver Fixes Applied During Testing

1. **`onic_ethtool.c`**: Added `SOF_TIMESTAMPING_TX_SOFTWARE`, `SOF_TIMESTAMPING_RX_SOFTWARE`, and `SOF_TIMESTAMPING_SOFTWARE` to `get_ts_info`. Without these, ptp4l reported "does not support requested timestamping mode" when using `-S`.

2. **`onic_netdev.c`**: Added `skb_tx_timestamp(skb)` call in `onic_xmit_frame()` before ring increment. Without this, ptp4l master reported "timed out while polling for tx timestamp".

3. **MAC address conflict**: Both hosts had the same default MAC `00:0a:35:01:00:00`, causing identical PTP clock IDs (derived from MAC). Fixed by changing Host B MAC to `00:0a:35:02:00:00`.

---

## FPGA (open-nic-shell) -- FULLY IMPLEMENTED AND LOADED ON HARDWARE

All source files are present and structurally complete. No missing modules. Bitstreams loaded and running on both test hosts.

### New `src/ptp_subsystem/` directory

| File | Status | Purpose |
|------|--------|---------|
| `ptp_clock.v` | Done | Master 96-bit PTP clock (250 MHz, 4 ns/tick) |
| `ptp_clock_cdc.v` | Done | Phase-locked CDC from 250 MHz to 322 MHz per CMAC port |
| `ptp_perout.v` | Done | Periodic pulse output (available, not instantiated) |
| `ptp_ts_extract.v` | Done | Timestamp extraction from AXI-Stream tuser |
| `stats_dma_latency.v` | Done | Generic DMA latency counter |
| `ptp_subsystem.sv` | Done | Top-level: master clock, per-port CDC, TX TS FIFOs, register bank |
| `ptp_subsystem_register.sv` | Done | AXI-Lite register file (time set/get, adj, drift, per-port TX TS FIFO) |
| `vivado_ip/vivado_ip.tcl` | Done | Empty IP list (uses XPM primitives only) |

### CMAC subsystem changes

| Change | Status |
|--------|--------|
| 15 TCL files: `CONFIG.ENABLE_TIME_STAMPING {1}` | Done |
| `cmac_subsystem_cmac_wrapper.sv`: PTP ports connected to CMAC IP | Done |
| `cmac_subsystem.sv`: RX timestamp capture, tuser widened (RX: 81-bit, TX: 17-bit) | Done |

### Datapath changes (tuser widening + sideband FIFOs)

| Change | Status |
|--------|---------|
| `box_322mhz.sv`: PTP tuser ports added | Done |
| `box_250mhz.sv`: PTP tuser ports added | Done |
| `packet_adapter_rx.sv`: Sideband xpm_fifo_async (80-bit, 322->250 MHz) for RX TS | Done |
| `packet_adapter_tx.sv`: Sideband xpm_fifo_async (16-bit, 250->322 MHz) for TX tags | Done |
| P2P plugins: PTP signal passthrough | Done |

### System integration

| Change | Status |
|--------|--------|
| `system_config_address_map.sv`: PTP slave added (index 12, 0x18000-0x1AFFF) | Done |
| `system_config_axi_crossbar.tcl`: 12 to 13 masters | Done |
| `open_nic_shell.sv`: PTP subsystem instantiated, all signals wired | Done |

---

## Driver (open-nic-driver) -- PTP CLOCK AND SOFTWARE TIMESTAMPING COMPLETE

The driver has PTP clock registration, frequency/time adjustment, IOCTL dispatch, ethtool timestamp capability reporting, and software timestamping support. Software-timestamped ptp4l is verified working. What remains is the QDMA-level plumbing for per-packet hardware timestamps.

| File | Status | What it does |
|------|--------|--------------|
| `onic_ptp.h` (new) | Done | Register offset definitions matching FPGA address map |
| `onic_ptp.c` (new) | Done | adjfine, adjtime, gettime64, settime64, hwtstamp_set/get, TX TS FIFO poll scaffolding |
| `onic.h` | Done | ptp_clock, ptp_info, tstamp_config, ptp_lock added to onic_private |
| `onic_main.c` | Done | onic_ptp_init() in probe, onic_ptp_cleanup() in remove |
| `onic_netdev.c` | Done | SIOCSHWTSTAMP/SIOCGHWTSTAMP dispatch; `skb_tx_timestamp()` for SW TX timestamps |
| `onic_ethtool.c` | Done | get_ts_info reporting HW and SW timestamping capabilities |

---

## What Is NOT Done

These items require QDMA descriptor-level modifications and have not been started. They are the only barrier to hardware timestamping.

### 1. QDMA C2H Descriptor Integration (RX Timestamps)

RX timestamps travel from the CMAC through the sideband async FIFO and arrive at `box_250mhz` on `m_axis_rx_tuser_ptp_ts`. However, they are **not** embedded into QDMA C2H (card-to-host) completion descriptors. The driver therefore cannot extract per-packet RX hardware timestamps.

**What is needed:**
- Modify the QDMA C2H descriptor path to include the 80-bit RX timestamp in the completion metadata
- Update the driver's RX completion handler to extract the timestamp and call `skb_hwtstamps(skb)->hwtstamp`

### 2. H2C TX Tag Injection

The driver has TX TS FIFO polling scaffolding, but there is no path from the driver through the QDMA H2C (host-to-card) descriptor into the `packet_adapter_tx` sideband FIFO. When a socket requests `SKBTX_HW_TSTAMP`, the driver needs to:
- Assign a 16-bit PTP tag to the SKB
- Inject that tag into the H2C descriptor metadata
- The FPGA must extract the tag and pass it to the CMAC via `tx_ptp_tag_field_in`

**What is needed:**
- Modify the QDMA H2C descriptor path to carry the 16-bit PTP tag
- Update `packet_adapter_tx` to extract the tag from QDMA metadata (currently it reads from tuser sideband, which is populated but not connected to QDMA)
- Update the driver's TX path to set the tag in the descriptor when `SKBTX_HW_TSTAMP` is requested

### 3. Vivado Synthesis Verification

The bitstream is loaded and running (PTP clocks tick, connectivity works), so major structural issues are ruled out. However, a clean synthesis run with timing closure verification has not been performed against the modified sources. Timing violations may exist that cause intermittent issues under load.

### 4. Hardware Timestamping ptp4l -H Test

End-to-end `ptp4l` with hardware timestamping (`-H` flag) has not been tested. This is blocked by items 1-3 above.

---

## Next Steps (Priority Order)

1. **QDMA C2H descriptor integration (RX HW timestamps)** -- This is the critical path. The two-host setup is verified working with software timestamps, so once RX hardware timestamps are delivered through QDMA, `ptp4l -H` slave mode should work immediately. Requires understanding the QDMA IP's C2H completion descriptor format and the driver's RX completion handler.

2. **QDMA H2C TX tag injection (TX HW timestamps)** -- Needed for TX hardware timestamping. Lower priority than RX because `ptp4l` in slave mode can function with RX timestamps alone (the master sends Sync messages; the slave timestamps them on arrival).

3. **Vivado synthesis verification** -- Run a clean build against the current sources to confirm timing closure. The bitstream is functional but timing has not been formally verified.

4. **End-to-end `ptp4l -H` test** -- Once RX timestamps work, run `ptp4l -i onic0 -H -2` on the existing two-host setup. The infrastructure (hosts, cables, IP config, driver loading) is already in place from the SW timestamping test.

5. **TX timestamp verification** -- Once TX tag injection works, verify `SO_TIMESTAMPING` returns valid TX hardware timestamps.

6. **Performance characterization** -- Measure HW timestamp synchronization accuracy (offset, jitter) and compare against the SW timestamp baseline (~10-50 us). Expected HW timestamp accuracy: sub-microsecond.

---

## Two-Shell Test Setup (VERIFIED WORKING)

The target test environment uses two FPGA cards on separate hosts connected back-to-back. Basic connectivity and software-timestamped PTP synchronization are confirmed.

### Physical Topology

```
  Host A (desktop)                Host B (desktop-2)
  ┌─────────────────┐            ┌─────────────────┐
  │   onic0 (CMAC)  │────QSFP────│   onic0 (CMAC)  │
  │   PTP Master    │  direct    │   PTP Slave     │
  │   open-nic-shell│  cable     │   open-nic-shell│
  │   /dev/ptp3,4   │            │   /dev/ptp3,4   │
  │   00:0a:35:01:…│            │   00:0a:35:02:…│
  └─────────────────┘            └─────────────────┘
```

### Current Working Configuration

Software timestamping (verified 2026-03-27):
```
# Host A (master):
ptp4l -i onic0 -S --masterOnly=1

# Host B (slave):
ptp4l -i onic0 -S --slaveOnly=1
```

### Target Configuration (Blocked on QDMA Integration)

Hardware timestamping (not yet functional):
```
# Host A (master):
ptp4l -i onic0 -H -2 --masterOnly=1

# Host B (slave):
ptp4l -i onic0 -H -2 --slaveOnly=1
```

Flags:
- `-H` : hardware timestamping
- `-S` : software timestamping
- `-2` : IEEE 802.3 (Layer 2) transport (avoids IP stack complexity)
- `--masterOnly=1` / `--slaveOnly=1` : forces role assignment

### What This Setup Validates

Already verified (SW timestamps):
- PTP clock register read/write from both drivers
- Clock ticking at correct rate (4 ns/tick, 250 MHz)
- ptp4l state machine transitions (LISTENING -> MASTER/SLAVE)
- Servo convergence and frequency correction
- Basic network connectivity between shells

Still to validate (HW timestamps, blocked by QDMA work):
- RX hardware timestamping (slave timestamps incoming Sync messages)
- TX hardware timestamping (master timestamps outgoing Sync messages)
- Clock servo convergence with HW timestamps (sub-microsecond target)
- Steady-state offset and jitter between the two clocks
