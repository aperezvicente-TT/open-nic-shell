# PTP IEEE 1588 Timestamping -- Implementation Status

Last updated: 2026-04-16 (evening)

---

## Summary

**End-to-end plumbing is live** on bitstream 0x0201: ptp4l with FPGA as slave and Mellanox ConnectX-5 as master reaches the `SLAVE` state, servo stays in `s2`, no more `FAULTY` transitions. TX and RX hardware timestamps both flow into ptp4l.

**Current gating issue: timestamp jitter.** Raw path-delay samples on a direct QSFP DAC cable vary from 2.7 µs to 258 µs (wire latency should be ~25 ns). As a result ptp4l oscillates at ±40–60 µs offset with ±50k ppb frequency swings rather than locking.

Root cause not yet isolated. Suspects (in order): (1) RX timestamp capture point on the wrong pipeline stage, (2) TX/RX reference-plane asymmetry at the CMAC, (3) tag-to-TS pairing races in the TX return FIFO. Next step is an ILA capture of raw `s_axis_rx_tuser_ptp_ts` at the CMAC boundary for 10 consecutive Sync frames — that separates CMAC-sourced jitter from in-logic jitter.

---

## 2026-04-16 Test Results (bitstream 0x0201)

### What works
- `ptp4l -H -2 --slaveOnly=1` reaches `UNCALIBRATED → SLAVE` cleanly on second attempt (after initial large step).
- TX DIAG: `delta_ms=0` for every TX tag (CMAC-returned TX timestamp matches current PTP clock within ~7 µs poll latency).
- RX DIAG: timestamps arrive with plausible sec/ns, `delta_ms=0` vs current PTP clock.
- CDC locked on all four domains (`cdc_locked=0xf` before and after `settime64`).
- No more stale-SOP duplicates: consecutive RX packets carry distinct timestamps (though `gap_ms` still varies per-message-type).

### What does not converge
Raw path-delay samples from ptp4l `-l 7`:
```
258595, 8476, 13382, 58633, 10323, 39714, 2726, 28298,
6179,   75622, 56312, 26084, 38047, 5258   (ns)
```
Expected: ~25 ns with <10 ns jitter on a 5 m DAC. Observed jitter is ~10,000× over budget.

Master offset oscillates `+50 µs / -50 µs` every second; frequency correction swings ±50,000 ppb per sample — textbook servo oscillation driven by noisy timestamps, not a tuning issue.

### Interpretation
Bug #9 and Bug #10 were real and are fixed (plumbing is now end-to-end), but they are not the only source of RX timestamp error. There is at least one more defect upstream — either in the CMAC PTP config, the capture point in `packet_adapter_rx.sv` / `cmac_subsystem.sv`, or the TX-vs-RX MAC reference-plane offset. The servo cannot distinguish "offset" from "asymmetric delay", so asymmetry manifests as unbounded offset.

---

## Current Blocker: Timestamp jitter investigation

Planned diagnostics:
1. **ILA on raw CMAC RX timestamp.** Trigger on PTP Ethertype (0x88F7) at `axis_cmac_rx_tvalid && sop`, capture `rx_ptp_tstamp_out[79:0]` on the SOP beat for 10 consecutive Syncs. If those raw values show µs-scale jitter, the CMAC config is wrong (wrong tuser slice, wrong PTP mode). If they are clean, the jitter is being introduced downstream in our logic.
2. **ILA on raw CMAC TX timestamp.** Same trigger on TX side; compare `tx_ptp_tstamp_out` latency relative to `tx_ptp_1588op_in` handshake.
3. **ptp4l `-l 7` trace of t1/t2/t3/t4.** If forward leg `t2 - t1` is stable but reverse `t4 - t3` is noisy, RX timestamping is the suspect; if both are noisy, TX contributes as well.
4. **Check CMAC PTP latency adjust registers.** Xilinx CMAC exposes TX/RX PTP latency adjust — a configured asymmetry here would produce a constant bias (not per-sample jitter), but worth ruling out.

---

## Historical Blockers (all RESOLVED in 0x0201)

### Bug #9: Wrong clock domain for ctl_rx_systemtimerin (FIXED in 0x0200, verified 0x0201)

**Root cause:** The Xilinx CMAC IP uses `rx_clk = txusrclk2` (TX clock) for ALL user-facing signals including `ctl_rx_systemtimerin`. We drove it from `gt_rxusrclk2` (recovered RX clock) via async FIFO — a CDC violation.

**Evidence:** TX DIAG showed `delta_ms=0` (perfect). RX DIAG showed `delta_ms=354-950` (hundreds of ms behind). Async FIFO input was correct but output was in wrong domain.

**Fix (applied):** `cmac_subsystem_cmac_wrapper.sv` — changed both CMAC instances:
```verilog
.ctl_rx_systemtimerin (ptp_time),  // same as ctl_tx_systemtimerin
```

### Bug #10: Stale tuser on SOP beat (FIXED in 0x0201, verified — no `gap_ms=0` duplicates in 0x0201 run)

**Root cause:** `rx_ptp_ts_held` updates via a 2-stage lane-skew correction pipeline, 2 cycles after the CMAC SOP. But `axis_cmac_rx_tuser_wide = {rx_ptp_ts_held, err}` is captured by downstream register slices on the SOP cycle itself — before the held register updates. The SOP beat's tuser carries the **previous packet's** timestamp.

**Evidence (confirmed 2026-04-16):** Added `gap_ms` diagnostic comparing consecutive RX timestamps:

| DIAG | delta_ms | gap_ms | Meaning |
|------|----------|--------|---------|
| #11 | 1000 | **0** | Same timestamp as previous packet (stale) |
| #21 | 0 | 999 | Correct unique timestamp |
| #41 | 0 | 1004 | Correct |
| #61 | 1005 | **0** | Stale duplicate |
| #91 | 1005 | **0** | Stale duplicate |
| #101 | 1005 | **0** | Stale duplicate |

`gap_ms=0` proves packets are getting duplicate timestamps. Every `gap_ms=0` correlates with `delta_ms≈1000` (the inter-Sync interval).

**Fix (applied):** `cmac_subsystem.sv` — mux raw CMAC timestamp for SOP beat:
```verilog
wire [79:0] rx_ptp_ts_for_tuser = (axis_cmac_rx_tvalid && !rx_in_packet) ?
                                   rx_ptp_ts_raw : rx_ptp_ts_held;
assign axis_cmac_rx_tuser_wide = {rx_ptp_ts_for_tuser, axis_cmac_rx_tuser_err};
```

This skips the ±60ns lane-skew correction on the SOP beat (negligible for PTP) but guarantees the correct timestamp.

---

## Pre-0x0201 Blockers (ALL RESOLVED)

### 7. RX lane-skew pipeline overwrite (FIXED 2026-04-13)

CMAC drives `rx_ptp_tstamp_out` for 1 cycle (SOP). Stage 1 registers were unconditionally overwritten every cycle. Fix: gate stage 1 with SOP detection (`rx_ptp_sop`).

### 6. 80-bit timestamp format mismatch (FIXED 2026-04-09)

96→80 bit conversion produced wrong format. Fix: `{cdc_ts_96[95:48], cdc_ts_96[47:16]}`.

### 5. adjtime truncation (FIXED 2026-04-07)

`adj_ns = (u32)delta` truncated 64-bit deltas. Fix: read-modify-write via gettime/settime.

### 4. TX TS delivery race (FIXED 2026-04-07)

Workqueue latency exceeded ptp4l timeout. Fix: polling with delayed_work at 1 ms.

### 3. packet_adapter_tx single-beat tag capture (FIXED 2026-04-05)

1-beat PTP packets captured stale registered tag value (0). Fix: mux FIFO din for single-beat.

### 2.5. adjfine used DRIFT registers (FIXED 2026-04-05)

Verilog signedness bug in ptp_clock.v drift path. Fix: use PERIOD registers directly.

### 2. P2P 322 MHz PTP tag pipeline skew (FIXED 2026-04-04)

PTP tag bypassed TX register slices. Fix: widened TUSER_W from 1 to 17 (TX), 1 to 81 (RX).

### 1. P2P 250 MHz PTP tag pipeline skew (FIXED 2026-04-01)

Same class of bug in 250 MHz path. Fix: pack tag into tuser[47:32].

### 0. CMAC IP cached without PTP (FIXED 2026-04-01)

Build cached CMAC IP with `C_HAS_PTP=0`. Fix: rebuild with `-overwrite 1`.

---

## Bugs Found and Fixed (Complete List)

| # | Bug | Date Fixed | File(s) | Version |
|---|-----|-----------|---------|---------|
| 10 | **Stale tuser on SOP beat** — rx_ptp_ts_held 2 cycles late, SOP tuser has previous packet's timestamp | 2026-04-16 (pending rebuild) | `cmac_subsystem.sv` | 0x0201 |
| 9 | **Wrong clock domain for ctl_rx_systemtimerin** — driven from gt_rxusrclk2, CMAC reads in txusrclk2 | 2026-04-16 (in 0x0200 build) | `cmac_subsystem_cmac_wrapper.sv` | 0x0200 |
| 8 | **RX CDC approaches targeted wrong domain** — all 3 CDC approaches (independent CDC, register sync, async FIFO) crossed to gt_rxusrclk2 instead of txusrclk2 | 2026-04-15 (superseded by #9) | `ptp_subsystem.sv` | — |
| 7 | **RX lane-skew pipeline overwrite** — stage 1 registers unconditionally overwritten every cycle | 2026-04-13 | `cmac_subsystem.sv` | — |
| 6 | **80-bit timestamp format mismatch** — wrong 96→80 bit conversion | 2026-04-09 | `ptp_subsystem.sv`, driver | — |
| 5 | **adjtime truncation** — `adj_ns = (u32)delta` truncated 64-bit deltas | 2026-04-07 | `onic_ptp.c` | — |
| 4 | **TX TS delivery race** — workqueue latency exceeded ptp4l timeout | 2026-04-07 | `onic_ptp.c` | — |
| 3 | **packet_adapter_tx single-beat tag capture** — FIFO reads stale register for 1-beat packets | 2026-04-05 | `packet_adapter_tx.sv` | — |
| 2.5 | **adjfine used DRIFT registers** — Verilog signedness bug in ptp_clock.v drift path | 2026-04-05 | `onic_ptp.c` | — |
| 2 | **P2P 322 MHz tag pipeline skew** — tag bypassed register slices | 2026-04-04 | `p2p_322mhz.sv` | — |
| 1 | **P2P 250 MHz tag pipeline skew** — tag bypassed TX pipeline | 2026-04-01 | `p2p_250mhz.sv` | — |
| 0 | **CMAC IP cached without PTP** — stale IP with `C_HAS_PTP=0` | 2026-04-01 | build scripts | — |

---

## What's Verified Working (2026-04-16)

### TX Path (fully verified — delta_ms=0 for all tags)

| Component | Status | Evidence |
|-----------|--------|----------|
| PTP master clock (250 MHz, 4ns/tick) | OK | Correct wall-clock time, rate = 1.000 s/s |
| PTP CDC TX (250→322 MHz) | OK | TX DIAG delta_ms=0 for tags 2-43 |
| adjfine (PERIOD registers) | OK | Rate changes correctly |
| adjtime (gettime+add+settime) | OK | Applied correctly |
| QDMA H2C metadata tag delivery | OK | Tag reaches FPGA |
| P2P pipeline tuser threading | OK | TUSER_W=17 (TX), 81 (RX) |
| CMAC PTP TX timestamping | OK | TX_GOOD matches, valid timestamps returned |
| TX TS FIFO (322→250 MHz) | OK | Tags match, timestamps delivered |
| Driver TX TS poll (on-demand) | OK | Workqueue kicks from alloc_tx_tag |

### RX Path

| Component | Status | Evidence |
|-----------|--------|----------|
| CMAC RX timestamping | OK | Valid sec/ns values in rx_ptp_tstamp_out |
| ctl_rx_systemtimerin clock domain | **FIXED (0x0200)** | Now uses ptp_time in txusrclk2 domain |
| SOP beat tuser timestamp | **FIXED (0x0201, pending rebuild)** | Mux raw ts on SOP to avoid 2-cycle stale |
| Lane-skew correction pipeline | OK | Correctly computes ±60ns correction (bypassed on SOP for tuser) |
| Packet adapter RX sideband FIFO | OK | 80-bit async FIFO 322→250 MHz |
| P2P 322 MHz RX tuser passthrough | OK | TUSER_W=81 |
| QDMA C2H completion descriptor | OK | 16B completion with timestamp |
| Driver RX timestamp extraction | OK | Correct sec/ns from completion |

### Driver Status

| Change | Status |
|--------|--------|
| PTP hot-path logging → dev_dbg | Done |
| Diagnostic udelays removed (110μs → 5μs) | Done (remove 5μs after verification) |
| PTP workqueue on-demand | Done |
| TX TS poll timeout 10s → 100ms | Done |
| RX DIAG (delta_ms + gap_ms) | Temporary — remove after verification |
| TX DIAG (delta_ms) | Temporary — remove after verification |

### Ping Latency

| Before cleanup | After cleanup |
|---------------|--------------|
| avg 8ms, max 26ms | avg 0.9ms, min 112μs |

Cause: dev_info printk on serial console + unconditional 1ms workqueue polling.

### Timing Closure (0x0200 build, 2026-04-15)

| Clock domain | WNS (ns) | Failing | Notes |
|-------------|----------|---------|-------|
| txoutclk_out[0] (CMAC) | **Passing** | 0 | Fixed by SLR2 pblock widening |
| axis_aclk_0 (QDMA 250MHz) | -0.134 | 60 | QDMA internal, functional |
| txoutclk_out[0]_2 (PCIe) | -0.032 | 2 | QDMA internal |
| rxoutclk_out[0] (RX SerDes) | +0.771 | 0 | Clean |

---

## FPGA Bitstream Version Register

Read via `CTRL[31:16]` at BAR2+0x18000. Driver logs at init: `PTP hardware detected, version 0xNNNN`.

| Version | Date | Description |
|---------|------|-------------|
| 0x0100 | 2026-04-15 | Async FIFO RX CDC, separate ptp_time_rx (wrong clock domain) |
| 0x0200 | 2026-04-16 | ctl_rx_systemtimerin = ptp_time (correct domain, stale SOP tuser) |
| 0x0201 | 2026-04-16 | SOP-beat tuser uses rx_ptp_ts_raw — **built and tested**; plumbing works, servo does not converge due to timestamp jitter |

---

## Test Setup (2026-04-16)

### Physical Topology

```
  desktop-2 (AU200 FPGA, slave)     desktop (Mellanox, master)
  ┌──────────────────────┐         ┌──────────────────────┐
  │  enp1s0f0            │──QSFP───│  enp2s0np0           │
  │  PTP Slave           │ direct  │  PTP Master          │
  │  CMAC port 0         │ cable   │  ConnectX-5          │
  │  /dev/ptp4           │         │  /dev/ptp1           │
  └──────────────────────┘         └──────────────────────┘
```

### Reference (Mellanox-to-Mellanox, verified 2026-04-16)

```
ptp4l: master offset converges to <10 μs, path delay ~55 μs, servo stays in SLAVE
```

### Test Commands

```bash
# Master (desktop):
sudo ptp4l -i enp2s0np0 -H -2 --masterOnly=1 -m

# Slave (desktop-2):
sudo phc_ctl /dev/ptp4 set
sudo ptp4l -i enp1s0f0 -H -2 --slaveOnly=1 -m

# Verify bitstream version:
dmesg | grep "PTP hardware detected"
# Expected: version 0x0201
```

---

## Next Steps (Priority Order)

1. **Isolate RX timestamp jitter source** — ILA capture of `rx_ptp_tstamp_out[79:0]` on the SOP beat at the CMAC boundary for 10 consecutive PTP Sync frames. Expected cadence is 1 s ± <100 ns. If those values jitter by µs, the CMAC is misconfigured; if clean, the jitter is introduced between CMAC and `m_axis_rx_tuser_ptp_ts`.
2. **Verify TX reference plane** — confirm `tx_ptp_tstamp_out` from the CMAC is the SFD-on-wire time (vs enqueue time) and that both TX and RX stamps refer to the same pipeline stage. Check/configure CMAC PTP latency-adjust registers if a constant bias remains after jitter is fixed.
3. **ptp4l `-l 7` per-message trace** — identify whether forward leg (t2−t1) or reverse leg (t4−t3) is the dominant noise contributor. This narrows RX vs TX without touching the FPGA.
4. **Remove driver diagnostics** — once servo converges: RX DIAG, TX DIAG, the 5 µs udelay in `onic_xmit_frame`, and debug prints reduced to dev_dbg.
5. **Clean up FPGA dead code** — `ptp_time_rx` port and residual async FIFO path in `ptp_subsystem.sv` (superseded by Bug #9 fix).
6. **Measure steady-state accuracy** — once locked: offset jitter, path-delay stability, lock time from cold start, behavior under CMAC link flap.
7. **Two-shell (FPGA↔FPGA) test** — once single-ended convergence is achieved against Mellanox, repeat against a second FPGA instance for wire-to-wire and round-trip latency measurement (see `docs/ptp_timestamping.md`).
