# TT-RDMA-v1 FPGA Endpoint — Production Plan

**Status:** proposal, 2026-05-21. Synthesizes three parallel-agent designs into a single phased plan.
**Goal:** ship `plugin/tt_rdma_v1_endpoint/` as the line-rate FPGA-TT-Link partner NIC that
terminates the TT-RDMA-v1 wire protocol (ethertype `0x1AF6`, 32 B header) end-to-end against
the shipped WH FW `tt-rdma-v1.0` (md5 `43bdcb46`). No WH FW changes.

**Out of scope for v1:** the RoCEv2↔TT-RDMA RTL translator (BF3-gateway-in-fabric) is sketched
in §6 as Phase-2 future work. Do not start it until the v1 endpoint plus the host verbs provider
are both shipped.

---

## 1. Why this plan

- **Performance ceiling unlock.** The shipped TT-RDMA-v1 (`tt-metal-external-eth/docs/tt-rdma-v1/README.md`)
  is bound by the Mellanox PCIe Gen3 x4 partner at ~25 Gbps. FPGA-TT-Link removes that bottleneck.
  Target: sustained ≥ 80 Gbps wire, no PCIe hop on the partner side.
- **Wire compatibility.** WH FW is frozen — we mirror what Mellanox does, not what we'd prefer.
  Every locked decision in `README.md:109-119` (32 B header, opcodes, rkey encoding, 16 MR slots,
  PFC priority 3) is a non-negotiable contract.
- **De-risked.** Our UDP-bridge session validated the FPGA shell integration, exposed 4 RTL bug
  classes the new plugin must avoid, and built the JTAG/SPI/Vivado flow we'll reuse.

---

## 2. Architecture summary

Plugin sits alongside (not replacing) `tt_link_udp_bridge` — different ethertype, different role,
different classifier. Same shell, same `packet_adapter`, same QDMA.

**Path: CMAC0 RX → ethertype filter (0x1AF6) → 32 B header parser → MR table lookup → opcode dispatch
→ AXI-MM master DMA into host hugepage / off-chip MR → ACK/READ_RESP generator → TX arbiter
→ `tuser_dst[CMAC0+6]=1` → CMAC0 TX.** Full datapath stays at 250 MHz × 512 b = 128 Gbps internal,
PCIe sets the real ceiling.

### Module hierarchy

```
plugin/tt_rdma_v1_endpoint/
├── tt_rdma_v1_endpoint_250mhz.sv  — top, replaces tt_link_udp_bridge_250mhz at the box level
├── rdma_regs.sv                   — AXI-Lite CSR + MR table BRAM (clone of tt_link_regs fix)
├── rdma_rx_classifier.sv          — ethertype 0x1AF6 filter; counts legacy 0x1AF4/5
├── rdma_hdr_parser.sv             — latch 32 B header at beat0; sideband decoded fields
├── rdma_mr_lookup.sv              — 1-cycle BRAM read on rkey[31:24]; bounds + access flag check
├── rdma_opcode_dispatch.sv        — fan-out payload AXIS to per-opcode engines
├── rdma_write_engine.sv           — WRITE/WRITE_IMM → QDMA AXI-MM master write
├── rdma_read_engine.sv            — READ_REQ → AXI-MM read + READ_RESP builder
├── rdma_send_engine.sv            — SEND/SEND_IMM → host RxWqeRing publish (OWNED_BY_HOST last)
├── rdma_ack_engine.sv             — cumulative ACK gen + consumer; updates last_acked CSR
├── rdma_tx_arbiter.sv             — mux ACK > READ_RESP > IMM-completion onto CMAC0 TX
├── rdma_tx_frame_builder.sv       — L2 (14 B) + RDMA header (32 B) prepend on egress
├── rdma_pfc_ctrl.sv               — PFC priority-3 watchdog (≥¾ H2C-FIFO fill → emit pause)
└── tb/                            — cocotb regression (see §4)
```

### CSR map (locked decisions baked into reset values)

| Offset       | Reset           | Notes |
|--------------|-----------------|-------|
| `0x000`      | `0x0001_0000`   | `VERSION`; v1 wire-protocol flag in bit[16] |
| `0x008`      | `0`             | `CTRL` — bit0 `ep_enable`, bit1 `auto_ack`, bit2 `pfc_en` |
| `0x020`      | `0x1AF6`        | `ETHERTYPE` — writable for soak compat, but production = 0x1AF6 only |
| `0x024`      | `9000`          | `LINK_MTU` — **default jumbo, not 1500** (bridge session lesson) |
| `0x028`      | priority 3      | `PFC_CFG` |
| `0x100+n·32` | per MR          | MR table, 16 × 32 B; layout mirrors `tt-rdma-fw-arch-rx.md:184-198` |
| `0x300-33C`  | 0               | Per-opcode + drop debug counters |
| `0x500-5FF`  | 0               | Designed-in debug block (§5 of agent 3 report) |
| `0x5FC`      | 0               | `dbg_clear` strobe |

### Performance budget

| Stage | Latency | Steady throughput |
|-------|---------|-------------------|
| classifier + header parse | 3 clk | 1 beat/clk |
| MR lookup (dual-port BRAM) | 2 clk | new req every clk |
| WRITE → AXI-MM AW | 4-6 clk | 1 frame per ~6 clk |
| ACK gen | independent | own FIFO ≥16 deep so RX never stalls |

**Verdict:** 100 Gbps WRITE single-stream is achievable provided (a) QDMA in AXI-MM master mode
(no descriptor RTT), (b) PCIe ≥ Gen3 x16, (c) host can sink data. Single-stream READ caps at
~70 Gbps unless we issue ≥8 outstanding READs.

---

## 3. Phase plan

| # | Name | Deliverable | Acceptance | PW | Dep |
|---|------|-------------|------------|----|-----|
| **P0** | RTL skeleton + cocotb shell | Empty hierarchy with AXI-Lite, AXI4-S TX/RX, `tuser_dst[CMAC0+6]=1` asserted | `make sim` green; lint clean | 1 | — |
| **Phase A** | CMAC + PFC + jumbo | Wire to existing CMAC PTP IP, RFE+PFCE bits set, JE=1, MTU register default 9000 | 4080 B frame accepted; ILA shows tuser_dst high | 1 | P0 |
| **Phase B** | RX opcode dispatch | Header parser, ethertype filter, 16 B alignment check, length-at-+4 | 1000 random frames per opcode dispatched correctly; unknown counter increments | 2 | A |
| **Phase C** | RxWqeRing publish | QDMA C2H push, 64-slot × 1536 B ring per `host-sdk.md §3`, OWNED_BY_HOST written last | 10⁶ SEND, prod_idx matches; `rx_overflow_drops` increments on stall | 2 | B |
| **P1** | MR table + WRITE | 16-entry BRAM table, rkey-encoded slot+rand+gen, AXI-MM master to host hugepage | 1024 × 4080 B WRITEs, 100 % byte-match vs `register_mr_slot` golden | 2 | C |
| **P2** | WRITE_IMM + SEND_IMM | Immediate consumes 1 ring slot, payload at MR offset | Loopback WRITE_IMM imm=0xCAFEBABE → host RxCqe matches | 1 | P1 |
| **P3** | READ responder | READ_REQ → rkey lookup → AXI-MM read → READ_RESP with original tag | 256 outstanding READs byte-match; correlation tag preserved | 1.5 | P1 |
| **P4** | READ initiator | host post → outgoing READ_REQ; correlation table; landing MR fill on RESP | Echoes against WH FW `--rx-echo-read`, 4/4 landed | 1 | P3 |
| **Phase R** | ACK + cumulative reliability | Opcode 0x40, auto-ACK from responder, retx_window CSR; auto-on for WRITE/READ per `host-sdk.md §6` | 500 frames @ 1 % drop → retx_runs ≤ 30, zero data loss | 2 | P3 |
| **Phase 3.3** | 4-deep TX pipeline | Mirror WH `TX_BUF0_A/B/C/D`, 4 outstanding PCIe reads | ≥ 80 Gbps sustained in cocotb stretched-time; ≥ 60 Gbps on rig | 1.5 | P4 |
| **Phase I** | Host SDK integration | Matches `TtRdmaEndpoint` API per `tt-rdma-host-sdk.md` | 8-scenario loopback green: SEND/IMM, WRITE/IMM, READ, multi-MR ≥4, dereg-while-in-flight, overflow recovery | 2 | Phase R |
| **P5** | Multi-MR stress | 16-slot concurrent rkeys, generation race, zombie state | 1 M ops over 16 MRs, zero cross-contamination | 1 | Phase I |
| **P6** | 1 h soak | Long-run TX/RX, PCS counters, no drift | 1 h ≥ 80 Gbps, zero drops, zero PCS link-down events | 1 | P5 |
| **P7** | CMAC max-pkt + align sweep | Binary search `(4096, 9216]` for hang; align sweep at 1450 B | Documented MTU cap; align constant in RTL CSR | 0.5 | P6 |
| **P8** | Production release | SPI-flashed `.bit`, host SDK pinned, release notes | All 8 opcodes pass against WH FW md5 `43bdcb46`; 1 h soak ≥ 80 Gbps | 0.5 | P7 |

**Total: ~20 PW (~5 cal months solo, ~3 with parallel SW).**
**Critical path:** P0 → A → B → C → P1 → P3 → Phase R → 3.3 → Phase I → P6 → P8.

---

## 4. Validation strategy

**Test pyramid (lessons from our session — invest in L1 to keep L3/L4 cheap):**

| Level | Iter time | Catches | What failure looks like |
|-------|-----------|---------|-------------------------|
| L0 cocotb unit | <5 min full suite | protocol/FSM/off-by-one | scoreboard mismatch |
| L1 cocotb integration *(includes `packet_adapter_tx`)* | ~30 min full | cross-block plumbing | scoreboard mismatch / timeout |
| L2 Vivado synth + ILA | ~50 min | timing closure, real CMAC | timing-not-met, ILA shows X |
| L3 JTAG `.bit` board | ~5 min per cycle | host↔FPGA interop, PCIe enum | kernel oops, frame drops, `ethtool -S` mismatch |
| L4 SPI-flashed soak | 1 h+ per soak | drift, PCS instability, thermal | counter freeze, gradual drop creep |

### Cocotb regression — must-have tests

Each cites the bug class it catches; `(NEW)` = would have caught a session bug:

| Test | Catches |
|------|---------|
| `test_csr_axil_aw_w_same_cycle` *(NEW)* | **PCIe Completer Abort → host kernel oops** from hardwired AWREADY/WREADY. Drives AW+W same cycle. |
| `test_bridge_plus_packet_adapter_tuser` *(NEW)* | **`tuser_dst[CMAC0+6]=1` silent drop** — wires plugin TX → packet_adapter_tx → CMAC stub; asserts every beat has the bit set. |
| `test_integrated_mtu_with_encap` *(NEW)* | `cfg_mtu=1500` → 1542 B outer frame silently dropped as oversize. Sweeps cfg_mtu values. |
| `test_decap_single_beat_short_frame` *(NEW)* | Single-beat frames (≤64 B, e.g. ACK) wrongly rejected as "too short". Sweep payload {1, 8, 32, 56, 64}. |
| `test_header_parse_random` | Bad opcode dispatch, length-vs-BUF_PTR race |
| `test_mr_table_lookup` | rkey/gen validation, slot 0..15 RMW |
| `test_mr_dereg_race` | Late frame with stale generation → silent drop + counter |
| `test_rx_ring_overflow` | `rx_overflow_drops` increments, head/tail integrity |
| `test_owned_by_host_ordering` | OWNED_BY_HOST bit written LAST (PCIe ordering) |
| `test_retx_window_overflow` | Window full → backpressure; never drop committed seq |
| `test_ack_cumulative` | Cumulative ACK collapses seq window correctly |
| `test_full_loopback_{send,write,write_imm,read}` | End-to-end byte-match per opcode |
| `test_multi_mr_concurrent` | 4 MRs interleaved, zero contamination |
| `test_reliability_with_drops` | 1 % drop injection, retx_runs ≤ 30, zero data loss |
| `test_jumbo_max_size` | 4080 B + 8192 B SEND/WRITE (P7 boundary) |

**Coverage gate:** every opcode × {valid rkey, miss, bounds bad, access bad} = 32 cases.

---

## 5. Risk register

| # | Risk | Prob | Impact | Mitigation |
|---|------|------|--------|------------|
| R1 | CMAC TX max-pkt hangs > 4096 B (README open Q1) | High | High | P7 binary search; RTL caps `cfg_mtu`; auto-recycle on hang |
| R2 | CMAC RX alignment > 16 B needed for some sizes (README Q2) | Med | Med | P7 sweep; payload pre-pad logic |
| R3 | RxWqeRing overflow at small-frame bursts (README Q3) | High | Med | Ring size CSR-tunable; PFC pri-3 back-pressure to wire |
| R4 | PCS link unstable under sustained TX (README Q4) | Med | High | P6 1 h gate; PCS event counters in `0x500` block; auto-relock |
| R5 | Multi-MR rkey contamination (README Q5) | Low | High | P5 stress; 16-bit random + generation; state byte (free/valid/zombie) |
| R6 | AXI-Lite AW+W same-cycle → kernel oops *(session lesson)* | High if undefended | **Critical** | `test_csr_axil_aw_w_same_cycle` mandatory in CI; never ship without |
| R7 | `tuser_dst` silent drop *(session lesson)* | High if undefended | High | Integration test + SV assertion `tvalid \|-> tuser_dst[CMAC0+6]` |
| R8 | `cfg_mtu` default 1500 → outer oversize drop *(session lesson)* | High | High | Default 9000 at reset; integration test sweeps boundary |
| R9 | pcimem stat offsets drift per CMAC IP rev *(session lesson)* | Med | Low | `ethtool -S enp2s0` is ground truth; pcimem only for our 0x500 block |
| R10 | SPI sector-0 factory-lock on AU250 *(session lesson)* | Med | Med | Document GUI Erase / unprotect; JTAG `.bit` for L3 iteration |
| R11 | JTAG `.bit` is volatile, power-cycle wipes *(session lesson)* | High | Low | SPI for L4 only; JTAG reserved for fast L3 iteration |
| R12 | Single-thread Python ~290 kpps cap *(session lesson)* | Cert | Med | Throughput tests use FW burst-tx + `ethtool -S`; Python for correctness only |
| R13 | Vivado ~50 min build limits iteration | Cert | Med | Out-of-context synth for unchanged IP; incremental compile |
| R14 | OWNED_BY_HOST PCIe ordering | Med | High | RTL scoreboard test; ordering assertion |
| R15 | Host SDK contract drift vs `TtRdmaEndpoint` API | Low | High | Pin to WH FW `tt-rdma-v1.0` (md5 43bdcb46); CI on host-sdk.md hash |

---

## 6. Phase 2+ (future): RoCEv2-to-TT-RDMA RTL translator

A FPGA-fabric equivalent of `bf3-gateway-design.md`. **Do not start until v1.0-fpga endpoint and host
verbs provider both ship.** Reasons:

1. **Verbs provider is strictly cheaper** for the "unmodified libibverbs apps reach WH" goal —
   ~7 weeks of host software (`tt-rdma-verbs-provider.md`) vs. ~9-12 months of RTL.
2. **BF3 gateway is strictly better on flexibility** if a SmartNIC in the rack is acceptable —
   ~10 weeks for the niche where SmartNIC bandwidth is OK.
3. The **only case where RTL translator is the right answer**: (a) FPGA-TT-Link already in
   production, (b) compute host is not under our control (no kernel-module install possible),
   (c) BF3 is unacceptable as a PCIe hop in the data path. Real but narrow.

### Wire crosswalk summary (RoCEv2 ↔ TT-RDMA-v1)

| RoCE field | TT-RDMA-v1 | Class |
|------------|------------|-------|
| `BTH.opcode` | `opcode` | rewrite + state for FIRST/MIDDLE/LAST reassembly |
| `BTH.DestQPN` (24 b) | `tag[15:0]` (Option B) | truncate; **lossy** unless v1.x 32 b QPN ships |
| `BTH.PSN` (24 b) | `seq` (32 b) | stateful per-QP table (PSN window, retx dedup) |
| `RETH.VA` | `remote_offset` | subtract `mr.base_va` per rkey |
| `RETH.Rkey` | `rkey` | remap table RoCE rkey → TT slot/gen |
| `AETH.Syndrome` | — | drop / synthesize (NAK→remote-access-error only in v1) |
| `ImmDt` | `imm_data` | stateless rewrite |
| `ICRC` | — | drop on ingress, regenerate on egress |
| CNP / ECN | — | terminate locally; counter only |
| Atomics | reserved 0x30/0x31 | NAK until FW v1.2 |

### Hardest problems (rank order)

1. **Multi-packet message reassembly** (RC_SEND_FIRST/MIDDLE/LAST → one TT SEND). HBM-backed
   reassembly buffers; latency cost. WRITE is tractable via cut-through chunking; SEND needs
   true reassembly with MAX_MSG cap (16 KB MVP).
2. **PSN ↔ seq translation under loss + retransmit.** Per-QP PSN window bitmap, dedupe for
   retx-after-ACK-loss. Hardest correctness bugs hide here.
3. **RDMA-CM TCP termination.** Punt to host kernel module (not on-chip TCP). Same pattern
   every real HCA uses.
4. **ICRC compute, both directions.** Standard CRC32 with masked region; ~600 LUTs; spec foot-gun.

### MVP scope (v2 of translator)

- RC only (no UC/UD/XRC); ≤ 1024 QPs; ≤ 16 active MRs; multi-packet WRITE chunked; multi-packet
  SEND ≤ 16 KB cap; single RoCE port → single TT port; host-driven connection setup; no atomics.

### Resource estimate

~25–40 K LUTs, ~30–50 K FFs, ~80–120 BRAM, ~80–120 URAM, 64 MB–1 GB HBM/DDR for reassembly,
250 MHz × 512 b datapath.

### Dependencies before starting

- P0 v1.0 endpoint shipped (this plan)
- TT-RDMA-v1 wire stable through 1 h soak
- Option B QPN-in-tag working at scale
- MR registration control plane working
- 100 GbE datapath line-rate-clean
- Named customer / workload that needs exactly this (verbs provider doesn't fit, BF3 unacceptable)

**Realistic schedule once dependencies close:** 9–12 months to MVP translator. Plan as Phase-2,
not Phase-0 of this program.

---

## 7. Tooling reuse (session → production)

| Script | Status | Action |
|--------|--------|--------|
| `run_tt_link_test.sh` | Adapt | swap ethertype 0x1AF4 → 0x1AF6; add `dbg_clear` strobe + 0x500-block snapshot |
| `program_bridge_csrs.sh` | Adapt | add 16-entry MR table programming; MTU default 9000; RxWqeRing base |
| `manual_tx_trigger.py` | Adapt | add opcode arg (default SEND); build 32 B v1 header per wire-protocol-v1.md |
| `gateway_mode_test.py` | Rewrite | replace with `tt_rdma_endpoint_smoke.py` calling host SDK |
| `udp_blast.py` | Keep | useful for L3 raw-UDP background traffic / PFC coexistence |
| **NEW** `run_tt_rdma_v1_test.sh` | New | umbrella: snapshot 0x500-0x5FF pre/post; cocotb gate + host loopback |
| **NEW** `dump_dbg_counters.sh` | New | `pcimem` reads 0x500-0x5FF + diff vs `ethtool -S enp2s0` |
| **NEW** `interop_with_wh_fw.sh` | New | pinned to WH FW md5 43bdcb46; 8-opcode interop sweep |

**Key rule (R9):** never re-derive CMAC stats from pcimem PIO offsets — they drift per CMAC IP rev.
`ethtool -S enp2s0` is ground truth; the 0x500-0x5FF block is for FPGA-internal state only.

---

## 8. Definition of done — v1.0-fpga production release

All of:

- 1 h soak: ≥ 80 Gbps sustained TX and RX, zero frame drops, zero PCS link-down events
- 16 concurrent MRs × 1 M ops, zero cross-MR contamination
- 8 v1 opcodes all green: SEND, SEND_IMM, WRITE, WRITE_IMM, READ_REQ, READ_RESP, ACK, CONTROL
- Interop with WH FW `tt-rdma-v1.0` (md5 `43bdcb46`) — byte-match per opcode against the rig
- 1 % injected drop → `dbg_retx_runs ≤ 30` per 500-frame window, zero data loss
- `register_mr` → `post_send_write` → `wait_completion` matches `tt-rdma-host-sdk.md §8` byte-for-byte
- OWNED_BY_HOST ordering verified under PCIe stress
- README open Q1–Q5 closed with numeric answers (max-pkt cap, align constant, ring sizing, PCS stability, multi-MR)
- SPI-flashed `.bit` boots clean from cold power-cycle, 5-min smoke green
- Cocotb regression green in CI; build reproducible from tagged commit

---

## 9. Open questions for next design review

1. **QDMA AXI-MM master mode.** Does the existing open-nic-shell QDMA wrapper expose an AXI-MM
   master to user logic, or does it only support descriptor-ring queue mode? If only queue mode,
   we need a new wrapper variant. See `src/qdma_subsystem/`.
2. **NoC-PCIe DMA hugepage layout.** The WH `mr.base_noc_addr` is 64-bit NoC-encoded; the FPGA
   `MR[n].BASE_BUS` is an IOMMU bus address. Static convertible by host SDK or per-MR translation?
3. **Exact MR table CSR offset.** Doc proposes BAR2+0x100; confirm against
   `src/system_config/system_config_address_map.sv` to avoid collisions with existing slaves.
4. **READ_RESP > MTU.** Chunk into multiple READ_RESP frames with `tag` correlation, or drop+error?
   Verbs-correct = chunk; needs more state.
5. **WRITE_IMM completion ordering.** Data-before-immediate guarantee — does QDMA AXI-MM order
   completions, or do we need an explicit B-channel sync?
6. **`packet_adapter_rx` L2-strip behaviour.** Does it deliver bytes-on-wire (L2 still present)
   to the plugin, or pre-strip? Affects `rdma_hdr_parser` offset.
7. **Soft-reset semantics.** On `CTRL.ep_enable=0`, what about in-flight QDMA? Need an
   `INFLIGHT_DMA` counter and quiesce procedure.
8. **PFC pause quanta.** Wire-side max stall budget — pfc-lossless.md doesn't commit a number;
   recommend 0x4000 (~10 µs at 100 G) pending FW confirmation.

---

## 10. References

- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/README.md` — v1.0 status, open questions, locked decisions
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/tt-rdma-wire-protocol-v1.md` — 32 B header, opcodes, hex examples
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/tt-rdma-fw-arch-rx.md` — WH FW RX dispatch, MR table
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/tt-rdma-host-sdk.md` — `TtRdmaEndpoint` API the FPGA partner must serve
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/tt-rdma-pfc-lossless.md` — PFC priority 3 contract
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/bf3-gateway-design.md` — BF3 alternative; comparison anchor for §6
- `/home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth/docs/tt-rdma-v1/tt-rdma-verbs-provider.md` — host-software alternative; ships strictly cheaper than RTL translator
- `/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/plugin/tt_link_udp_bridge/` — session reference; the AXI-Lite handshake fix, single-beat decap, `tuser_dst` quirk, packet_adapter integration pattern all live here
- `/home/alex/mpi-shfs/fpga/open-nic-shell-tt-link/src/packet_adapter/packet_adapter_tx.sv:116` — `bad_dst` filter — silent-drop source
- `/home/alex/mpi-shfs/fpga/wh-erisc-fpga/{run_tt_link_test.sh,manual_tx_trigger.py,program_bridge_csrs.sh,udp_blast.py}` — bring-up tooling to adapt
