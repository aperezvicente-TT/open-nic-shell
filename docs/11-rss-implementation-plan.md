# Chapter 11 — Implementation Plan: Per-Port RSS Coexisting with qid-Steering

A step-by-step plan to add Receive Side Scaling **within** each CMAC's queue block,
while keeping the qid's high bit(s) as the port selector. Read Ch. 10 §2.1 for the
concept and Ch. 3 for the qid graft this builds on.

> **✅ STATUS: IMPLEMENTED & HARDWARE-VERIFIED (2026-07-03).** Shell RTL commit
> `5117c3c` (`RSS_ON_EXT`), driver commit `5b0e4c8` (default indir + Toeplitz key).
> Bitstream built (timing met, WNS 0.000), flashed (build-stamp `0x07021704`).
> See §11.12 for the on-hardware verification results.

## 11.1 The design in one paragraph

The absolute qid is `{ cmac_sel | rss_idx }`, split at `QID_LO_W = 6`. The plugin already
tags each RX packet with `qid = cmac·64` — i.e. the **high** bits carry the CMAC and the
**low 6 bits are zero**. The QDMA C2H path already computes a Toeplitz hash on every
packet (`hash_inst`, always instantiated) but discards it under `EXT_QID=1`. The plan is
to **OR the RSS-derived low bits onto the plugin's external qid** inside
`qdma_subsystem_function`:

```
final_qid = external_qid  |  ( indir_table[hash_result[6:0]] & 0x3F )
          = (cmac·64)      |  rss_idx∈[0,64)
          = cmac·64 + rss_idx
```

Because the plugin's low bits are already zero, the OR is exact — **no plugin RTL change
is needed**. The driver side (multi-queue, indirection-table + key programming via ethtool
`-X`) is already ~90 % wired (Ch. 10 §10.2 note); it needs small additions only.

## 11.2 Where things stand in the code (anchors)

| Fact | Location |
|------|----------|
| Hash engine always on; emits `hash_result_valid` + `hash_result[31:0]` | `qdma_subsystem_function.sv:452-464` |
| RSS lookup (EXT_QID=0 path): `indir_table[getvec(16,hash_result[6:0])] + q_base` | `:510-513` |
| `qid_fifo` (per-packet qid, written on `hash_result_valid`, read on output tlast) — only built for `EXT_QID==0` | `:524-571` |
| Output qid mux: `EXT_QID? buf_tuser_qid : qid_fifo_dout` | `:695-696` |
| Output valid gate `... && ~qid_fifo_empty` (already present) | `:691,698` |
| Plugin RX tag `qid = cmac·PER_CMAC_QUEUES` (low bits zero) | `eth_2cmac_1pf_250mhz.sv:353` |
| Driver programs indir table + key via ethtool | `onic_ethtool.c:583,591` |
| Driver already allocates N rx queues + per-queue NAPI | `onic_lib.c:422-446` |

## 11.3 Milestone 0 — decisions before touching code

1. **Mode encoding.** Add a new parameter `RSS_ON_EXT` (0/1). Combine-mode is active only
   when `EXT_QID==1 && RSS_ON_EXT==1`. This keeps the existing `EXT_QID==0`/`==1` generate
   conditions readable rather than overloading `EXT_QID` with a third value.
2. **Queue count per port for v1.** Start with **4** rx queues/port (small, easy to verify
   fan-out), scale later.
3. **Hash function.** Reuse the existing Toeplitz `hash_inst` (already running, already
   keyed by the driver). No new hash RTL.
4. **Indirection table semantics change.** Entries become **intra-CMAC** queue indices in
   `[0, PER_CMAC_QUEUES)` (we take the low `QID_LO_W` bits), not absolute qids. The driver
   must fill them accordingly (§11.6).

## 11.4 Step 1 — RTL parameter plumbing

Thread `RSS_ON_EXT` from the top down, mirroring how `EXT_QID` is plumbed.

- `src/open_nic_shell.sv:~745` — on the `qdma_subsystem` instance, add `.RSS_ON_EXT(1)`
  next to `.EXT_QID(1)`.
- `src/qdma_subsystem/qdma_subsystem.sv` — add `parameter int RSS_ON_EXT = 0` (near the
  `EXT_QID` param, ~line 28) and forward it to each `qdma_subsystem_function` instance
  (`.RSS_ON_EXT(RSS_ON_EXT)`, ~line 833).
- `src/qdma_subsystem/qdma_subsystem_function.sv` — add `parameter int RSS_ON_EXT = 0`
  (after `EXT_QID`, ~line 30).

## 11.5 Step 2 — the combine logic in `qdma_subsystem_function.sv`

Three surgical edits. Define a localparam for readability near the top of the module body:

```verilog
localparam int COMBINE = (EXT_QID == 1) && (RSS_ON_EXT == 1);
localparam int QID_LO_W = 6;   // = $clog2(PER_CMAC_QUEUES); low bits are the RSS index
```

### 2a. Compute the RSS low bits (extend the qid-compute generate, `:482-520`)

Today the `EXT_QID==1` branch (`gen_ext_qid_passthru`) ties `qid_fifo_wr_en=0`. Change it
so that **in combine-mode** it drives the same per-packet write the RSS path uses, but
storing only the low bits:

```verilog
generate if (EXT_QID == 1 && RSS_ON_EXT == 0) begin : gen_ext_qid_passthru
    // full-external qid (unchanged behavior)
    always @* begin qid_fifo_wr_en = 1'b0; qid_fifo_din = 11'd0; end
    assign qid_fifo_rd_en = 1'b0;
end
else begin : gen_qid_compute   // RSS (EXT_QID==0) OR combine (EXT_QID==1 && RSS_ON_EXT)
    reg s_c2h_in_pkt_r;
    // ... (unchanged in-packet tracker) ...
    always @(posedge axis_aclk) begin
      if (~axil_aresetn) begin qid_fifo_wr_en <= 1'b0; qid_fifo_din <= 0; end
      else if (hash_result_valid) begin
        qid_fifo_wr_en <= 1'b1;
        qid_fifo_din   <= COMBINE
          ? {5'd0, indir_table[`getvec(16, hash_result[6:0])][QID_LO_W-1:0]} // low bits only
          : indir_table[`getvec(16, hash_result[6:0])] + q_base;            // legacy RSS
      end
      else qid_fifo_wr_en <= 1'b0;
    end
    assign qid_fifo_rd_en = m_axis_c2h_tvalid && m_axis_c2h_tlast && m_axis_c2h_tready;
end
endgenerate
```

### 2b. Instantiate `qid_fifo` in combine-mode too (`:524-571`)

Change the instantiation condition from `EXT_QID == 0` to "not full-external":

```verilog
generate if (EXT_QID == 0 || (EXT_QID == 1 && RSS_ON_EXT == 1)) begin : gen_qid_fifo_inst
    xpm_fifo_sync #( ... ) qid_fifo_inst ( ... );   // unchanged body
end
else begin : gen_qid_fifo_tieoff   // only full-external EXT_QID=1, RSS_ON_EXT=0
    assign qid_fifo_dout  = 11'd0;
    assign qid_fifo_empty = 1'b0;
    assign qid_fifo_full  = 1'b0;
end
endgenerate
```

### 2c. Combine at the output mux (`:695-696`)

```verilog
assign m_axis_c2h_tuser_qid =
    COMBINE       ? (axis_c2h_buf_tuser_qid | {5'd0, qid_fifo_dout[QID_LO_W-1:0]}) // hi|lo
  : (EXT_QID==1)  ?  axis_c2h_buf_tuser_qid                                         // full-ext
  :                  qid_fifo_dout;                                                 // legacy RSS
```

The existing `~qid_fifo_empty` gate on `m_axis_c2h_tvalid`/`axis_c2h_buf_tready`
(`:691,698`) now correctly holds each packet until its hash result is ready — the same
alignment discipline the legacy RSS path uses. No new backpressure logic.

**Why this is aligned & packet-atomic:** the high bits ride the byte-locked `buf_fifo`
TUSER (constant across the frame); the low bits come from `qid_fifo` (one entry/packet,
FWFT, read on output tlast). Both are stable for the whole packet and read out together.

## 11.6 Step 3 — plugin: no change (verify only)

The plugin already emits `qid = cmac·PER_CMAC_QUEUES` with zero low bits
(`eth_2cmac_1pf_250mhz.sv:353`), which is exactly the high-bits-only value the OR expects.
**Confirm** (don't change) that the RX tag path still drives `s_axis_c2h_tuser_qid` with
`cmac·64`. Optionally assert in sim that `qid[QID_LO_W-1:0] == 0` at the plugin output so a
future change can't silently break the OR.

## 11.7 Step 4 — driver changes (small)

| Change | File | Notes |
|--------|------|-------|
| Advertise hashing | `onic_main.c` (`onic_alloc_netdev`) | add `NETIF_F_RXHASH` to `features`/`hw_features` |
| Record the hash on skbs | `onic_netdev.c:onic_rx_poll` | `skb_set_hash(skb, hash, PKT_HASH_TYPE_L4)` — hash can come from a C2H completion field or be left to the stack; at minimum enable RPS/RSS queue spread |
| Default indirection table in `[0, num_rx_queues)` | driver init / `onic_set_rxfh` | entries are now **intra-CMAC** indices; ensure `ring_index[i] < num_rx_queues` (the existing bound check at `onic_ethtool.c:580` already guards `>= num_rx_queues`) |
| Ensure `real_num_rx_queues > 1` per netdev | `onic_lib.c:445` | already computed from `num_q_vectors`; confirm MSI-X budget gives ≥4/port |
| Fill the Toeplitz key | already done via `onic_set_rxfh` (`onic_ethtool.c:591`) | must be programmed before traffic; add a sane default at init if not present |

No queue-allocation rewrite is needed — the per-queue rings, MSI-X vectors, and NAPI
already exist (`onic_netdev.c:1011`, `onic_lib.c:232`); they simply start receiving once
the FPGA stops pinning every packet to low-index 0.

## 11.8 Step 5 — build

Rebuild the bitstream with the wrapper (Ch. 6 §6.2); `RSS_ON_EXT=1` is now hardcoded on
the instance so no new build flag is required. Rebuild `onic.ko` (Ch. 5 §5.7).

## 11.9 Step 6 — bring-up & verification

1. Load driver; confirm each netdev shows **>1** rx queue: `ethtool -l enp1s0`.
2. Program/verify the indirection table + key: `ethtool -x enp1s0`.
3. **Fan-out test:** generate many flows per port —
   `iperf3 -c 10.99.0.2 -P 8` (8 parallel streams, distinct 4-tuples) — and confirm they
   land on multiple queues:
   - `ethtool -S enp1s0 | grep rx_queue` (per-queue packet counts should be spread).
   - Plugin diag counters still increment on the right CMAC (Ch. 8 §8.3).
4. **Correctness regressions (must still pass):**
   - 0 % loss on both ports concurrently (Ch. 7 §7.6).
   - No in-flow reordering (a single TCP stream must stay on one queue — verify no
     `RX_MARK_MISMATCH`/`TX_QID_CHANGED` trip-wire increments, Ch. 8 §8.3, and no TCP
     reordering counters climbing).
   - CMAC steering unchanged: CMAC0 traffic never appears on a CMAC1 queue (qid ≥ 64) and
     vice-versa.
5. **Table remap test:** rewrite the indirection table with `ethtool -X enp1s0 equal 2`
   and confirm the spread collapses to 2 queues — proves the table is live.

## 11.10 Risks & watch-outs

- **Shared indirection table across ports.** Single PF → one indir table + key for both
  CMACs. Both ports use the same hash→index pattern (each within its own block). Fine for
  v1; per-port tables would need a second table indexed by CMAC (extra RTL + driver).
- **Hash-result timing.** `hash_result_valid` must fire once per packet before output
  tlast (it does today for RSS). The combine path reuses that exact discipline; verify in
  sim with back-to-back small packets.
- **`hash_result[6:0]` → 128 buckets → ≤64 queues.** 2:1 bucket:queue folding is fine; the
  indir table maps buckets to queue indices.
- **TUSER widths unchanged.** qid stays 11 bits end-to-end — none of the 27/107-bit width
  chains (Ch. 3 §3.3-3.4) move. This is the biggest derisking factor vs. the original graft.
- **Driver default key.** If no key is programmed, the hash degenerates; ship a default
  Toeplitz key at init.

## 11.11 Effort summary

| Piece | Effort |
|-------|--------|
| RTL param plumbing (Step 1) | S |
| `qdma_subsystem_function` combine logic (Step 2) | M (3 small edits + sim) |
| Plugin (Step 3) | none (verify) |
| Driver (Step 4) | S |
| Build + bring-up + verification (Steps 5-6) | M (incl. a full FPGA rebuild ~3-5 h) |

**Overall ≈ M**, dominated by verification and the rebuild — not by new logic. The
design reuses the always-on hash, the existing `qid_fifo` alignment mechanism, the
existing output-gate, and the existing driver ethtool/queue plumbing.

## 11.12 Verification results (on hardware, 2026-07-03)

Build-stamp `0x07021704` flashed and live; `num_cmacs=2`; 14 rx queues/port; MSI-X
32 vectors / 14 queue-vectors per CMAC. `ethtool -x enp1s0` confirmed the default
indirection table (`i % 14`) and the programmed 40-byte Toeplitz key (Toeplitz on).

> **How spread was observed:** the driver exposes no per-queue counters in
> `ethtool -S`, so RX fan-out was measured via **per-queue MSI-X interrupt deltas** in
> `/proc/interrupts` (`onic1s0f0c<cmac>-<q>`). Load was generated with **reverse iperf**
> (`iperf3 -c <peer> -R -P 8`) so the remote transmits and the *host* receives, which is
> what exercises host-side RSS. (iperf3 here is the local build at
> `/home/alex/mpi-shfs/fpga/iperf/src/iperf3`, not in `PATH`.)

| Test | Expected | Result |
|------|----------|--------|
| CMAC0 fan-out, 8 streams | spread across many queues | **6–7 / 14** queues active |
| CMAC1 fan-out, 8 streams | spread across many queues | **5 / 14** queues active |
| Steering isolation | load on one CMAC never touches the other's queues | CMAC0→**0** c1 queues; CMAC1→**0** c0 queues |
| `ethtool -X enp1s0 equal 2` | spread collapses to 2 | **2 / 14** queues |
| Single flow (`-P 1`) | stays on one queue (ordering) | **1 / 14** queue |
| Trip-wires `0x100040`/`0x100044` | 0 | **0 / 0** |
| Concurrent ping both ports, 1000 pkts each | 0% loss | **0% / 0%** |

All pass. Per-port RSS coexists with qid-steering: flows fan out across cores *within*
each CMAC's queue block, the CMAC-select high bits keep the two ports isolated, and a
single flow stays on one queue (in-order). The `equal 2` result proves the indirection
table is live and controllable at runtime via `ethtool -X`.

**Caveat unchanged:** aggregate RX throughput is still bounded by the remote peers'
Gen3 ×4 PCIe slot (~22 Gbps), so RSS's benefit here is *distribution across cores*, not a
higher aggregate number on this particular bench (Ch. 8 §8.6).

## 11.13 Root cause: C2H LEN/MTY mismatch under multi-queue RSS (2026-07-29)

> **Status: RTL fix committed, UNBUILT and unverified on hardware.** Requires a
> rebuild (§6.2) and a re-run of the measurements below.

Hardware traffic testing against a 100G ConnectX-7 peer (see Ch. 8 §8.8) showed
QDMA raising **fatal** C2H errors whenever RSS spread traffic over more than one
queue:

```
C2H_ERR_STAT = C2H_FATAL_ERR_STAT = 0x3
  bit 0  MTY_MISMATCH   last-beat empty-byte count inconsistent with tlast
  bit 1  LEN_MISMATCH   completion length != bytes actually transferred
C2H_FIRST_ERR_QID = 7
```

### Evidence

| Config | Throughput | Error IRQs / 10 s |
|--------|-----------|-------------------|
| 14 queues, unlimited | 45.9 Gbit/s | 104 |
| 14 queues, rate-limited | 21.4 Gbit/s | **183** |
| 2 queues, unlimited | 48.8 Gbit/s | 8 |
| 1 queue, unlimited | 27.3 Gbit/s | **0** |
| 1 queue, rate-limited | 23.5 Gbit/s | **0** |

Two properties pin the mechanism down: the error count tracks the **number of
distinct qids in flight**, not the rate; and it *rises as the rate falls*, which
excludes a high-rate race and points at idle/stall cycles.

### Cause

`qdma_subsystem_hash.sv` state `S_S1_MORE` asserted `eth_payload_valid` and
advanced the FSM **outside** the `p_axis_tvalid && p_axis_tready` handshake, also
sampling `p_axis_tlast` with no beat transferred. `hash_result_valid` derives from
it (`:458`), and in RSS/combine mode that signal pushes `qid_fifo` while the pop is
driven by the *output* `tlast` (`qdma_subsystem_function.sv:535`). Any spurious
pulse desynchronises push from pop, after which every packet carries a
neighbour's qid — so the completion length lands on the wrong queue.

A uniform indirection table (`ethtool -X ... equal 1`) hides it completely, which
is why Ch. 11's original bring-up (ping + per-queue IRQ spread) passed: the qid is
*wrong* but still inside the correct CMAC's block, so steering isolation and
trip-wires stay clean.

**This defect is pre-existing and also affects the legacy `EXT_QID=0` RSS path.**
`RSS_ON_EXT=1` merely re-exposed it, by returning `qid_fifo` to the `EXT_QID=1`
datapath that v5.2.10 had deliberately moved off it (`:484-490` calls the same
symptom "first-beat-vs-tlast pipelining asymmetry ... ~14% misroute").

### Fix

Move the payload-valid pulse and the state advance inside the handshake, so
`hash_result_valid` fires exactly once per packet. The module synthesises clean
out-of-context (3347 cells).

### Still open

- Rebuild + re-measure: does the error count go to zero at 14 queues, and how much
  of the RX throughput ceiling (Ch. 8 §8.8) was these drops?
- Consider carrying the RSS low bits in the `buf_fifo` TUSER alongside the data,
  as v5.2.10 did for the external qid, so correctness no longer depends on two
  independent pipelines staying aligned.

## 11.14 §11.13 hypothesis DISPROVEN — rebuilt, reflashed, re-measured (2026-07-29)

The `S_S1_MORE` handshake guard was built (stamp `0x07290823`, WNS +0.020 ns) and
flashed. **It did not change the C2H error behaviour**, so the handshake defect —
real though it is — is not the cause of `MTY_MISMATCH`/`LEN_MISMATCH`:

| Config | errIRQ before (`0x07290109`) | errIRQ after (`0x07290823`) |
|--------|------------------------------|------------------------------|
| 14 queues, unlimited | 104 | 94 |
| 14 queues, rate-limited | 183 | 652 |
| 2 queues | 8 | 48 |
| 1 queue | 0 | 0 |

Keep the fix (an unguarded FSM advance is wrong regardless), but the root cause is
still open.

### Two measurement lessons

**Error-IRQ counts are not an error rate.** `ERROR_REARM_DELAY_MS = 2`
(`onic_lib.c:207`) throttles re-arming, so the count is a floor on burst events,
modulated by workqueue scheduling. Two runs at the same underlying rate can differ
several-fold. Do not compare them as rates — the table above is illustrative only.

**Use the QDMA C2H statistics registers** (BAR **0**, not BAR2):

| Offset | Counter |
|--------|---------|
| `0xA88` | `C2H_STAT_S_AXIS_C2H_ACCEPTED` — packets accepted from the user stream |
| `0xA90` | `C2H_STAT_DESC_RSP_PKT_ACCEPTED` |
| `0xB10` | `C2H_STAT_DESC_RSP_DROP_ACCEPTED` — **drops** |
| `0xB14` | `C2H_STAT_DESC_RSP_ERR_ACCEPTED` — **errored packets** |

```bash
sudo onic-bar-read 0000:c2:00.0 0xB10 --bar 0     # drops
```

### What the counters actually say (stamp 0x07290823, MTU 9000, -P 8)

| Config | Throughput | accepted | DROP | ERR |
|--------|-----------|----------|------|-----|
| 14 queues | 58.8 Gbit/s | 8,214,680 | 564 (0.007%) | **0** |
| 14 queues, rate-limited | 21.5 Gbit/s | 3,022,988 | 3,265 (0.11%) | **0** |
| 1 queue | 26.1 Gbit/s | 3,678,995 | 30,610 (0.83%) | **0** |

So:

1. **No packets are counted as errored.** The MTY/LEN status bits assert, but
   `DESC_RSP_ERR_ACCEPTED` stays 0 — the condition costs no packets that QDMA
   accounts for. It remains a protocol-correctness concern, not a loss source.
2. **Real loss is descriptor starvation** (`DESC_RSP_DROP_ACCEPTED`), and it scales
   *inversely* with queue count: 0.83% on one queue, 0.007% on fourteen. That is
   ordinary capacity exhaustion and points at ring sizing — which cannot currently
   be tuned at all (`ethtool -g/-G` unimplemented, Ch. 10 §1.4).
3. **The errors are traffic-triggered, not latched**: zero error IRQs during 12 s
   idle, both on a running driver and after a fresh reload.
4. **The throughput ceiling is not explained by loss.** With `ERR=0` and drops at
   0.007%, the 39-69 Gbit/s spread on one port needs a different explanation.

### Open, in priority order

- Throughput ceiling + run-to-run variance (39-69 Gbit/s single port, ~70 aggregate).
  Not loss-driven; profile the C2H completion path and the driver's NAPI/refill.
- Descriptor starvation at low queue counts — needs `ethtool -g/-G` (§1.4) first.
- MTY/LEN status: audit the qid/length timing in `qdma_subsystem_function.sv`. The
  leading structural suspicion is that `qid_fifo_dout` only advances on the output
  `tlast` (`:535`), so a packet's early beats present the *previous* packet's qid;
  if QDMA samples TUSER qid at the first beat, that is a systematic misassignment
  invisible with a uniform indirection table. Fix would carry the RSS low bits in
  the `buf_fifo` TUSER (as v5.2.10 did for the external qid) or pop at SOP and hold
  for the packet.
