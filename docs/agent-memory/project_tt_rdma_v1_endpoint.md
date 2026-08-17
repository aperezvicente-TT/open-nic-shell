---
name: tt-rdma-v1-endpoint-phase-c-landed
description: Phase A/B/C + 10 review fixes shipped and silicon-validated on AU250; next gate is custom WH FW + QDMA C2H wiring for P1
metadata: 
  node_type: memory
  type: project
  originSessionId: c4372cc9-6de5-4473-97ce-f51a44549f4b
---

Phase A/B/C of `plugin/tt_rdma_v1_endpoint/` is committed (head: `9db9b3b`, branch `feature/tt-link-udp-bridge`) and the resulting AU250 bitstream is **silicon-validated at the CSR + classifier layer**. End-to-end SEND injection deferred to P1.

**Why:** P1 needs custom WH erisc firmware to emit deterministic 0x1AF6 frames + QDMA C2H wiring for the host-side ring; both land together rather than building a one-off FW just for this validation step.

**How to apply:**
- Next session resuming endpoint work: skip CSR validation (done) and skip "did the build work" (done — bitstream loads, kernel binds, AXI-Lite handshake stable).
- The P1 plan is in `agent/tt_rdma_v1_endpoint/PRODUCTION_PLAN.md` — start there.
- The validated CSR offsets are below; don't re-discover them.

## Silicon validation snapshot (2026-05-22)

Bitstream: `build/au250_tt_rdma_v1_endpoint/.../open_nic_shell.mcs`
PCIe: `0000:02:00.0` on host `desktop-2` (10.42.0.180)
Driver: `/home/alex/mpi-shfs/fpga/open-nic-driver/onic.ko` (already in sudoers NOPASSWD)

Plugin CSR base in BAR2: `0x100000`. Verified reads:

| Offset | Value | Meaning |
|--------|-------|---------|
| 0x000  | `0x0001_0000` | VERSION = 1.0 |
| 0x004  | `RW` | SCRATCH — wrote/read 0xDEADBEEF; AXI-Lite handshake fix solid |
| 0x020  | `0x0000_1AF6` | ETHERTYPE — write-locked (hostile 0x1234 ignored) |
| 0x024  | `0x0000_0FF0` (4080) | LINK_MTU — review-fix default |
| 0x028  | `0x0000_0008` | PFC_CFG — priority-3 |
| 0x040..04C | ring config | base/log2n=6/stride=0x600 (1536 B) |
| 0x050  | `0x0` | rx_prod_idx |
| 0x054  | `RW` | rx_cons_idx |
| 0x058  | `0x0` | cnt_rx_overflow (ring-full drops) |
| 0x05C  | `0x0` | cnt_rx_c2h_bp_drop (new from review fix) |
| 0x300-0x33C | per-opcode counters | all 0; reads work |
| 0x518  | `0x0` | cnt_ethtype_legacy |
| 0x5FC  | write-any → clear-all | per review fix |
| 0x1000F0 (unmapped) | `0xDEAD_BEEF` | decode default works |

Classifier proven alive: `cnt_ethtype_drop` ticked +174M frames during testing (background WH FW traffic at non-0x1AF6 ethertype). No AER/Completer-Abort events in dmesg.

## What's NOT yet wired

- `m_axis_ring_push` is exposed by `tt_rdma_v1_endpoint_250mhz.sv` but the box harness (`box_250mhz/user_plugin_250mhz_inst.vh`) ties off QDMA C2H — slots reach the AXI-Stream output and stop. Host RAM publication needs the C2H bridge (P1).
- Custom WH erisc FW for deterministic 0x1AF6 frame injection is not built. `manual_tx_trigger.py` races with `erisc_cmac_simple.elf`'s autonomous TX queue activity — single-shot inject can't reliably land an RDMA-v1 frame with a chosen opcode byte. See [[reference-tt-link-bridge-test]] for the bridge-side pattern that does work (frames at 0x9999 hit the bridge classifier; bridge counts every byte not the opcode, so the race doesn't matter).

## Test suite

35 cocotb tests in `plugin/tt_rdma_v1_endpoint/tb/`, all green:
- `test_passthrough` (5), `test_aw_w_same_cycle` (2), `test_tuser_dst_set` (3),
- `test_mtu_default` (2), `test_debug_csr_decode` (3), `test_jumbo_passthrough` (3),
- `test_opcode_dispatch` (6), `test_rx_ring` (11)

8 new tests added during review fixes lock down: WRITE_IMM ring, endianness LE, c2h backpressure split, tkeep all-1s, back-to-back frames, multi-beat frame, clear-all-counters, ETHERTYPE RO-lock.

## Review fixes summary (commit 9db9b3b)

Blockers closed: `mod_rst_done` port via `generic_reset`; LE wire endianness; WRITE_IMM ring slot.
Serious closed: CDC layer (`cdc_sync.sv`); ring-full vs C2H-bp split; ETHERTYPE RO-lock.
Minor closed: `beat0_tdata_q` `is_beat0` gating; CSR clear-all at 0x5FC; MTU=4080; dead-code purge.
