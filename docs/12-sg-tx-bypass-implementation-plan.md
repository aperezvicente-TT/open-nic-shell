# Chapter 12 — Implementation Plan: Scatter-Gather TX via H2C Descriptor Bypass

A step-by-step plan to enable true scatter-gather TX (`NETIF_F_SG`) by running the
QDMA **H2C** queues in **descriptor-bypass mode**, so the driver's per-fragment
SOP/EOP framing is honoured and a paged skb becomes one CMAC packet. Read Ch. 10
§2.1 and the SG post-mortem (§10.2 item 1.3) first — this chapter is the fix for the
blocker found there.

> **⛔ STATUS: PHASE A ATTEMPTED, PARKED at an integration blocker (2026-07-15).**
> Prereq context: internal-mode H2C does **not** honour multi-descriptor SOP/EOP
> framing (6-encoding driver sweep all failed; on-wire capture showed fragmented
> frames truncated by one 64 B beat). Phase A (loopback bring-up) was built and
> run on hardware **twice** and failed Gate A both times — see §12.14.
>
> **⚠️ RE-DIAGNOSIS (2026-07-15, offline, §12.14.3):** the earlier "root cause is
> QDMA integration, needs ILA + vendor case" conclusion is now considered
> **premature**. The byp module was matched against the **wrong IP's** reference —
> `cpm5_qdma/dsc_byp_h2c.sv` is the **Versal CPM5 hardened** QDMA, but the U200
> (`xcu200`, Virtex UltraScale+) uses the **soft `qdma_v5_1` (EQDMA soft)** IP.
> Their bypass interfaces differ (`fmt` `[2:0]`vs`[3:0]`, `qid` `[11:0]`vs`[10:0]`,
> `func` `[11:0]`vs`[7:0]`), and the module **dropped the marker loopback**
> (`mrkr_req`/`mrkr_rsp`) that the soft IP's bypass interface defines. There is an
> **offline RTL fix to try before any card/ILA/vendor step** — see §12.14.3.
> The driver-side SG datapath and the byp module exist but are **uncommitted WIP**;
> `NETIF_F_SG` is not advertised.

## 12.1 The design in one paragraph

QDMA fetches each H2C descriptor from the host ring and, in bypass mode, hands it out
on `h2c_byp_out_*` instead of processing it internally. A new shell module decodes
the fetched descriptor (source address, length, SOP/EOP), and re-submits it on
`h2c_byp_in_st_*` with `no_dma=0`. The engine then DMAs each fragment and asserts
`tlast` only on the descriptor that carried EOP — so N fragments concatenate into one
packet. The driver's job shrinks to one line (`sw_ctxt.bypass = 1` on H2C queues) plus
re-advertising `NETIF_F_SG`; the multi-descriptor descriptor build is already written.
The **one non-obvious catch**: `byp_in` has no metadata field, so the shell's current
`metadata[15:0]`→`tkeep` scheme (Ch. 3) must be replaced by the QDMA IP's native
`tkeep` (or the existing `axi_stream_size_counter`).

## 12.2 Why bypass, not a coalescing shim

Internal mode discards the "these N descriptors are one packet" information; bypass is
the only place it still exists intact, and it's the Xilinx-documented path (their
reference driver builds multi-segment H2C exactly this way). A coalescing shim on the
AXI-ST *output* would have to reconstruct packet boundaries from a driver-smuggled
side-channel and assume strict ordering — strictly harder and non-standard. See §12.9
for the shim as a fallback. Trade-off to accept up front: bypass routes **all** H2C
traffic (including today's working linear TX) through the new module, so a bug there
breaks all TX, not just SG — hence the loopback-first step in §12.4.

## 12.3 Change surface (exact)

**No QDMA IP regeneration.** The IP is already generated with
`CONFIG.dsc_byp_mode {Descriptor_bypass_and_internal}` and the wrapper already brings
every bypass port out (`qdma_subsystem_qdma_wrapper.v:87-112`, both `qdma_no_sriov`
instances). Bypass-vs-internal is a per-queue *software-context* bit, not an IP option.

| Layer | File | Change |
|-------|------|--------|
| Shell RTL | `src/qdma_subsystem/qdma_subsystem.sv:307-320` | Replace the H2C tie-off block with the new bypass module (§12.5). |
| Shell RTL | `src/qdma_subsystem/qdma_subsystem_function.sv:366-370` | Replace metadata-based last-beat `tkeep` with IP-native `tkeep` / size-counter (§12.6). |
| Driver | `onic_hardware.c` `onic_qdma_init_tx_queue()` (~line 514) | Add `sw_ctxt.bypass = 1;` before `qdma_write_sw_ctxt` (packs `QDMA_SW_CTXT_W1_BYPASS_MASK = BIT(18)`). |
| Driver | `onic_main.c` `onic_apply_netdev_features()` | Re-advertise `NETIF_F_SG` (features + hw_features). |
| Driver | `onic_netdev.c` `onic_xmit_frame` | Already builds multi-descriptor SOP/EOP/per-frag-len — mirror the libqdma bypass convention (`pld_len = len`); no structural change. |

No prefetch-context change (that bit is C2H-only; H2C init never touches `qdma_pfch_ctxt`).

## 12.4 Step 0 — de-risk with a passthrough loopback (do this FIRST)

Before any fragment logic, prove the bypass datapath carries *normal* traffic:

1. Shell: wire a **straight `byp_out → byp_in` passthrough** — decode `addr`/`len`/
   `sop`/`eop` from `h2c_byp_out_dsc` and drive them onto `h2c_byp_in_st_*` verbatim,
   echoing `qid`/`cidx`/`func`/`port_id`, `no_dma=0`, `mrkr_req=0`, with the
   `_vld/_rdy` handshake.
2. Driver: `sw_ctxt.bypass = 1` on H2C queues, **SG still off** (packets stay linear /
   single-descriptor).
3. Build, flash, run linear iperf3. Expected: unchanged ~9.4 Gbit/s, 0 retr.
4. If linear TX regresses, the problem is the bypass plumbing itself — fix that before
   touching fragment framing. This isolates "does bypass work at all" from "does SG
   framing work."

## 12.5 Step 1 — the H2C bypass module

Signals (from `qdma_subsystem.sv:233-258`):

- **out (from IP):** `h2c_byp_out_vld`, `h2c_byp_out_dsc[255:0]`, `h2c_byp_out_qid[10:0]`,
  `h2c_byp_out_cidx[15:0]`, `h2c_byp_out_dsc_sz[1:0]`, `h2c_byp_out_func[7:0]`,
  `h2c_byp_out_port_id[2:0]`, `h2c_byp_out_st_mm`, `h2c_byp_out_fmt[3:0]`,
  `h2c_byp_out_error`; ack via `h2c_byp_out_rdy`.
- **in (to IP):** `h2c_byp_in_st_vld`, `_addr[63:0]`, `_len[15:0]`, `_sop`, `_eop`,
  `_qid[10:0]`, `_cidx[15:0]`, `_func[7:0]`, `_port_id[2:0]`, `_sdi`, `_mrkr_req`,
  `_no_dma`, `_error`; back-pressured by `h2c_byp_in_st_rdy` (IP output).

Descriptor decode — the 16 B H2C ST descriptor sits in the low 128 bits of
`h2c_byp_out_dsc` (`desc_sz=1`), matching the driver's pack layout
(`qdma_export.c`): `metadata=[31:0]`, `len=[47:32]`, `flags=[63:48]` (SOP=bit48,
EOP=bit49), `src_addr=[127:64]`. So:

```
h2c_byp_in_st_addr = h2c_byp_out_dsc[127:64];
h2c_byp_in_st_len  = h2c_byp_out_dsc[47:32];
h2c_byp_in_st_sop  = h2c_byp_out_dsc[48];
h2c_byp_in_st_eop  = h2c_byp_out_dsc[49];
h2c_byp_in_st_qid  = h2c_byp_out_qid;   // echo
h2c_byp_in_st_cidx = h2c_byp_out_cidx;  // echo
h2c_byp_in_st_no_dma = 1'b0;            // real data
```

Logic: a registered handshake bridge (`byp_out_vld & byp_in_st_rdy` → forward one
descriptor, assert `byp_out_rdy`). Start combinational + a skid buffer for timing.
**Open question O1:** confirm the `byp_out_dsc[255:0]` bit layout against PG302 (the
RTL carries no in-tree doc) — validate in sim before trusting the offsets above.

## 12.6 Step 2 — fix the tkeep source (the real subtlety)

Today `qdma_subsystem_function.sv:366-370` builds the last-beat `tkeep` from
`tuser_size[5:0]` = descriptor `metadata[15:0]`, and `qdma_subsystem_h2c.sv:74,101`
force the IP's own `tkeep` to all-ones. In bypass mode **`byp_in` has no metadata
field**, so that packet-length sideband is no longer populated per-packet. Two ways to
get a correct last-beat `tkeep`:

- **(a) Use the IP's native `m_axis_h2c_tkeep`.** The engine knows the true byte count
  (sum of per-descriptor `len`) and drives a correct `tkeep`/`tlast`. Stop forcing
  `tkeep=all-ones` in `qdma_subsystem_h2c.sv` and stop regenerating it in
  `qdma_subsystem_function.sv`; pass the IP's `tkeep` straight through. Cleanest.
- **(b) Use `axi_stream_size_counter`.** The counter already exists in
  `qdma_subsystem_h2c.sv` (feeds `h2c_status_bytes`); repurpose it to trim the last
  beat. More work than (a).

Recommend (a). **Open question O2:** verify the QDMA IP asserts a correct per-beat
`tkeep` on H2C ST in bypass mode (it should — this is standard AXIS). This is the item
most likely to need sim + a scope on hardware.

## 12.7 Step 3 — driver

1. `onic_qdma_init_tx_queue()` (`onic_hardware.c`): `sw_ctxt.bypass = 1;` (H2C only;
   `memset` currently leaves it 0). Keep `desc_sz = 1`.
2. `onic_xmit_frame`: keep the committed multi-descriptor build; set `pld_len = len`
   per fragment (mirror libqdma `descq_proc_st_h2c_request`) so the descriptor matches
   the bypass convention. PTP tag path stays on the EOP descriptor.
3. `onic_apply_netdev_features`: re-advertise `NETIF_F_SG` (features + hw_features).
4. `onic_tx_clean` already frees the skb only from the EOP slot — no change.

## 12.8 Verification

1. **Loopback (§12.4):** linear iperf3 unchanged (~9.4 Gbit/s, 0 retr) with
   `bypass=1`, SG off. Gate: no regression.
2. **SG on, correctness:** iperf3 completes (was the failure signal); large TCP TX;
   peer `tcpdump` shows fragmented frames arriving full-length (no `truncated-ip`), no
   FCS/CRC errors; driver `tx_dropped`/`tx_errors` = 0.
3. **On-wire size:** the 2-descriptor frame (66 B head + 124 B frag) now arrives as
   190 B with real payload (was 126 B garbage). CMAC `stat_tx_pkt_128_255_bytes`
   increments, not `_65_127`.
4. **Fallback:** `ethtool -K enp1s0 sg off` still linearizes cleanly.
5. **PTP + qid steering + RSS** regression pass (they share the H2C tuser path).

Bench: QSFP0 (`.223` `enp1s0`) ↔ ConnectX-6 (`.180` `enp1s0np0`), private
`192.168.199.0/24` link (avoids the corporate `10.42.0.0/24` collision); iperf3 at
`/home/alex/mpi-shfs/fpga/iperf/src/iperf3` on `.180`.

## 12.9 Alternative — AXI-ST coalescing shim (fallback only)

If bypass proves intractable (e.g. O1/O2 don't resolve), a shim on the H2C AXI-ST
output could merge consecutive internal-mode per-descriptor packets into one, using a
driver-provided "fragment count / is-EOP" hint in the metadata sideband. Lower blast
radius (single-descriptor packets pass untouched) but non-standard, needs the
side-channel, and assumes no cross-packet interleaving. Not recommended unless bypass
is blocked.

## 12.10 Risks & open questions

- **O1** — `h2c_byp_out_dsc[255:0]` exact bit layout (no in-tree doc; use PG302 + sim).
- **O2** — IP-native `tkeep` correctness on H2C ST bypass (§12.6a).
- **Blast radius** — all H2C TX flows through the new module; §12.4 mitigates.
- **Timing** — new logic in the QDMA clock domain; budget a `phys_opt` pass.
- **cidx/completion** — the writeback/`cidx` accounting must stay correct through the
  bypass loop; confirm `onic_tx_clean` still sees monotonic `cidx`.
- **Two IP instances** — apply identical wiring to both `qdma_no_sriov` and
  `qdma_no_sriov_1` branches (`qdma_subsystem_qdma_wrapper.v`).

## 12.11 Effort

| Piece | Effort |
|-------|--------|
| §12.4 loopback bring-up (RTL + build + test) | M (incl. ~3–5 h rebuild) |
| §12.5 bypass module (fragment framing) | S–M (small RTL, sim-heavy) |
| §12.6 tkeep source change + verify | M (the risky part) |
| §12.7 driver | S (≈3 lines + re-advertise) |
| §12.8 verification | M |

**Overall ≈ M–L**, dominated by RTL bring-up/verification and two full FPGA rebuilds
(loopback, then SG). The payoff is CPU savings (linear TX is already PCIe-bound here),
so the stronger justification is that this bypass datapath is the **prerequisite for
TX checksum offload / TSO** (Ch. 10 §1.2, §2.2), which need the same user-controlled
H2C path.

## 12.12 Phased execution with go/no-go gates (loopback-first)

The organizing principle: **keep linear TX as the invariant under test** and only flip
one variable per phase, so any regression bisects to a single change. SG stays OFF
until the datapath is proven end-to-end. The bypass module (§12.13) is the *same* in
every phase — it already forwards per-descriptor SOP/EOP/len, so no extra RTL is needed
to "add framing"; de-risking is about *enabling* incrementally, not writing more logic.

### Phase A — bypass datapath bring-up (loopback, SG OFF)  ·  RTL + rebuild
- Shell: add `qdma_subsystem_h2c_byp` (§12.13), replace the tie-off at
  `qdma_subsystem.sv:307-320` with an instance, wire to both IP branches.
- Driver: `sw_ctxt.bypass = 1` in `onic_qdma_init_tx_queue`; **`NETIF_F_SG` still off**
  (traffic stays single-descriptor, SOP+EOP both set — a pure passthrough).
- **GATE A** (all must hold):
  1. Linear `iperf3` ≈ 9.4 Gbit/s, 0 retr — *unchanged*.
  2. **Sustained** (ring wraps many times) — proves the `sdi`→writeback→`cidx` loop
     works and `onic_tx_clean` reclaims. If TX stalls after ~one ring, the `sdi`/wb
     handshake is wrong (§12.13 note) — fix before Phase B.
  3. `ping`/jumbo clean; `tx_dropped`/`tx_errors` = 0.
- **No-go rollback:** driver `sw_ctxt.bypass = 0` reverts to internal mode instantly
  (no reflash) — the RTL module is inert when the queue context is internal.

### Phase B — `tkeep` from IP-native (SG OFF)  ·  RTL + rebuild
- Shell: stop forcing `tkeep=all-ones` in `qdma_subsystem_h2c.sv:74,101`; pass the IP's
  `m_axis_h2c_tkeep` through; remove/gate the metadata-based regen in
  `qdma_subsystem_function.sv:366-370` (§12.6a).
- **GATE B:** linear TX still **byte-exact** — the last-beat trim now comes from the IP.
  Verify with non-64-multiple frames (e.g. 1514 B → last beat 42 B): peer `tcpdump`
  shows exact lengths, no oversize/short frames, FCS clean. This isolates the `tkeep`
  swap from SG.
- **No-go rollback:** revert the two RTL hunks (reflash) — Phase A stays intact.

> **Rebuild economy:** A and B can share one bitstream if you accept coarser
> bisection. Recommended split: **Phase A alone first** (isolates the riskiest item —
> does bypass + writeback work at all), then **B+C together** (B is RTL, C is
> driver-only). That's 2 rebuilds, riskiest change isolated.

### Phase C — enable SG (driver only, NO rebuild)
- Driver: advertise `NETIF_F_SG`; set `pld_len = len` per fragment; keep the committed
  multi-descriptor build. Reload the module (the Phase-B bitstream already frames).
- **GATE C** (the SG acceptance test):
  1. `iperf3` **completes** (was the failure signal) at line rate, low retr.
  2. Peer `tcpdump`: the 2-descriptor frame arrives full-length (190 B, real payload),
     no `truncated-ip`, no CRC errors; CMAC `stat_tx_pkt_128_255_bytes` increments.
  3. Multi-flow + jumbo; `tx_errors`/`tx_dropped` = 0.
  4. `ethtool -K enp1s0 sg off` fallback still linearizes cleanly.
  5. Regression: PTP TX timestamp, qid-steering, per-port RSS (shared H2C tuser path).
- **No-go rollback:** `ethtool -K sg off` (runtime) or drop the `NETIF_F_SG` advertise
  (reload) — bitstream unaffected.

## 12.13 Draft — `qdma_subsystem_h2c_byp` (Phase-0 module, turnkey)

Pure handshake passthrough; decodes the 16 B H2C-ST descriptor from the low 128 bits of
`h2c_byp_out_dsc`. Add a skid buffer only if it misses timing. This module is the whole
RTL datapath — Phases A/B/C reuse it unchanged.

```systemverilog
// qdma_subsystem_h2c_byp.sv — H2C descriptor-bypass passthrough (Phase 0+).
// dsc[127:0] = metadata[31:0] | len[47:32] | flags[63:48] | src_addr[127:64]
// flags: SOP=bit48, EOP=bit49 (S_H2C_DESC_F_SOP/_EOP). Confirm vs PG302 (O1).
module qdma_subsystem_h2c_byp (
  // from IP: descriptor-bypass-out
  input             h2c_byp_out_vld,
  input     [255:0] h2c_byp_out_dsc,
  input      [10:0] h2c_byp_out_qid,
  input      [15:0] h2c_byp_out_cidx,
  input       [7:0] h2c_byp_out_func,
  input       [2:0] h2c_byp_out_port_id,
  input             h2c_byp_out_error,
  output            h2c_byp_out_rdy,
  // to IP: descriptor-bypass-in (ST)
  output            h2c_byp_in_st_vld,
  output     [63:0] h2c_byp_in_st_addr,
  output     [15:0] h2c_byp_in_st_len,
  output            h2c_byp_in_st_sop,
  output            h2c_byp_in_st_eop,
  output     [10:0] h2c_byp_in_st_qid,
  output     [15:0] h2c_byp_in_st_cidx,
  output      [7:0] h2c_byp_in_st_func,
  output      [2:0] h2c_byp_in_st_port_id,
  output            h2c_byp_in_st_sdi,
  output            h2c_byp_in_st_mrkr_req,
  output            h2c_byp_in_st_no_dma,
  output            h2c_byp_in_st_error,
  input             h2c_byp_in_st_rdy
);
  // 1:1 handshake: forward when the IP has a descriptor and can accept one back.
  assign h2c_byp_in_st_vld      = h2c_byp_out_vld;
  assign h2c_byp_out_rdy        = h2c_byp_in_st_rdy;

  assign h2c_byp_in_st_addr     = h2c_byp_out_dsc[127:64];
  assign h2c_byp_in_st_len      = h2c_byp_out_dsc[47:32];
  assign h2c_byp_in_st_sop      = h2c_byp_out_dsc[48];
  assign h2c_byp_in_st_eop      = h2c_byp_out_dsc[49];
  assign h2c_byp_in_st_qid      = h2c_byp_out_qid;
  assign h2c_byp_in_st_cidx     = h2c_byp_out_cidx;
  assign h2c_byp_in_st_func     = h2c_byp_out_func;
  assign h2c_byp_in_st_port_id  = h2c_byp_out_port_id;
  assign h2c_byp_in_st_error    = h2c_byp_out_error;
  assign h2c_byp_in_st_no_dma   = 1'b0;   // real data fragment
  assign h2c_byp_in_st_mrkr_req = 1'b0;
  // Request status writeback at packet end so the H2C wb-ring cidx advances and
  // onic_tx_clean reclaims descriptors. THE Phase-A gate item: if linear TX stalls
  // after the ring fills once, this sdi/writeback assumption is wrong.
  assign h2c_byp_in_st_sdi      = h2c_byp_out_dsc[49];  // = EOP
endmodule
```

Instantiate in `qdma_subsystem.sv` in place of lines 307-320, connecting the existing
`h2c_byp_out_*` / `h2c_byp_in_st_*` wires (already routed to both `qdma_no_sriov`
instances). Tie the handful of `byp_in` fields the module omits (`_error` if unused,
etc.) to 0 at the instantiation if not driven.

## 12.14 Phase A execution result (2026-07-15) — PARKED at integration blocker

Phase A was built and run on hardware **twice**; both failed **Gate A**. The board
(au200 on `.223`) is shared with Tenstorrent's RoCEv2 project (flash `1e52:4001`,
`rocev2` driver) — flashing the eth bitstream over it crashed `rocev2` once and needed
a host reboot; testing was done via volatile `.bit` (JTAG from the build host) so a
power-cycle restores the RoCEv2 design.

**Both builds:** timing met, `qdma_subsystem_h2c_byp` synthesized in, driver bound in
bypass mode (`h2c_bypass=1` module param), netdevs up, SG off.

**A/B isolation (same bitstream, `h2c_bypass` toggled):**

| | internal (`=0`) | bypass (`=1`) |
|---|---|---|
| TCP iperf3 | **9.36 Gbit/s, 0 retr** | 0 bytes |
| UDP 3G blast → peer RX | 100 % delivered | **16 / 1.5M (~0 %)** |
| backpressure | normal | **none** (sender full rate) |

- **Iter 1** (naive combinational passthrough): failed as above.
- **Iter 2** (byp module made byte-identical to Xilinx `dsc_byp_h2c.sv` ST path —
  added `~fmt[0] & ~st_mm` gating on `byp_in_st_vld`, marker-response `rdy=1`):
  **identical failure.**

**Conclusion — root cause is NOT the byp module logic** (it matches Xilinx's reference
exactly and still fails), **it is QDMA bypass integration.** Signature: full send rate,
no backpressure, ring `cidx` advancing, ~0 on the wire ⇒ `cidx` advances on descriptor
**fetch** (`byp_out`) while the `byp_in` submission never actually DMAs/transmits.
`sw_ctxt.bypass=1` routes descriptors *out*, but the bypass *datapath* needs more that
OpenNIC (which never used bypass) doesn't set up — most likely a **global
descriptor-bypass enable** and/or a **fetch-credit/writeback** setting in the queue
context (`fcrd_en`, `wbi_*`).

**To resume (needs a dedicated card window):**
1. Offline first: study the QDMA example-design *driver/software* (same tree as
   `dsc_byp_h2c.sv`: `.../XilinxCEDStore/.../cpm5_qdma*/`) for how it configures a
   descriptor-bypass H2C ST queue — global enable, `fcrd_en`, writeback/credit — and
   check PG302's descriptor-bypass queue-setup requirements.
2. Add an **ILA** on `byp_out_*`/`byp_in_st_*` (+ CMAC tx handshake) to capture, on
   hardware, whether `byp_in` DMA fires and where the `cidx`/transmission decouple.
3. Only then iterate the driver `qdma_sw_ctxt`/global-enable + one rebuild.

**Do NOT** resume by flashing the shared RoCEv2 card without coordination.

**WIP artifacts (uncommitted):** shell `src/qdma_subsystem/qdma_subsystem_h2c_byp.sv`
+ the tie-off replacement in `qdma_subsystem.sv`; driver `h2c_bypass` module param +
`sw_ctxt.bypass` in `onic_hardware.c`. Build script
`script/build_eth_1pf_2cmac_sgbyp_a.sh` (tag `eth_1pf_2cmac_sgbyp_a`).

### 12.14.1 Iteration 3 (2026-07-15, post-reboot) — driver config + register diagnosis

After a clean reboot (Phase-A eth bitstream survived, `rocev2` not auto-loaded), pursued
the QDMA-bypass *configuration* hypothesis (research vs Xilinx `dma_ip_drivers`):

- **IP capability confirmed OK, rules out regen.** `GLBL2_MISC_CAP @ 0x134` reads
  `0x01200000` → bits[3:2]=`00` = `INTERNAL_BYPASS`. The IP *does* support descriptor
  bypass (matches the `dsc_byp_mode {Descriptor_bypass_and_internal}` IP config). So
  `sw_ctxt.bypass=1` is a valid request; no IP regen needed. (pcimem read validated:
  0x134 reads back correctly.)
- **`fetch_max=7` did NOT fix it.** The reference sets `fetch_max=FETCH_MAX_NUM(7)` for
  every non-64B ST queue (OpenNIC left it 0). Added it for bypass queues → bypass still
  delivers ~0 (peer RX 18/1.3M), TCP 0 bytes.
- **Behavioural localization:** descriptors are submitted at full rate, ring `cidx`
  advances (no backpressure), yet the H2C DMA/transmit engine appears to process none —
  i.e. the `byp_out→byp_in` loop is not delivering descriptors to the DMA engine, even
  though the byp module is byte-identical to Xilinx `dsc_byp_h2c.sv` and the queue context
  now matches the reference (`bypass=1`, `fetch_max=7`, `mrkr_dis=0`, `desc_sz=16B`).
- **H2C debug registers (`0xE0C/0xE10/...`) read 0** but could not be validated (the
  QSFP0↔peer link went flaky during the churn, so no confirmed-working control read was
  possible; treat these counters as unconfirmed offsets for this IP version).

**Conclusion:** the blocker is at the QDMA descriptor-bypass *integration* boundary and
is **not** resolvable by more register poking or blind rebuilds. Definitive next step is
an **ILA** on `h2c_byp_out_*`/`h2c_byp_in_st_*` (+ CMAC tx) to see whether `byp_out_vld`
asserts, whether the module forwards, and whether `byp_in` is accepted — on a
**dedicated card with a stable link**. Given reference-correct logic + confirmed IP
capability, a Xilinx QDMA support question is warranted in parallel.

**Driver-side config now matched to the reference (WIP):** `sw_ctxt.bypass` +
`sw_ctxt.fetch_max=7` in `onic_hardware.c` (both gated on the `h2c_bypass` module param).
Register-read method for resume: QDMA CSRs are BAR0 (`resource0`); `pcimem <resource0>
<off> w`; key offsets `0x134` (cap), `0xE00` (H2C err), `0xE0C-0xE1C` (H2C dbg), `0x248`
`0x254` (glbl err).

### 12.14.2 Dead-ends confirmed (so the resumer doesn't repeat them)

- **H2C debug registers `0xE0C/0xE10/0xE14` are the WRONG offsets for this IP** — they
  read `0x00000000` even during a confirmed-working 9.23 Gbit/s internal-mode transfer.
  Register-level localization needs the correct IP register map (or an ILA). Only
  `0x134` (GLBL2_MISC_CAP) is confirmed valid.
- **No in-house QDMA descriptor-bypass reference exists.** Checked RecoNIC
  (`../RecoNIC/base_nics/open-nic-shell`) and the Tenstorrent rocev2 design/driver
  (`../rocev2-rtl-vivado`) — neither drives the QDMA `byp_in`/`byp_out` interface; both
  run the QDMA in internal mode. So there is no local working example to diff against;
  the only reference is Xilinx's `dsc_byp_h2c.sv` + the QDMA example *design's* driver
  software. **Correction (§12.14.3):** the `dsc_byp_h2c.sv` that was "matched" is the
  **CPM5 (Versal)** variant — the wrong IP family for this soft-`qdma_v5_1` U200 design;
  the correct soft-IP reference is the (encrypted) `qdma_v5_1` example design.
- **`fetch_max`/`frcd_en` are fetch-side knobs** and don't address a `byp_in`→DMA
  delivery failure (the fetch side works — `cidx` advances).

**~~Genuinely remaining path:~~** ILA on `h2c_byp_out_*`/`h2c_byp_in_st_*` (dedicated card,
stable link) and/or a **Xilinx QDMA support case** — the situation (IP bypass-capable,
queue context + byp RTL both reference-correct, yet `byp_in` doesn't deliver) is exactly
a vendor-integration question. Not resolvable by further offline/register work here.

> **Superseded by §12.14.3.** The "byp RTL is reference-correct" premise was false —
> it was matched against the wrong IP family. Try the offline RTL fix first.

### 12.14.3 Offline re-investigation (2026-07-15) — wrong-IP reference + dropped marker loopback

A fresh offline audit (no card) of the full driver↔RTL↔IP path found that the Phase-A
premise "byp RTL is reference-correct" is **wrong**, which reopens an offline fix path
that predates any ILA/vendor step.

**What is confirmed CORRECT (so stop re-checking these):**
- **Driver `sw_ctxt.bypass` lands on the right bit.** The deployed encoder is the
  homegrown `open-nic-driver/qdma_legacy/qdma_context.c` (not the vendored libqdma).
  Its `QDMA_SW_CTXT_W1_BYPASS_MASK = BIT(18)` matches EQDMA v5's
  `SW_IND_CTXT_DATA_W1_BYPASS_MASK = BIT(18)` exactly; MRKR_DIS `BIT(30)` and FCRD_EN
  `BIT(1)` also match. Only `fetch_max` width differs (legacy `GENMASK(7,5)` 3-bit vs
  EQDMA `GENMASK(8,5)` 4-bit) — **benign for value 7**. So bypass is validly requested.
- **Descriptor packing ↔ RTL extraction are self-consistent.** Driver packs (in
  `qdma_export.c`, masks in `qdma_export.h`): metadata `[31:0]`, len `[47:32]`, flags
  `[63:48]` (SOP=`BIT(0)`→bit48, EOP=`BIT(1)`→bit49), src_addr `[127:64]`. The byp
  module reads `len=dsc[47:32]`, `sop=dsc[48]`, `eop=dsc[49]`, `addr=dsc[127:64]` —
  matches, and matches the EQDMA5 layout that works in internal mode.
- **IP is generated for bypass.** `vivado_ip/qdma_no_sriov_au200.tcl:25`
  `dsc_byp_mode {Descriptor_bypass_and_internal}`, ST-only
  (`AXI_Stream_with_Completion`, `en_axi_mm false`).
- **Wiring IP↔module is intact both directions** (`qdma_subsystem.sv:310-335`,
  `:412-437`).

**What is WRONG (the actual leads):**
1. **The byp module was copied from the wrong IP family.** Reference used was
   `cpm5_qdma/src/dsc_byp_h2c.sv` = **Versal CPM5 hardened** QDMA. The U200 (`xcu200`,
   Virtex UltraScale+) uses the **soft `qdma_v5_1` (EQDMA soft)** IP. Proof they differ:
   the CPM5 reference declares `fmt[2:0]` (marker=`3'b1`), `qid[11:0]`, `func[11:0]`;
   our soft-IP wires are `fmt[3:0]` (module checks `4'h1`), `qid[10:0]`, `func[7:0]`.
   The correct reference — `/opt/amd/2025.2/data/ip/xilinx/qdma_v5_1/ttcl/`
   `dsc_byp_h2c_sv.ttcl` — is **encrypted**, so it was never actually diffed. The
   `fmt`/`st_mm` decode that gates `h2c_byp_in_st_vld` may be wrong for the soft IP,
   which is exactly the failure point (descriptor consumed → `cidx` advances via
   `byp_out_rdy`, but `byp_in` never fires → 0 bytes, no backpressure).
2. **The module dropped the marker loopback.** The reference does
   `h2c_byp_in_st_mrkr_req = h2c_st_marker_req` and drives `h2c_st_marker_rsp` back to
   the IP; `qdma_subsystem_h2c_byp.sv:80` hardwires `h2c_byp_in_st_mrkr_req = 1'b0` and
   just swallows `fmt==1` with `rdy=1`. The **soft IP's bypass interface defines
   `mrkr_req`/`mrkr_rsp`** (`/opt/amd/2025.2/data/ip/interfaces/qdma_dsc_byp_v1_0/`),
   so these are real ports on our IP that are currently unserviced. "Byte-identical to
   reference" held for the ST *datapath fields* only — it missed the marker ports.

**On "just use libqdma as a submodule":** the deployed driver deliberately uses the
homegrown `qdma_legacy` (minimal, netdev-shaped) rather than the full libqdma framework
(char-dev/ioctl/own-threading — a rearchitecture to embed). We *do* vendor libqdma
twice (`onic-driver/libqdma/`, `../dma_ip_drivers/QDMA/linux-kernel/`) — so the move is
to **mirror libqdma's bypass queue-setup sequence** into the homegrown path, not adopt
it wholesale. Extracted sequence (from `dma_ip_drivers .../libqdma/qdma_context.c`
`make_sw_context()` + start path): for a 16B bypass H2C ST queue set `bypass=1`,
`fetch_max=7`, `frcd_en=fetch_credit`, `mrkr_dis=0`, `qen=1`, `is_mm=0`, plus
per-function **FMAP (qbase/qmax)** and global **`GLBL_DSC_CFG.MAX_DSC_FETCH`**. Note:
H2C ST needs **no prefetch/credit context** (those are C2H-only) — so `onic_hardware.c`
clearing hw/cr and skipping prefetch is correct. But **a driver fix alone cannot fix an
RTL byp module that speaks the wrong IP's dialect** — do the RTL fix too.

**Revised resume plan (offline first, only then card):**
1. **Vivado `open_example_project`** on the soft `qdma_v5_1` IP → extract the plaintext,
   correct-IP `dsc_byp_h2c.sv` (EQDMA soft). Diff `fmt`/`st_mm` decode and descriptor
   bit layout against `qdma_subsystem_h2c_byp.sv`.
2. **Rebuild the byp module against the soft-IP reference** — correct `fmt`/`st_mm`
   gating, and **restore the marker loopback** (wire `mrkr_req`/`mrkr_rsp` to the IP's
   top-level `h2c_st_marker_req`/`_rsp` — currently absent from `qdma_subsystem.sv`).
3. **Mirror libqdma's bypass queue setup** in `onic_hardware.c` (FMAP + `GLBL_DSC_CFG`
   in particular — verify OpenNIC programs them; these are the likeliest driver gaps).
4. One rebuild → retest on a dedicated card. ILA / vendor case only if this still fails.
