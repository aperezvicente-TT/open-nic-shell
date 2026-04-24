# Task Restructuring Proposal — Post-Rescope (2026-04-23)

## Context

The RoCE FPGA project has been rescoped from a single "general-purpose RoCE NIC"
goal into four tracks:

- **Track A** — General-purpose RoCE NIC. Gated; frozen pending parallel IP
  survey (wrap ERNIC vs swap IP).
- **Track B** — Restricted Linux RoCE NIC. `ib_device` in `onic.ko`, restricted
  ibverbs subset. NCCL/UCX/NVMe-oF/libfabric/stock ULPs explicitly *not*
  supported.
- **Track C** — RoCE gateway for external hosts. External ConnectX clients →
  FPGA terminates RoCE → forwards payloads to Tenstorrent chips over a
  non-PCIe backend fabric (spec TBD).
- **Track D** — TT↔TT RoCE transport. Two FPGAs, pre-arranged QP/MR pairings
  orchestrated by a TT-side layer (protocol TBD).

ERNIC v4.2 IP limits (single MR per QP, one-shot CC, no atomics, no UD/SRQ/XRC)
are the direct reason Track A is gated.

This document proposes how to triage the existing in-session task list and
restructure the remaining work into per-track tasks.

---

## 1. Task triage table

| ID | Title | Recommendation | Justification |
|----|-------|---------------|---------------|
| 16 | P1 — Verify s_axib path works in current bitstream | **REFRAME-TO-TRACK-B** | `s_axib` only matters when host memory is an RDMA source/sink; Tracks C/D stage through FPGA DDR4 and never touch host memory, so this is a Track B probe only. |
| 17 | P2 — ib_device skeleton registration in onic.ko | **REFRAME-TO-TRACK-B** | Linux `ib_device` is only relevant when Linux verbs are the control surface; Tracks C and D do not present ibverbs to the local host. |
| 18 | P3 — Control-plane ibverbs on ERNIC | **DROP (split)** | Shape differs radically across tracks: B = Linux verbs glue, C = ingress RoCE responder + gateway control, D = TT-orchestrated pairing stub. Split into per-track tasks. |
| 19 | P4 — Data-plane: post_send, poll_cq, MSI-X dispatch | **DROP (split)** | Shared-foundation portion (WQE/CQE/MSI-X plumbing) becomes a foundation task; per-track data-plane shapes are distinct and become separate tasks. |
| 21 | Write phase_p1_saxib_probe.c | **REFRAME-TO-TRACK-B** | Same reasoning as #16: `s_axib` probe is Track B only. |

Tasks 1–15 remain **completed** and are unchanged.

---

## 2. Proposed new task breakdown

Legend — Size: **S** = hours, **M** = days, **L** = ≥1 week. Track tags:
**F** (shared foundation), **B**, **C**, **D**, **A**.

### 2.1 Shared foundation (before track forks)

These are prerequisite to all three active tracks (B, C, D). They are mostly
about proving the ERNIC IP works end-to-end on our board with a known-good
loopback before we commit to any track-specific driver or firmware shape.

| ID | Title | Track | Deps | Size | Description |
|----|-------|-------|------|------|-------------|
| F1 | Audit ERNIC AXI-Lite register map from pg332 v4.2 | F | — | S | Cross-check the register map the driver will use against the v4.2 production audit we already have; lock a register header. |
| F2 | Bring up ERNIC on both CMAC paths in current bitstream | F | — | M | Validate that the graft compiled in tasks 9–15 actually lets ERNIC TX/RX RoCE frames on CMAC0 and CMAC1; no driver, use ILA + external traffic. |
| F3 | Pcap-based RoCEv2 loopback test against ERNIC RX | F | F2 | M | Replay captured RoCE WRITE/READ/SEND packets at CMAC RX and confirm ERNIC ingress counters advance and (for WRITE) DDR4 is written. |
| F4 | DDR4 staging buffer allocator design | F | — | M | Define how DDR4 is carved into MR-backing regions; needed by C and D (staging) and by B (MR pinning path). |
| F5 | MSI-X dispatch skeleton in onic.ko | F | — | M | Generic MSI-X vector table + ISR shell capable of routing ERNIC CQ/event interrupts; used by all tracks that run Linux-side (B always, C/D for management). |
| F6 | ERNIC register-access helper library | F | F1 | S | Thin wrapper around BAR access for ERNIC register read/write with logging; reused by B driver and by any Linux-side firmware bringup harness for C/D. |
| F7 | Lock down QP/CQ/PD lifecycle state machine | F | F1 | M | One diagram + one header: what states a QP goes through, who owns transitions. Diverges later per track but the ERNIC-side mechanics are common. |
| F8 | Bench harness for end-to-end RoCE traffic | F | F2 | M | Reusable test bench (scripts + pcap + counter scraping) so each track's bringup tests can share instrumentation. |

### 2.2 Track B — Restricted Linux RoCE NIC

| ID | Title | Track | Deps | Size | Description |
|----|-------|-------|------|------|-------------|
| B1 | s_axib runtime probe (was task 21) | B | F2 | S | Port `phase_p1_saxib_probe.c`: confirm `s_axib` BAR is reachable and decodes ERNIC registers under the live bitstream. |
| B2 | s_axib functional validation (was task 16) | B | B1 | S | Confirm ERNIC config writes from host through `s_axib` produce the expected register-side effects and no AXI hangs. |
| B3 | ib_device skeleton registration in onic.ko (was task 17) | B | F5, F6 | M | Register a minimal `ib_device` from the existing `onic.ko`; enumerate ports, caps, and device attrs hardcoded from ERNIC v4.2 limits. |
| B4 | Capability subset policy module | B | B3 | M | Central "what verbs/flags we support" table used to reject unsupported verbs cleanly instead of faulting later; documents restricted subset. |
| B5 | PD / MR / CQ / QP create/destroy verbs | B | B3, F4, F7 | L | Implement the create/destroy side of ibverbs against ERNIC; single-MR-per-QP restriction enforced in B4. |
| B6 | QP state transitions (INIT→RTR→RTS) | B | B5 | M | Implement `ibv_modify_qp` path with the subset of attributes ERNIC v4.2 honors. |
| B7 | post_send fast-path (WRITE/READ/SEND) | B | B6 | L | WQE build + doorbell; one-MR-per-QP constraint simplifies SGL handling. |
| B8 | CQ polling + event delivery | B | B5, F5 | M | `ibv_poll_cq` path + MSI-X-driven completion event channel. |
| B9 | One-shot congestion control plumbing | B | B7 | S | Wire ERNIC's one-shot CC notification so the driver at least observes and logs; no adaptive behavior needed for restricted subset. |
| B10 | Capability-subset conformance test | B | B7, B8 | M | Runs every verb we claim to support and every verb we reject; regression guard against accidental ABI drift. |
| B11 | perftest (ib_write_bw / ib_read_bw / ib_send_bw) bringup | B | B7, B8 | M | End-to-end perftest on a single HCA+ConnectX peer; first "real" user-space validation. |
| B12 | Restricted-subset app compatibility matrix | B | B11 | S | Document which apps in the capability subset run; explicitly note NCCL/UCX/NVMe-oF/libfabric as out-of-scope. |
| B13 | Track B production packaging (DKMS, udev) | B | B10, B11 | M | Package `onic.ko` with `ib_device` support behind a build flag; install-time conformance check. |

### 2.3 Track C — RoCE gateway for external hosts

| ID | Title | Track | Deps | Size | Description |
|----|-------|-------|------|------|-------------|
| C1 | Backend-fabric interface spec | C | — | — | **Blocked on backend spec.** Capture the fabric handshake, framing, and flow-control contract the FPGA must implement toward the TT chips. |
| C2 | External-client control-plane model | C | F7 | M | Decide how external ConnectX hosts discover and bring up QPs against the FPGA: static config file vs on-box CM responder. Restricted-subset only (no UD/SRQ/XRC). |
| C3 | Connection Manager (CM) responder on ERNIC | C | C2, F6 | L | If C2 picks dynamic CM: firmware/soft-CPU responder that accepts REQ, allocates QP on ERNIC, returns REP. Can be skipped if static config wins. |
| C4 | Ingress RoCE → DDR4 staging pipeline | C | F3, F4 | L | On WRITE/SEND from external client, land payload in DDR4 staging ring; one-MR-per-QP means the MR *is* the staging ring. |
| C5 | DDR4 → backend-fabric egress adapter | C | C1, C4 | L | **Blocked on backend spec.** DMA/streaming engine moving staged payload from DDR4 to backend fabric; includes credit/flow-control toward TT chips. |
| C6 | Backend → DDR4 → RoCE response path | C | C1, C4 | L | **Blocked on backend spec.** Reverse direction: TT chip returns data, it lands in DDR4, ERNIC READ-response or SEND delivers to external client. |
| C7 | Gateway-side one-shot CC policy | C | C4, C5 | M | Decide how to translate ERNIC one-shot CC into backend-fabric backpressure; a placeholder pass-through is acceptable for v1. |
| C8 | Gateway management plane (Linux side) | C | F5, F6 | M | `onic.ko` on the gateway FPGA exposes config/stats but *not* `ib_device`; `sysfs`/`netlink` for QP and staging-ring config. |
| C9 | Multi-client scaling study | C | C4 | M | How many simultaneous external clients are realistic given ERNIC QP count × DDR4 bandwidth × backend-fabric BW. |
| C10 | End-to-end external-client ↔ TT chip smoke test | C | C5, C6 | L | First full traversal: ConnectX host runs RDMA WRITE, TT chip sees payload on backend fabric. |
| C11 | Gateway conformance + soak test | C | C10 | M | Extended multi-client, mixed-op soak; crash recovery behavior documented. |

### 2.4 Track D — TT ↔ TT RoCE transport

| ID | Title | Track | Deps | Size | Description |
|----|-------|-------|------|------|-------------|
| D1 | TT orchestration control-protocol spec | D | — | — | **Blocked on TT-layer decision.** Define how the TT layer tells each FPGA which QP/MR/peer to pair with; likely a small message set over an existing sideband. |
| D2 | Pre-arranged QP/MR provisioning API | D | D1, F7 | M | `onic.ko` control surface that accepts "install QP N paired with peer X, MR covers DDR4 region Y"; no ibverbs exposure. |
| D3 | Static QP bring-up flow | D | D2, F6 | M | Drive ERNIC through INIT→RTR→RTS using pre-arranged parameters; no CM, no exchange. |
| D4 | TT↔TT data-plane: WRITE staging | D | F4, D3 | L | Two-FPGA RDMA WRITE between pre-paired DDR4 regions; single MR per QP is fine since pairing is 1:1. |
| D5 | TT↔TT data-plane: READ staging | D | D4 | M | READ direction; reuses most of D4's plumbing. |
| D6 | Pairing teardown + re-pairing flow | D | D3 | M | TT layer can un-pair and re-pair; must cleanly drain ERNIC state between pairings. |
| D7 | One-shot CC handling (TT↔TT) | D | D4 | S | TT↔TT is a controlled environment; simplest policy is "log and continue" for v1. |
| D8 | Two-FPGA loopback bench | D | D4 | M | Two DEV boards, CMAC↔CMAC direct, exercise WRITE/READ under TT orchestration stub. |
| D9 | Orchestration-layer integration | D | D2, D8 | L | Replace stub with real TT orchestration client; validate pairing lifecycle against the real control protocol. |
| D10 | TT↔TT soak + failure-injection | D | D9 | M | Crash one side, confirm orchestration layer re-pairs cleanly. |

### 2.5 Track A — General-purpose RoCE NIC (gated)

**Do not start any of these until the parallel IP survey returns a
recommendation** (wrap ERNIC v4.2 in additional RTL, or swap to a different
RoCE IP). All A-tasks are placeholders to preserve scope memory, not to plan
against.

| ID | Title | Track | Deps | Size | Description |
|----|-------|-------|------|------|-------------|
| A1 | IP-survey decision intake | A | IP survey | — | Consume the IP survey recommendation and pick: wrap-ERNIC, swap-IP, or defer-indefinitely. |
| A2 | Multi-MR-per-QP RTL/firmware work | A | A1 | L | Whichever path A1 picks, multi-MR is the headline missing feature vs Track B restricted subset. |
| A3 | UD / SRQ / XRC feature enablement | A | A1 | L | Required for NCCL/UCX/libfabric; only feasible if A1 chose swap-IP. |
| A4 | Atomics support | A | A1 | M | RC atomics; feasibility is IP-dependent. |
| A5 | Adaptive congestion control | A | A1 | L | Replace ERNIC one-shot CC with DCQCN or equivalent; IP-dependent. |
| A6 | Stock ULP conformance (NCCL/UCX/NVMe-oF/libfabric) | A | A2, A3 | L | The actual goal of Track A; everything above is enabling work. |

---

## 3. Critical path per track

### Track B (Restricted Linux RoCE NIC)

```
F1 ─► F6 ─┐
          ├─► B3 ─► B4 ─► B5 ─► B6 ─► B7 ─► B8 ─► B10 ─► B11 ─► B13
F5 ───────┤                            ▲
F7 ───────┤                            │
F4 ───────┘                            │
                                       │
F2 ─► B1 ─► B2 ──────────────────────► (s_axib must be usable
                                        by the time post_send
                                        fires real WQEs from
                                        host memory)
```

Rough parallelism: `F1/F5/F6/F7/F4` fan out; `B1/B2` s_axib validation runs
in parallel with the early verbs plumbing; everything collapses onto
`B5 → B6 → B7` as the long sequential spine.

### Track C (RoCE gateway)

```
F1 ─► F6 ─► C8 ───────────────────┐
                                  │
F3 ─► F4 ──► C4 ──┬─► C5 ─► C10 ─► C11
                  │        ▲
                  └─► C6 ──┘
                       ▲
C1 (backend spec) ─────┘   ◄── BLOCKS C5, C6
                                  
C2 ─► C3  (optional; skippable if static config)
```

`C1` is the gating blocker: `C5` and `C6` cannot progress until the backend
fabric spec is frozen. `C4` (ingress → DDR4) can land before `C1` is final
and is the right place to start Track C work today.

### Track D (TT ↔ TT transport)

```
F1 ─► F6 ─┐
F4 ───────┤
F7 ───────┤
          │
D1 (TT control proto) ─► D2 ─► D3 ─► D4 ─► D5 ─► D8 ─► D9 ─► D10
                                  │
                                  └─► D6 (teardown; branch)
                                  └─► D7 (CC; branch)
```

`D1` is the gating blocker; until the TT orchestration layer picks a control
protocol, D2 must be stubbed. Everything F-prefixed can proceed independently.

---

## 4. First two weeks of concrete work

If work commits tomorrow (2026-04-24), the five highest-leverage tasks to
start — chosen so that (a) they unblock ≥2 tracks each, (b) they surface
hardware-vs-datasheet surprises early, and (c) they don't burn effort on
decisions still pending elsewhere:

1. **F2 — Bring up ERNIC on both CMAC paths in current bitstream.**
   Tasks 9–15 grafted the RTL; this actually proves the graft works. Unblocks
   *every* other track. No driver dependency.
2. **F1 + F6 — Lock the register map and build the access helper.**
   Small and parallelizable with F2. Every Linux-side piece of B/C/D needs
   this. F1 is audit-only; F6 is ~1 day of code.
3. **F3 — Pcap-based RoCEv2 loopback at ERNIC RX.**
   Confirms the IP actually speaks RoCEv2 the way v4.2 datasheet claims
   before we write driver code that trusts the datasheet. Depends on F2.
4. **B1 — `s_axib` runtime probe (ported from task 21).**
   Cheap, de-risks Track B's single biggest unknown (is the BAR even usable
   under the live bitstream), and is pure C code.
5. **F4 + F7 — DDR4 staging allocator design + QP/CQ/PD state-machine lock.**
   Design tasks, not code; they are the prerequisites that, if left implicit,
   cause rework in B/C/D simultaneously. Doing them now means every track's
   implementation starts from a written contract.

Explicitly *not* in the first two weeks:

- C1, C5, C6 — blocked on backend fabric spec.
- D1, D2 — blocked on TT orchestration protocol decision.
- Any A-prefixed task — gated on IP survey.
- B3 onwards — these are fine to queue, but F1/F5/F6 should precede them so
  the `ib_device` skeleton isn't hand-rolling register access.

---

## 5. Summary

- Closed tasks 1–15 remain closed.
- Old tasks 16/21 → Track B (**B1**, **B2**).
- Old task 17 → Track B (**B3**).
- Old tasks 18 and 19 are **dropped as monolithic items** and split per track:
  - Task 18 → **B3–B6** (Track B), **C2–C3 + C8** (Track C), **D2–D3** (Track D).
  - Task 19 → **F5** (shared MSI-X), **B7–B9** (Track B post_send/CQ/CC),
    **C4–C7** (Track C data-plane), **D4–D7** (Track D data-plane).
- New total: **8 foundation + 13 B + 11 C + 10 D + 6 A (frozen) = 48 tasks**,
  with the 6 A-tasks frozen until the parallel IP survey returns.
