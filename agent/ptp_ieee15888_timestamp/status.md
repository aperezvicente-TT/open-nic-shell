# PTP IEEE 1588 Timestamping -- Implementation Status

Last updated: 2026-04-13

---

## Summary

TX hardware timestamping is **fully working**. RX hardware timestamping is **blocked by a lane-skew correction pipeline bug in `cmac_subsystem.sv`**. Fix applied 2026-04-13. Needs FPGA bitstream rebuild + test.

ptp4l remains stuck in `s0` (never adjusts) because the slave RX timestamp is always zero, making the computed offset nonsensical (~-888 billion seconds).

---

## Current Blocker: RX timestamp lane-skew pipeline overwrite (2026-04-13)

**Symptom:** ptp4l shows enormous master offset (~-888e15 ns after `phc_ctl set`, ~-1.776e18 ns before). Offset never converges; stays in `s0 freq +0` indefinitely. TX timestamps are correct (confirmed via dmesg `hwtstamp=1776065608...`).

**Diagnostic:** Added `netdev_info` RX timestamp print (modulo 50) to driver. Output:
```
PTP RX TS #1: sec=0 ns=21 raw_hi=0x00000000 raw_lo=0x00000015 pktlen=78
PTP RX TS #51: sec=0 ns=21 raw_hi=0x00000000 raw_lo=0x00000015 pktlen=60
```

The RX completion descriptor always contains `sec=0, ns=21`. The constant 21 ns is the lane-skew correction `(LANE_FILL_REF - sop_lane_fill) × 3 = (10-3)×3 = 21 ns` applied to a zeroed raw timestamp. Confirmed the "halving" pattern: with t2≈0, the PTP offset formula `((t2-t1) - (t4-t3))/2` gives exactly `-master_time/2` when t3=t4 (slave TX matching master after `phc_ctl set`).

Also confirmed via PTP CTRL register (BAR2+0x18000) that all four CDCs are locked: `CTRL=0x01000f01`, bits [11:8]=0xF (TX0, RX0, TX1, RX1 all locked). The PTP clock reads correct wall-clock time (~1776066042 seconds). So the issue is not in the CDC or PTP clock — it's in how the CMAC timestamp reaches the completion descriptor.

**Root cause:** In `cmac_subsystem.sv`, the lane-skew correction has a 2-stage registered pipeline:

- **Stage 1** (cycle 0→1): registers `p1_raw_sec`, `p1_raw_ns`, `p1_correction_ns`
- **Stage 2** (cycle 1→2): combinational add + wraparound → latched into `rx_ptp_ts_held` by `rx_sop_d[1]`

The Xilinx CMAC IP only drives `rx_ptp_tstamp_out` for **one clock cycle** (on the SOP beat, when `rx_ptp_tstamp_valid_out` is asserted). On subsequent cycles, it reverts to zero.

The stage 1 registers were **unconditionally updated every `cmac_clk` cycle** (no enable gate):

```verilog
always @(posedge cmac_clk) begin
    p1_raw_ns  <= rx_ptp_ts_raw[29:0];     // updates EVERY cycle
    p1_raw_sec <= rx_ptp_ts_raw[79:32];     // updates EVERY cycle
    p1_correction_ns <= (...);
end
```

Timeline:
- **Cycle 0 (SOP):** `rx_ptp_ts_raw` = valid timestamp. Stage 1 captures it correctly.
- **Cycle 1:** `rx_ptp_ts_raw` = 0 (CMAC no longer driving). Stage 1 **overwrites** valid value with 0.
- **Cycle 2:** `rx_sop_d[1]` fires, latching `rx_ptp_ts_corrected` into `rx_ptp_ts_held`. But the corrected value is computed from the **zeroed** stage 1 registers → `{sec=0, ns=0+21}`.

**Fix:** Gate stage 1 with SOP detection so registers only capture when the CMAC output is valid:

```verilog
wire rx_ptp_sop = axis_cmac_rx_tvalid && !rx_in_packet;

always @(posedge cmac_clk) begin
    if (rx_ptp_sop) begin
        p1_raw_ns  <= rx_ptp_ts_raw[29:0];
        p1_raw_sec <= rx_ptp_ts_raw[79:32];
        p1_correction_ns <= (...);
    end
end
```

This preserves the valid SOP timestamp in stage 1 until stage 2 reads it on cycle 2.

**Files modified:** `src/cmac_subsystem/cmac_subsystem.sv` (lines 193-206)

**Status:** Code fix applied. Needs FPGA bitstream rebuild and hardware test.

---

## Previous Blockers (ALL RESOLVED)

### 5. 80-bit timestamp format mismatch (FIXED 2026-04-09)

The 96→80 bit conversion in `ptp_subsystem.sv` produced the wrong format. Fix: `{cdc_ts_96[95:48], cdc_ts_96[47:16]}`. Driver simplified: `sec=ts_raw_hi`, `ns=ts_raw_lo & 0x3FFFFFFF`.

### 4. packet_adapter_tx single-beat tag capture race (FIXED 2026-04-05)

For 1-beat PTP packets (60 bytes), the sideband FIFO captures the stale registered tag value (0) instead of the current tag. Fix: mux FIFO `din` for single-beat packets.

### 3. P2P 322 MHz PTP tag pipeline skew (FIXED 2026-04-04)

PTP tag bypassed TX register slices while data went through 2 pipeline stages. Fix: widened TUSER_W from 1 to 17 (TX) and 1 to 81 (RX).

### 2. P2P 250 MHz PTP tag pipeline skew (FIXED 2026-04-01)

Same class of bug in the 250 MHz path. Fix: pack tag into `tuser[47:32]`.

### 1. CMAC IP cached without PTP (FIXED 2026-04-01)

Build cached CMAC IP with `C_HAS_PTP=0`. Fix: rebuild with `-overwrite 1`.

---

## Bugs Found and Fixed (Complete List)

| # | Bug | Date Fixed | File(s) |
|---|-----|-----------|---------|
| 7 | **RX lane-skew pipeline overwrite** — stage 1 registers unconditionally overwritten every cycle; CMAC only holds timestamp for 1 cycle | 2026-04-13 | `cmac_subsystem.sv` |
| 6 | **80-bit timestamp format mismatch** — wrong 96→80 bit conversion | 2026-04-09 | `ptp_subsystem.sv`, driver |
| 5 | **adjtime truncation** — `adj_ns = (u32)delta` truncated 64-bit deltas | 2026-04-07 | `onic_ptp.c` |
| 4 | **TX TS delivery race** — workqueue latency exceeded ptp4l timeout | 2026-04-07 | `onic_ptp.c` |
| 3 | **packet_adapter_tx single-beat tag capture** — FIFO reads stale register for 1-beat packets | 2026-04-05 | `packet_adapter_tx.sv` |
| 2.5 | **adjfine used DRIFT registers** — Verilog signedness bug in ptp_clock.v drift path | 2026-04-05 | `onic_ptp.c` |
| 2 | **P2P 322 MHz tag pipeline skew** — tag bypassed register slices | 2026-04-04 | `p2p_322mhz.sv` |
| 1 | **P2P 250 MHz tag pipeline skew** — tag bypassed TX pipeline | 2026-04-01 | `p2p_250mhz.sv` |
| 0 | **CMAC IP cached without PTP** — stale IP with `C_HAS_PTP=0` | 2026-04-01 | build scripts |

---

## What's Verified Working (2026-04-13)

### TX Path (end-to-end confirmed)

| Component | Status | Evidence |
|-----------|--------|----------|
| PTP master clock (250 MHz) | OK | `CTRL=0x01000f01`, time=1776066042s (correct wall-clock) |
| PTP CDC TX (250→322 MHz) | OK | CTRL[8]=1 (locked) |
| PTP CDC RX (250→rx_serdes) | OK | CTRL[9]=1 (locked) |
| Driver hwtstamp_set ioctl | OK | `tx_type=1 rx_filter=1` |
| Driver TX tag allocation | OK | Tags 2-13+ delivered successfully |
| QDMA H2C metadata delivery | OK | Tag reaches FPGA |
| P2P pipeline tag threading | OK | Widened TUSER carries tag through slices |
| CMAC PTP TX timestamping | OK | TX_GOOD matches, valid=1, timestamps returned |
| TX TS FIFO (322→250 MHz) | OK | Tags match, timestamps delivered to socket |
| Driver TX TS delivery | OK | `PTP TX TS DELIVER: tag=N hwtstamp=1776065608...` |
| `phc_ctl set/get` | OK | Sets and reads correct wall-clock time |

### RX Path (broken at lane-skew correction, fix pending rebuild)

| Component | Status | Evidence |
|-----------|--------|----------|
| CMAC RX timestamping | Unknown | Cannot verify until pipeline fix deployed |
| Lane-skew correction | **BUG** | Stage 1 overwrites valid timestamp with 0 |
| Packet adapter RX sideband FIFO | OK (code) | FIFO plumbing verified correct |
| P2P 322 MHz RX tuser passthrough | OK | TUSER_W=81, timestamp carried through slices |
| P2P 250 MHz RX passthrough | OK | Direct wire passthrough of 80-bit ts |
| QDMA C2H completion descriptor | OK (code) | Correctly packs ts_fifo_dout into DWORDs |
| Driver RX timestamp extraction | OK | `sec=cmpl.ts_raw_hi, ns=cmpl.ts_raw_lo & 0x3FFFFFFF` |

---

## FPGA (open-nic-shell) -- FULLY IMPLEMENTED

All source files present and structurally complete.

### New `src/ptp_subsystem/` directory

| File | Status | Purpose |
|------|--------|---------|
| `ptp_clock.v` | Done | Master 96-bit PTP clock (250 MHz, 4 ns/tick) |
| `ptp_clock_cdc.v` | Done | Phase-locked CDC from 250 MHz to 322 MHz / rx_serdes_clk |
| `ptp_subsystem.sv` | Done | Top-level: master clock, per-port CDC (TX+RX), TX TS FIFOs, register bank |
| `ptp_subsystem_register.sv` | Done | AXI-Lite register file with CDC lock status at CTRL[11:8] |

### CMAC subsystem changes

| Change | Status |
|--------|--------|
| 15 TCL files: `CONFIG.ENABLE_TIME_STAMPING {1}` | Done |
| `cmac_subsystem_cmac_wrapper.sv`: PTP ports, rx_serdes_clk exposed | Done |
| `cmac_subsystem.sv`: RX TS capture + lane-skew correction (2-stage pipeline) | Done (bug #7 fix applied) |

### Datapath changes

| Change | Status |
|--------|---------|
| `packet_adapter_rx.sv`: Sideband xpm_fifo_async (80-bit, 322→250 MHz) | Done |
| `packet_adapter_tx.sv`: Sideband xpm_fifo_async (16-bit, 250→322 MHz) | Done |
| `plugin/p2p/p2p_322mhz.sv`: TUSER_W=17 (TX), TUSER_W=81 (RX) | Done |
| `plugin/p2p/p2p_250mhz.sv`: PTP tag in tuser[47:32] | Done (single-QDMA only) |

---

## Driver (open-nic-driver) -- COMPLETE

| File | Status | What it does |
|------|--------|--------------|
| `onic_ptp.h` | Done | Register offsets, TX TS FIFO macros |
| `onic_ptp.c` | Done | adjfine, adjtime, gettime64, settime64, TX TS poll + delivery |
| `onic_netdev.c` | Done | hwtstamp ioctl, TX tag injection, RX TS from completion descriptor |
| `onic_ethtool.c` | Done | get_ts_info reporting HW+SW capabilities |

---

## Test Setup (2026-04-13)

### Physical Topology

```
  desktop (AU200 FPGA, slave)       desktop-2 (Mellanox, master)
  ┌──────────────────────┐         ┌──────────────────────┐
  │  enp130s0f0          │──QSFP───│  enp97s0f0np0        │
  │  PTP Slave           │ direct  │  PTP Master          │
  │  CMAC port 0         │ cable   │  ConnectX-5          │
  │  /dev/ptp2           │         │  /dev/ptp2           │
  │  00:0a:35:..         │         │  94:6d:ae:..         │
  └──────────────────────┘         └──────────────────────┘
```

### Test Commands

```bash
# Master (desktop-2):
sudo ptp4l -i enp97s0f0np0 -H -2 --masterOnly=1 -m

# Slave (desktop):
sudo phc_ctl /dev/ptp2 set                                    # seed PHC from system clock
sudo ptp4l -i enp130s0f0 -H -2 --slaveOnly=1 -m --step_threshold=1
```

### Build Commands

```bash
# FPGA bitstream (from open-nic-shell/):
./script/build_2cmac.sh
# Delete cached CMAC IP if needed: rm -rf build/au200_2cmac_2pf/vivado_ip/cmac_usplus_{0,1}

# Driver (from open-nic-driver/):
make clean && make
sudo rmmod onic; sudo insmod onic.ko
```

---

## Next Steps (Priority Order)

1. **Rebuild FPGA bitstream** with `cmac_subsystem.sv` lane-skew pipeline fix (bug #7)
2. **End-to-end ptp4l -H verification** — expect RX timestamps to be non-zero; servo should converge
3. **Performance characterization** — measure offset/jitter vs SW timestamping baseline (~10-50 us)
4. **Clean up debug prints** — remove temporary `dev_info` traces, restore 200ms TX TS poll timeout
5. **Timing closure** — check WNS after rebuild (previous: -0.020 to -0.037 ns, marginal)
