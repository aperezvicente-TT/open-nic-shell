# RDMA Production Full-Stack Plan

Written 2026-04-23.  Major rescope: replaces the earlier P1–P7
"general-purpose RoCE NIC" plan.  Same anchor document, new target.

> **Executive summary.**  ERNIC v4.2 (and editorially identical v4.3)
> cannot serve as a general-purpose RoCE NIC — a PG332 audit
> confirmed hard caps (single MR per QP, one-shot CC, no atomics/UD
> beyond MAD/SRQ/XRC, ~256 QPs) that foreclose standard workloads
> like NCCL/UCX/NVMe-oF.  The project is therefore rescoped into
> three near-term tracks built on a shared ERNIC control-plane
> foundation (B: restricted Linux RoCE NIC, C: RoCE gateway for
> external hosts talking to TT chips, D: TT↔TT RoCE transport),
> with a deferred future track A that either wraps ERNIC in a RoCE
> pre/post-processor or swaps the IP entirely.  Track A is not
> currently staffed or scheduled; B/C/D stand on their own.

Complements — does **not** supersede — `dual_netdev_plan.md`
(current Ethernet-side architecture).  Supersedes the P1–P7 phase
plan that previously occupied this file.

Sibling project: the UDP-based **tt-link gateway**
(`/home/alex/alex-notes/tenstorrent/fpga-erisc/status/tt-link-gateway-proposal/`)
handles the primary Tenstorrent external-data-movement path over
UDP, not RoCE.  The tt-link plan §7 explicitly notes that
"RoCEv2 coexistence via rdma_onic on a second CMAC port is a
separate engagement" — i.e. this document.  Scope here is RoCE
only; do not conflate.

---

## 1. Scope and non-goals

### 1.1 What this plan IS

A multi-flavor RoCEv2 product built on the dual-ERNIC OpenNIC
bitstream currently running.  Three near-term tracks (B, C, D)
share a single ERNIC control-plane foundation inside `onic.ko` and
fork on personality:

- **Track B** — Linux `ib_device` in `onic.ko` exposing a
  **restricted** ibverbs surface.  Applications whose usage stays
  inside ERNIC v4.2's capability envelope work.  Applications
  outside it fail fast with a clear `-EOPNOTSUPP` path.
- **Track C** — RoCE termination gateway: external ConnectX-class
  hosts speak standard RoCEv2 to the FPGA; the FPGA terminates
  RoCE and forwards payloads to Tenstorrent silicon over a
  backend fabric (TBD; see §4).
- **Track D** — TT↔TT RoCE over FPGA: two FPGAs, one per TT
  endpoint, with QP/MR pairing pre-arranged by a TT orchestrator.
  Endpoints are fully controlled, so ERNIC limits are irrelevant.

### 1.2 What this plan is NOT

- **Not a ConnectX replacement.**  Track B is explicit: we do not
  advertise an unrestricted ibverbs surface.  We do not support
  NCCL, UCX, NVMe-oF kernel client, libfabric (except a curated
  subset), or any application performing dynamic `ibv_reg_mr()`
  against a single QP at line rate.
- **Not a general-purpose shared-fabric RoCE NIC.**  ERNIC v4.2
  has no rate-recovery CC state machine.  Initial deployments
  require lossless PFC fabrics or tightly-scoped point-to-point
  links.
- **Not a research artifact either.**  Tracks B/C/D each have
  real product targets and acceptance gates.

### 1.3 Non-goals

- Upstreaming a general-purpose `onic_ib` driver to `linux-rdma`.
  Restricted ibverbs drivers are not upstreamable.  (A future
  Track A success might change this; not now.)
- DCQCN.  ERNIC's one-shot CC is not DCQCN and we will not pretend
  it is.  Fabrics must be engineered around this.
- Replacing the tt-link UDP gateway.  That's the primary TT
  external-data path.  RoCE work here is additive.

---

## 2. Architectural reality check — ERNIC v4.2 audit

Full receipts: `pg332_v4_2_production_audit.md` and the
v4.2↔v4.3 comparison at
`/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/cmac-us/pg332-ernic-4.{2,3}.md`.
v4.3 is **editorially identical** to v4.2 in every restriction
that matters — there is no upgrade path by waiting.

Key restrictions, receipts, and blast radius:

| Limit | PG332 source | What it breaks |
|---|---|---|
| **One MR per QP** | Register 0x18_00B0 note: *"Only one memory region can be associated per QP"* | NCCL (multi-buffer transfer engines), UCX, NVMe-oF, any dynamic `ibv_reg_mr()` workflow, libfabric's standard providers, kernel ULPs |
| **One-shot CC** | RX Path: on first ECN mark, 16→8 outstanding; further CNPs ignored; no rate recovery | No DCQCN.  No RP/NP state.  No congestion response in shared fabric. |
| **No atomics** | PG332 opcode table (verify during B1) | Distributed locking / shared-counter patterns |
| **No UD** beyond QP1/MAD | PG332 QP-type table | Multicast, SRP, anything UD-based |
| **No SRQ, no XRC** | Absent from PG332 | Shared receive queues, extended reliable connect |
| **RC only** | PG332 QP-type table | UC-mode apps |
| **~256 QPs** | Compile-time parameter (up to 2048 in theory; 256 in current build) | Cloud-scale fanout |

#### Capability → viable track matrix

| Capability needed | Track B | Track C | Track D | Track A (gated) |
|---|:-:|:-:|:-:|:-:|
| Multiple MRs per QP | NO | n/a (gateway picks one staging MR) | NO (orchestrator handles) | goal of A |
| Real DCQCN | NO | NO | NO (dedicated fabric) | goal of A |
| Atomics | NO | NO | NO | goal of A |
| UD / multicast | NO | NO | NO | possibly |
| SRQ/XRC | NO | NO | NO | possibly |
| >256 QPs | NO | NO (small client set) | NO (pairwise) | goal of A |

Tracks B/C/D are viable *because* each either lives in a
controlled environment or advertises its restrictions up front.

---

## 3. Shared foundation (used by B, C, and D)

Every personality shares the same ERNIC control-plane bring-up.
Build this once.

- **ERNIC QP/MR/CQ setup library (in-kernel).**  Refactor of the
  existing Phase 1/1b regression code into `onic_ernic.c` —
  driver-owned helpers that program PDT entries, QP conf tables,
  CQ base addresses, and rkey/lkey assignment.  Same code path
  used by B's verb ops, C's gateway firmware control plane, and
  D's orchestrator RPC handler.
- **DDR4 MR management.**  DDR4 crossbar at `0xa350_0000` stays
  as-is.  Kernel-side allocator carves `[base, base+size)` slabs
  for per-QP staging MRs (Track C especially) and for Track D
  pre-pinned buffers.  64-bit address latching already validated
  (Phase 1b).
- **CSR path.**  BAR2 @ 16 MB with ERNIC0 at offset 0x800000 and
  ERNIC1 at 0xA00000.  Already in production.
- **Interrupt routing.**  `int_rdma0/1` single-line interrupts
  into shell IRQ mux.  Driver reads `CQINTSTS1-64` on interrupt
  to find which CQs have pending completions.  No shell RTL
  change needed (confirmed by audit §4.5).
- **Dual-netdev coexistence.**  `onic.ko` keeps both CMAC netdevs
  for Ethernet-side traffic and non-RoCE control.  RoCE frames
  branch to ERNIC via the CMAC RX classifier (existing plugin
  `rdma_onic_250mhz.sv`).

#### Shared phases

| Phase | Scope | Gate |
|---|---|---|
| **S0** | Port Phase 1/1b regressions into `onic_ernic.c` kernel helpers; same CSR coverage but callable from driver | Existing regression results reproduced from kernel on both ERNICs |
| **S1** | DDR4 MR slab allocator + rkey/lkey assignment | 1k slab alloc/free, no leak, correct key round-trip |
| **S2** | Basic QP lifecycle (RESET → INIT → RTR → RTS → ERR → RESET) exercised via debugfs, no wire traffic | Loop 1k cycles, no stuck QPs, INTSTS drained cleanly |
| **S3** | End-to-end wire test: two FPGAs cabled back-to-back, RC RDMA WRITE via debugfs, DDR4 → DDR4 | Data arrives; CQEs delivered; used as regression going forward |

Expected duration: ~1 month for S0–S3, single engineer.  Tracks
B/C/D can only proceed after S3 passes.

---

## 4. Track B — Restricted Linux RoCE NIC

### 4.1 Goals

- Linux `ib_device` registered inside `onic.ko`, discoverable via
  `rdma link show` / `ibv_devinfo`.
- A curated subset of ibverbs works correctly.  Everything else
  fails with a specific, documented error.
- Standard OFED tooling (`ib_write_bw`, `ib_read_bw`,
  `ibv_rc_pingpong`) works **within the subset**.
- Zero kernel oops / stuck-QP under the failure paths of apps
  that hit unsupported verbs.

### 4.2 User stories

**Works:**

- App creates 1 PD, 1 MR (≤256 TB), 1 QP (RC), 1 CQ.  Issues
  `ib_write_bw` between two FPGAs.  Sustained large-MTU flow.
- App creates N≤128 QPs each with its own single MR.  Long-lived
  RPC-style traffic with bounded connection set.
- `rping`, `ibv_rc_pingpong`, `ib_write_bw`, `ib_read_bw` with
  point-to-point peer.

**Fails fast (by design):**

- `ibv_reg_mr()` called twice on the same PD with both MRs used
  by a single QP → second MR rejected with diagnostic log line
  pointing at single-MR-per-QP restriction.
- `ibv_post_send()` with `IBV_WR_ATOMIC_*` → `-EOPNOTSUPP`.
- `ibv_create_qp` with `qp_type = IBV_QPT_UD` (non-MAD) →
  `-EOPNOTSUPP`.
- `ibv_create_srq`, XRC variants → `-EOPNOTSUPP`.
- NCCL / UCX init → fails verb negotiation; documented.

### 4.3 Design notes

- One `ib_device` with `phys_port_cnt = 2` (matches existing
  dual-CMAC; mlx5 pattern).  Decision carried forward from the
  earlier plan — still correct.
- `query_device`: advertise `max_qp=256`, `max_mr=2048`,
  `max_qp_wr=` from PG332, **no atomic caps set**, no UD
  capability for user QPs, no SRQ.  Application-visible caps
  reflect reality.
- QP numbering: ERNIC0 uses `qp_num 0..255`, ERNIC1 uses
  `256..511`; driver-side table translates.
- MR registration: one-shot per QP bind.  Driver tracks
  (QP → MR) binding and rejects rebinding attempts with a clear
  error.
- Userspace provider: check `rdma-core/providers/` for Xilinx
  upstream support.  If absent, ship a minimal out-of-tree
  provider that maps SQ/CQ rings.  Do not submit upstream.

### 4.4 Phases

| Phase | Scope | Gate |
|---|---|---|
| **B0** | `ib_device` skeleton, stubs return `-EOPNOTSUPP`, `query_device`/`query_port` return honest caps | `ibv_devinfo -v` shows both ports with restricted caps; no crashes |
| **B1** | `alloc_pd`, `reg_mr`, `dereg_mr`, `create_cq`, `destroy_cq` | Allocate 100 of each; verify rkey/lkey values; dereg-while-in-use rejected |
| **B2** | `create_qp`, `modify_qp` (to RTS), `destroy_qp` | RC QP to RTS with remote FPGA peer |
| **B3** | `post_send` (WRITE/READ/SEND), `post_recv`, `poll_cq`; interrupt-driven CQ delivery | `ibv_rc_pingpong` works between two FPGAs |
| **B4** | Error paths: QP-fatal recovery, CQ-full detection, `dereg_mr` synchronization, reject unsupported verbs cleanly | Induced-error stress run — no kernel oops, no stuck QP |
| **B5** | Interop with Mellanox ConnectX peer (within subset) | `ib_write_bw` FPGA ↔ CX6 hits ≥40 Gbps; no spec-compliance failures in tcpdump |

### 4.5 Acceptance gates

- All B0–B5 gates green.
- 4-hour soak `ib_write_bw` on PFC-lossless fabric, zero errors.
- Documented capability sheet lists every verb and its status
  (supported / restricted / unsupported).

---

## 5. Track C — RoCE gateway for external hosts

### 5.1 Goals

External hosts keep their ConnectX NICs and their unmodified
ibverbs applications.  FPGA **terminates** the RoCE protocol and
forwards payloads to Tenstorrent silicon via a backend fabric.
No ibverbs on the FPGA side — the FPGA runs gateway firmware
(driver + embedded logic), not an `ib_device`.

The single-MR-per-QP limitation is natural here: each external
client QP has one staging MR in DDR4 that the gateway forwards
from/to the backend.

### 5.2 Architecture

```
  external host(s)                 FPGA (this project)              TT silicon
  ---------------                  ---------------------            -----------
  ConnectX NIC                     ERNIC                            TT endpoint
       |                             |                                   |
       |   RoCEv2 over 100GbE        |       backend fabric              |
       +------ CMAC0/1 --------------+------ (TBD, likely Ethernet) -----+
              RoCEv2 terminated       payload forwarded
              in ERNIC                from DDR4 staging MR
```

- RoCE termination: ERNIC receives RC/WRITE/READ/SEND from client
  QPs into DDR4 staging MR (one per client QP).
- Gateway firmware (onic.ko + userspace control daemon) peeks
  completion notifications, reads headers, forwards payload over
  backend fabric.
- Backend fabric: **TBD — depends on Tenstorrent integration
  decision.**  "Not PCIe" per project context; most likely
  Ethernet on a second CMAC port or on a QSFP side channel.
  Spec needed from TT integration team before C2 can start.

### 5.3 Phases

| Phase | Scope | Gate |
|---|---|---|
| **C0** | Gateway control daemon skeleton in userspace + `onic.ko` helpers; connects to shared-foundation QP/MR/CQ APIs | Daemon starts, opens ERNIC QP context, no wire traffic |
| **C1** | Single-client RC termination: external ConnectX host establishes QP with FPGA, issues RDMA WRITE into staging MR | Client sees successful CQE; FPGA driver sees corresponding completion |
| **C2** | **Backend fabric bring-up (TBD spec)** — payload forwarding path from staging MR → backend → TT | End-to-end payload delivered to TT silicon |
| **C3** | Multi-client scaling (16 → 128 concurrent client QPs) | Throughput + isolation gates TBD |
| **C4** | Backpressure and flow control: backend-full must stall ingress cleanly; ensure ERNIC single-shot CC doesn't cause fabric meltdown | Induced backend stall — no packet drop, clean CNP / PFC signalling |
| **C5** | Interop testing with real external hosts running real workloads (scope depends on TT product alignment) | TBD |

### 5.4 Acceptance gates

- Single-client and multi-client correctness gates pass.
- Backend fabric integration demonstrated against actual TT
  silicon interface (not a stub).
- Documented client-QP setup sequence (what external hosts must
  do).

---

## 6. Track D — TT↔TT RoCE transport

### 6.1 Goals

Two FPGAs, one attached to each Tenstorrent endpoint, transport
data between TT chips via RoCEv2 over 100 GbE.  QP/MR pairing is
**pre-arranged** by a TT orchestrator (not dynamic), so ERNIC's
static limitations are irrelevant.

### 6.2 Architecture

- Each FPGA has fixed, orchestrator-assigned QP slots paired to
  the peer FPGA's QP slots.
- MRs are pre-pinned at orchestrator time and stay resident for
  the lifetime of a session.
- No ibverbs, no userspace RDMA API.  The orchestrator drives
  setup via RPC into `onic.ko`'s shared-foundation helpers.
- Both endpoints are cooperative TT-owned infrastructure; no
  hostile workloads, no dynamic connection churn.

### 6.3 Phases

| Phase | Scope | Gate |
|---|---|---|
| **D0** | Orchestrator RPC shim in `onic.ko` exposing QP/MR setup to a TT control plane | RPC round-trip; QP reaches RTS via orchestrator-only path |
| **D1** | Pre-arranged FPGA↔FPGA RC pair: DDR4 → peer DDR4 via RDMA WRITE, orchestrator-driven | 100 GB transferred, zero data mismatch |
| **D2** | Multi-pair: N≤64 pairwise QP sessions between two FPGAs | Aggregate throughput ≥60 Gbps per CMAC |
| **D3** | Session reset / restart semantics (orchestrator tears down + rebuilds) | 1000 teardown/rebuild cycles, no leaks, no stuck QPs |
| **D4** | Integration with real TT data-path (DMA in/out of TT memory) — interface spec TBD | TBD with TT integration team |

### 6.4 Acceptance gates

- Sustained two-FPGA data movement at target throughput.
- Reset / restart robustness demonstrated.
- Interface to TT data path agreed and demonstrated (D4).

---

## 7. Track A — Deferred / future

**Status: DEFERRED.**  Not currently staffed or scheduled.  Do not
start any A-phase work without an explicit decision to pick up
the track (fresh IP evaluation required at that point).

The goal of Track A is a genuinely general-purpose RoCE NIC —
the thing the original P1–P7 plan targeted.  Reaching it from
ERNIC v4.2 requires removing the single-MR-per-QP restriction,
adding real CC, and at least considering atomics/UD.  Two
plausible approaches:

### 7.1 A1 — Wrap ERNIC with a RoCE pre/post-processor

Build RTL around ERNIC that interposes on both wire directions
and rewrites state so ERNIC "sees" one MR per QP while the
external wire and host sees many:

- **MTT (Memory Translation Table)** implemented in fabric
  alongside ERNIC.  External rkey → internal "fake" rkey that
  ERNIC thinks is its single per-QP MR.
- **Rkey / VA / ICRC rewrite on RX:** RoCE header parse, rkey
  lookup in MTT, rewrite to ERNIC-acceptable value, recompute
  ICRC, re-inject.
- **Rkey / VA / ICRC rewrite on TX:** reverse transform.
- **CQE rewrite:** ERNIC's internal rkey/VA in CQEs must be
  translated back to external values.

This addresses MR-per-QP.  It does **not** fix CC (still ERNIC's
one-shot), does **not** add atomics, does **not** add UD.  Honest
assessment: this is 6–12 months of RTL + verification for a
partial win.

### 7.2 A2 — Swap IP

Options to evaluate (non-exhaustive):

- Newer AMD RoCE IP (successor to ERNIC — availability,
  roadmap, and restrictions unverified as of rescope).
- **Corundum** + open-source RoCE layer — research-ish but
  rapidly evolving.
- Commercial third-party RoCE IP (several vendors).

Each option has integration, licensing, and timeline tradeoffs.

### 7.3 Re-entry criteria

Track A does not start until all of:

- A concrete business driver for general-purpose RoCE that
  restricted Track B cannot satisfy.
- A fresh IP evaluation enumerating options with feature
  matrices, licensing / commercial terms, integration effort.
- A decision: A1 (wrap ERNIC), A2-with-IP-X (swap), or
  "stay on B/C/D indefinitely."

Until then Track A tasks stay frozen.

---

## 8. Unified phase matrix

Calendar view, ~1 engineer-equivalent primary effort.  Shared
foundation first; tracks fork after S3.

| Week | Shared | Track B | Track C | Track D |
|---|---|---|---|---|
| 1 | S0 | | | |
| 2 | S0/S1 | | | |
| 3 | S1/S2 | | | |
| 4 | S2/S3 | | | |
| 5 | S3 | B0 | C0 | D0 |
| 6 | | B0/B1 | C0/C1 | D0/D1 |
| 7 | | B1 | C1 | D1 |
| 8 | | B1/B2 | C1 | D1 |
| 9 | | B2 | C2 (needs backend spec) | D2 |
| 10 | | B2/B3 | C2 | D2 |
| 11 | | B3 | C2/C3 | D2/D3 |
| 12 | | B3/B4 | C3 | D3 |
| 13 | | B4 | C3/C4 | D3/D4 |
| 14 | | B4/B5 | C4 | D4 |
| 15 | | B5 | C4/C5 | D4 |
| 16+ | | soak | C5 | D4 |

Track A is deferred and not in the schedule.

Tracks C and D can proceed in parallel with B; all three share S0–S3.
Track C blocks at C2 pending backend-fabric spec — call this out
early with TT integration.

---

## 9. Acceptance gates per track (summary)

| Track | Done criteria |
|---|---|
| **Shared foundation** | S0–S3 pass; `onic_ernic.c` replaces ad-hoc Phase 1/1b test code as the regression baseline |
| **B (restricted NIC)** | B0–B5 pass; 4-hour soak; capability sheet published; Mellanox interop within subset |
| **C (gateway)** | C0–C4 pass + C5 per TT alignment; end-to-end external-host → TT-silicon demo |
| **D (TT↔TT)** | D0–D3 pass + D4 per TT alignment; sustained target throughput between two FPGAs |
| **A (future)** | Gated; criteria defined post-IP-survey |

---

## 10. LoC estimate and schedule

Rough, honest-to-goodness numbers.

| Component | LoC (new) | Effort |
|---|---:|---|
| Shared foundation (`onic_ernic.c`, MR slab, lifecycle helpers) | ~1500 | 4 weeks |
| Track B (`onic_ib.c`, `onic_ib_verbs.c`, `onic_ib_dp.c`, rdma-core provider stub) | ~3500 | 8–10 weeks |
| Track C (gateway daemon + `onic_gw.c` + backend-fabric glue) | ~2500 | 8–12 weeks (C2 gated on backend-spec) |
| Track D (orchestrator RPC shim + session manager) | ~1500 | 6–8 weeks |
| Track A1 (RoCE pre/post RTL + verification) | ~6000 RTL + ~2000 sim | 6–12 months |
| Track A2 (IP swap + new driver integration) | variable | 6–18 months depending on IP |

**Schedule target:** B + C + D together land in **5–7 months**
from S0 start, with tracks partially overlapping and C2
potentially blocked on external spec.  Track A, if pursued,
adds 6–12+ additional months.

**Team scaling:** splitting B and C/D across two engineers after
S3 roughly halves wall-clock; foundation phase is not
parallelizable.

---

## 11. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| **Backend-fabric spec (Track C) undefined** | Blocks C2 onward | Open ticket with TT integration team now; C0/C1 can proceed without it |
| **Atomic-op support in ERNIC unverified** | Could further narrow Track B | Read PG332 v4.2 opcode table during B1; if absent, document and reject cleanly |
| **CC collapse under fan-in** (Track C especially) | Performance cliff when many clients converge | Initial deployments on PFC-lossless fabrics; measure under fan-in during C3/C4 |
| **QP count ceiling (256)** | Limits Track C client count | Recompile ERNIC with higher parameter if survey shows need; budget a bitstream rev |
| **Dual-ERNIC interrupt coalescing under load** | Completion delivery latency | `CQINTSTS1-64` polling on IRQ — may need per-CQ MSI-X in a later bitstream rev |
| **CQ overflow behavior undocumented** | Silent data loss? | Instrument heavily in B4 / C4; size CQs conservatively |
| **AXI bus error on MR access undocumented** | Unclear recovery path | Instrument INTSTS in B4; document empirically |
| **Track A never re-entered** | Never ship general-purpose RoCE NIC | Acceptable — B/C/D stand on their own; revisit only with explicit business driver |
| **Customer conflation of Track B with ConnectX** | Expectation mismatch | Capability sheet up front; no marketing of Track B as general-purpose |

---

## 12. References

- **Audit:** `pg332_v4_2_production_audit.md`
- **PG332 v4.2 full text:** `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/cmac-us/pg332-ernic-4.2.md`
- **PG332 v4.3 full text (editorially equal):** `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/cmac-us/pg332-ernic-4.3.md`
- **Sibling project — tt-link UDP gateway:** `/home/alex/alex-notes/tenstorrent/fpga-erisc/status/tt-link-gateway-proposal/`
- **Dual-netdev current architecture:** `dual_netdev_plan.md`
- **Tier 1b QDMA audit (reference; host-memory path no longer on B's critical path):** `tier1b_qdma_audit.md`
- **Shell RTL (plugin):** `src/plugin/p2p/rdma_onic_250mhz.sv`
- **Existing Phase 0/0b/0c/1/1b regression sources:** `rdma_test/phase*.c`
- **Libreconic userspace (reference; not on Track B/C/D critical path):** `libreconic/`

---

## 13. Next action

1. **Start F2: bring up ERNIC on both CMAC paths in current
   bitstream.**  Validates the RTL graft from tasks 9–15 actually
   carries RoCE frames through to ERNIC on CMAC0 and CMAC1.  No
   driver; use ILA + external traffic from a ConnectX peer (or
   pcap-replay into CMAC RX).  Unblocks every other track.
2. In parallel, **F1 + F6**: lock the ERNIC AXI-Lite register
   map + build the BAR access helper.  Foundation for all
   Linux-side work in B/C/D.
3. Open the backend-fabric spec question with TT integration
   team — blocks Track C beyond C1, do not let it hit critical
   path.
4. Socialize this rescope with stakeholders who saw the earlier
   P1–P7 plan — capability envelope changed, delivery shape
   changed, the "production RoCE NIC" promise is now qualified.
