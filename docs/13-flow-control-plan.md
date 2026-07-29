# Chapter 13 — Implementation Plan: Link-Level Flow Control (the C2H drop root cause)

A plan to close the burst-robustness gap measured in Ch. 8 §8.8.2, where this
datapath drops 1.2-3.6 % of unpaced UDP that a ConnectX-7 on the same bench absorbs
losslessly. The root cause is identified and it is not a tuning parameter.

> **Status: Step 0 DONE (driver `2024258`). Steps 3/4b/5 attempted and BLOCKED on
> the measurement instrument — see §13.10.** The root cause in §13.1 stands on the
> CX-7 comparison and code inspection, but the tuning experiments cannot be
> evaluated with iperf3 UDP: drop rate spans 0.0000-6.16 % at identical settings.
> A precise packet generator is now the first prerequisite, not the last step.

## 13.1 Root cause

**This design has no link-level flow control, so its only response to receive
overload is to discard.**

Evidence, in the order it was established:

| Observation | Source |
|-------------|--------|
| Unpaced UDP at 40 G offered → **1.2-1.9 %** drops, every run | Ch. 8 §8.8.1 |
| ConnectX-7, same host/peer/MTU/binary → **0.0000 / 0.0753 / 0.0000 %** | Ch. 8 §8.8.2 |
| CX-7↔CX-7 reference link has **pause RX on, TX on** at both ends | `ethtool -a` |
| The FPGA's own peer port (`enp130s0f0np0`) also has **pause RX/TX on** — it *would* honour pause frames | `ethtool -a` |
| The FPGA link has **never sent or received one**: `stat_tx_pause = 0`, `stat_rx_pause = 0` | `ethtool -S enp194s0` |
| `ethtool -a` on our netdev → `Operation not supported` | driver has no `get/set_pauseparam` |
| `ctl_tx_pause_req[8:0]` **exists** in the CMAC wrapper but is never driven | `cmac_subsystem_cmac_wrapper.sv:94` |
| Every RX-path FIFO fill output is left unconnected — `.almost_full()`, `.prog_full()` | `eth_2cmac_1pf_250mhz.sv:394-395`, `packet_adapter_rx.sv:273-279` |

### Why this also explains the TCP/UDP asymmetry

Ch. 8 §8.8.1 left one thing unexplained: TCP sustains ~1.37 Mpps at ≤0.33 % drops,
**2.4x the packet rate** at which UDP drops 1.2 %. No average-rate or buffer-size
argument covers that. Flow control does:

- **TCP carries its own end-to-end backpressure.** Loss shrinks the window, so the
  sender paces itself to just under the receiver's capability. It rarely presents an
  unpaced burst.
- **UDP has none.** iperf3 emits bursts at line rate inside each pacing interval, so
  the instantaneous arrival rate greatly exceeds the drain rate.
- A NIC with pause converts that into *backpressure on the sender*. A NIC without it
  has only one option left: drop.

So the gap is not "the CX-7 has deeper buffers" — it is "the CX-7 can say stop".

### What is NOT the cause (ruled out by measurement)

| Hypothesis | Verdict |
|------------|---------|
| Descriptor ring depth | Ruled out — 8x (2049→16385) changed nothing at comparable delivered rates (§8.8.1) |
| Posted-descriptor window | Not supported — 256→1024 within variance; **note the large-ring + large-window combination was never tested**, see §13.5 |
| Completion coalescing | Not the cause of drops; it *raised capacity* 2.7x and thereby moved the operating point to where drops appear |
| C2H `MTY`/`LEN` protocol errors | Unrelated — `DESC_RSP_ERR_ACCEPTED` is 0 in every measurement (Ch. 11 §11.14) |
| Peer or wire faults | Ruled out — peer `rx_dropped` 0, CMAC FCS/error 0 |

## 13.2 Step 0 — make the drops visible ✅ DONE (driver `2024258`)

Today `rx_dropped` reads 0 while packets are discarded; the only evidence is
`DESC_RSP_DROP` in BAR0 `0xB10`. A ConnectX-7 reports the identical class of drop in
`rx_dropped` (measured: 919 hardware drops, 919 in `rx_dropped`).

- read the QDMA C2H stats (`0xA88` accepted, `0xB10` drop, `0xB14` err) and add them
  to `ethtool -S`;
- fold the drop counter into `get_stats64`'s `rx_dropped` (and `rx_missed_errors`,
  which is the more precise kernel semantic for "ran out of buffer");
- add `stat_rx_pause` / `stat_tx_pause` to the same output — they are already read
  from the CMAC and are the primary signal that Step 2 works.

This is Ch. 10 §1.6, is required to validate every later step, and needs no RTL.

**Implemented and verified.** `ethtool -S` now reports `plugin_rx_adap_in` (per-CMAC),
both trip-wires, and `qdma_c2h_{accepted,desc_rsp_drop,desc_rsp_err}`; `get_stats64`
fills per-port `rx_dropped`/`rx_missed_errors` from the plugin counter, since the QDMA
register is device-global. Agreement to within one packet under 40 G unpaced UDP:

```
ip -s link:  packets 6,607,833   dropped 133,629   missed 133,629
ethtool -S:  accepted 6,741,463  desc_rsp_drop 133,630   (6,607,833 + 133,630 = ✓)
```

Two traps handled: the plugin counter is cumulative since bitstream load while netdev
counters reset per driver load (baseline seeded at open), and it is 32-bit (deltas
accumulated with natural wrap).

## 13.3 What is already configured (checked against live hardware)

The CMAC's pause/PFC machinery is **enabled and fully programmed** — this is not a
configuration gap. Read back from CMAC0 while running:

```
CONF_TX_FC_CTRL_1 (BAR2 0x8030) = 0x000001FF   9 enables = 8 PFC priorities + global pause
CONF_RX_FC_CTRL_1 (BAR2 0x8084) = 0x00003DFF   9 RX pause enables + GCP/PCP check bits
CONF_RX_FC_CTRL_2 (BAR2 0x8088) = 0x0001C631
```

`onic_enable_cmac()` (`onic_hardware.c:243-258`) writes those plus **all five quanta
and all five refresh registers to maximum** (`0xFFFFFFFF`…`0x0000FFFF`) on every CMAC
enable. Note it is *not* enabled through IP generics — `cmac_usplus_0_au200.tcl` sets
no flow-control `CONFIG.*` parameter, so with `ENABLE_AXI_INTERFACE=1` the whole
configuration lives in these AXI-Lite CSRs.

**So the only thing missing for pause generation is the request.** That shrinks Step 2:
no CSR work, just the RTL path in §13.4.

Two consequences worth carrying into the implementation:

- **Quanta are maxed (0xFFFF per priority).** The first pause frame we ever emit would
  request the longest possible duration, and refresh is likewise maxed. Over-long
  pause converts a drop problem into a stall problem — these want tuning alongside
  §13.4, not leaving at reset-max.
- **`ethtool -a/-A` still needs implementing** (Ch. 10 §1.5) so the feature is
  operator-visible and switchable, but it is reporting/40-line work, not enablement.

### 13.3.1 Separate bug: we ignore pause frames sent *to* us

`stat_rx_pause_req[8:0]` — the CMAC's "the peer is asking us to pause" output — is
wired to the IP instance (`cmac_subsystem_cmac_wrapper.sv:611`, `:935`) and then
**never read by any shell logic**. The CMAC USplus does not auto-throttle TX on
received pause; the user logic must do it. So a congested peer that pauses us is
ignored and we keep transmitting.

Latent on this bench (`stat_rx_pause = 0` — no peer has ever needed to pause us), but
it is an 802.3x conformance bug against any real congested switch, it is on the
**transmit** side, and it is independent of the RX drop story in §13.1. Fix alongside
§13.4 since it touches the same wrapper: gate the H2C/TX path on
`stat_rx_pause_req`, per CMAC.

## 13.4 Step 2 — RTL: drive `ctl_tx_pause_req` from RX-path fill (M, the actual fix)

The CMAC will emit pause frames when `ctl_tx_pause_req` is asserted; the missing
piece is a fill-level signal to drive it. Design:

1. Take `prog_full` (or `almost_full`) from the RX-path FIFO closest to the QDMA
   handoff — `packet_adapter_rx.sv:273-279` already exposes both and discards them.
   That FIFO filling *is* the definition of "the host is not draining fast enough".
2. Add a small hysteresis block: assert on `prog_full`, deassert on a lower
   watermark, so pause is not toggled per beat. Program `prog_full`/`prog_empty`
   thresholds via the existing FIFO generics rather than new logic where possible.
3. Drive `ctl_tx_pause_req[8]` (global pause) — or a chosen priority for PFC later —
   and hold it for the CMAC's configured quanta.
4. The quanta / refresh registers are already programmed (§13.3) — **retune them
   down from 0xFFFF** rather than programming them, and gate the whole feature on the
   driver's `set_pauseparam` so it defaults to today's behaviour until deliberately
   enabled.

**Per-CMAC scoping matters.** The two CMACs share one PF and one QDMA. Pause must be
asserted for the CMAC whose queues are backing up, not both, or one port's overload
throttles the other's sender. The RX FIFOs are already per-CMAC in the plugin, so the
fill signal is naturally per-port — keep it that way through to
`ctl_tx_pause_req`.

**Risk: head-of-line blocking.** Pause stops *all* traffic on that port, including
flows whose queues are fine. That is inherent to 802.3x pause and is why PFC exists.
Acceptable for a first cut; note it, and treat per-priority PFC as a later option.

## 13.5 Step 3 — retest the one buffering combination never covered (S)

`rx_desc_step` is clamped to ≤ ring/4, so the earlier sweeps could not raise the
posted window beyond 512 on the default 2049-entry ring — and `rx_desc_step=4096`
against that ring silently wedged the datapath (now guarded, driver `ad1a5d1`).
**Large ring and large window together was therefore never measured.** Test
`desc_rngcnt_idx=15 cmpl_rngcnt_idx=15 rx_desc_step=4096` (posted window
2048-6144, ~16x today) at fixed 40 G offered UDP before concluding buffering is
irrelevant. Cheap, and it either closes part of the gap or removes the last doubt.

## 13.6 Step 4 — QDMA C2H prefetch over-subscription (S-M, secondary)

Read from hardware:

```
C2H_PFCH_CFG_1 (0xA80) = 0x000c000c  ->  EVT_QCNT_TH = 12,  QCNT = 12
C2H_PFCH_CFG_2 (0xA84) = 0x804003c8  ->  FENCE=1, LL_SZ_TH=1024, VAR_DESC_NUM=15, NUM=8
C2H_PFCH_CFG   (0xB08) = 0x01000100  ->  EVT_PFCH_FL_TH = 256, PFCH_FL_TH = 256
C2H_PFCH_CACHE_DEPTH (0xBE0) = 0x001f0010  ->  MAX_STBUF = 31, CACHE_DEPTH = 16
```

The prefetch engine tracks **12 queues** and caches **16** entries, while this design
runs **14 RX queues per port, 28 total**. Over-subscription means prefetch context
eviction and longer descriptor-fetch latency exactly when a burst arrives. Test by
(a) raising `QCNT`/cache depth if the hardware permits, and (b) reducing active
queues per port to ≤12 via `ethtool -X` and re-measuring — (b) needs no code and
would confirm or kill the hypothesis in one run.

## 13.7 Step 5 — the missing instrument (M)

Nothing here resolves *how deep* a burst the path can absorb, because 0.5 s counter
sampling cannot see a burst. Options, cheapest first:

- **Onset bisection:** binary-search the offered rate at which drops first appear,
  at several `rx_desc_step` values. The onset rate is a proxy for absorbable depth
  and needs no new tooling.
- **Sender-side pacing sweep:** iperf3 `--pacing-timer` / smaller `-b` bursts to vary
  burstiness at constant average rate. If drops track burstiness rather than average
  rate, that is direct confirmation of the §13.1 model.
- **Hardware burst counter:** a plugin diag counter recording max RX FIFO occupancy
  (a high-water mark register), which is a few lines of RTL next to the existing diag
  counters and answers the question directly.

The pacing sweep is the highest value per effort and should precede any RTL.

## 13.8 Verification

Success is defined against the reference on the same bench, not against ourselves:

| Test | Target |
|------|--------|
| 40 G offered unpaced UDP, MTU 9000, 14 queues | **≤ 0.1 %** drops (CX-7 measures 0.0000-0.0753 %) |
| 64 G offered | substantially better than today's 3.6 %; CX-7 does ~0.01 % |
| `stat_tx_pause` | non-zero once Step 2 is enabled — proof pause is actually emitted |
| TCP line rate | unchanged at 96-98 Gbit/s; pause must not cost throughput |
| Latency, idle | unchanged (~0.10 ms); pause must not add latency when not congested |
| `DESC_RSP_ERR_ACCEPTED` | remains 0 |
| Other port unaffected | load on CMAC0 must not throttle CMAC1's sender (§13.4) |

## 13.9 Effort and order

| Step | What | Effort |
|------|------|--------|
| 0 | Surface drops + pause counters (§1.6) | S |
| 3 | Large ring + large posted window retest | S |
| 4b | ≤12 queues via `ethtool -X`, re-measure | S |
| 5 | Pacing sweep (confirms the model) | S |
| 1 | `ethtool -a/-A`, RX pause reaction (§1.5) | S |
| 2 | RTL: fill → `ctl_tx_pause_req`, per CMAC | M |
| 4a | Prefetch register tuning | S-M |

Do 0, 3, 4b and 5 first: all are days, need no RTL, and either narrow or eliminate
the alternatives before committing to a gateware cycle. Step 2 is the real fix and
the only one that makes sustained overload lossless, but it costs a rebuild + reflash
(~78 min build, ~15 min flash) and should be entered with the model confirmed.

## 13.10 BLOCKER — the drop metric is not reproducible with iperf3 UDP

Steps 3 (§13.5), 4b (§13.6) and 5 (§13.7) were attempted. They cannot be evaluated,
because the measurement varies more between identical runs than between the
configurations under test.

Same command, same settings, 40 G offered unpaced UDP, MTU 9000, 14 queues,
NUMA-pinned server, measured with the new per-port counters:

| Config | drop % across runs |
|--------|--------------------|
| defaults | 1.2137, 0.0193, 0.0000, 3.8501 |
| rings 16385 + step 4096 | 2.1112, 0.1798, 0.0000, 0.0006 |
| step 4096 only | 0.5781, 1.6653, 0.3645, 0.0223 |
| rings 16385 only | 2.4187, 0.1817, 0.0024, 0.1416 |
| defaults (8 more runs) | 0.1427, 1.5412, 0.0004, 0.1108, 6.1557, 0.0028, 0.0000, 0.1335 |
| big-buffers (8 more runs) | 5.3001, 0.0114, 2.9634, 0.0147, 0.0097, 2.3969, 2.9950, 0.0058 |

**0.0000 % to 6.16 % at identical settings.** Stratifying by achieved offered rate
(which is bimodal, ~380k or ~545k pps) did not rescue it: one stratified batch showed
big buffers 16x *better* with no overlap, the next showed them worse. Four successive
promising results failed to replicate.

The premise was wrong: **iperf3 UDP is not a constant-rate source.** Delivered counts
varied 4.4-6.7 M for the same nominal offer, and the residual variance after
rate-stratification means something else (sender CPU scheduling, per-run burst shape,
receiver core placement) also moves per run.

### What this changes about the plan

- **No conclusion about buffering.** §13.5 is neither confirmed nor refuted; earlier
  wording in this chapter claiming ring depth was "ruled out" over-stated what a
  2-sample comparison can support. The only buffering statement that survives is
  structural: the posted window is [step/2, 1.5·step] regardless of ring size.
- **§13.7 moves to the front.** You cannot tune what you cannot measure. The
  instrument is now step 1, and the plan order in §13.9 is superseded by §13.11.
- **The §13.1 root cause is unaffected** — it rests on the CX-7 comparison (a 20x-plus
  gap, repeatedly reproduced, including three CX-7 repeats at 0/0.0753/0 %) and on
  code inspection showing `ctl_tx_pause_req` tied to zero. Not on these sweeps.

## 13.11 Revised order — instrument first

1. **Precise generator (S-M).** `pktgen` is available on both hosts (module present,
   not loaded) and emits an exact, constant pps from kernel context, removing the
   sender-side variance. Pin the receiver's iperf3/NAPI cores too. Acceptance test:
   the same configuration measured five times must agree within a factor of two
   before any tuning result is believed.
2. **Then re-run §13.5 / §13.6** (buffering, prefetch queue count) against that
   generator, medians of ≥5.
3. **Then the burst-depth question** — with a constant-rate source, sweep burst size
   at fixed average rate, which is the measurement that actually distinguishes
   "absorbs deeper bursts" from "drops earlier".
4. **§13.4 (pause generation) is independent of all of the above** and can proceed in
   parallel: its acceptance criterion is `stat_tx_pause` becoming non-zero and the
   CX-7-relative drop gap closing, both of which are large effects rather than the
   fractions-of-a-percent this instrument cannot resolve.
