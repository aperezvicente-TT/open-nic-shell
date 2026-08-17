---
name: wh-fw-tx-stall-bisect
description: Two non-obvious WH erisc CMAC TX gotchas discovered during P1 injector bring-up — silently break TX with no error indication. Any future custom WH FW must avoid both.
metadata:
  type: reference
---

Two TX-killing pitfalls in WH erisc CMAC firmware, both discovered the hard way 2026-05-23 while building `erisc_cmac_rdma_inject`. Either alone causes 100% silent TX drop — MAC stat counters stay at 0, `ETH_TXQ_PKT_END_CNT` doesn't advance, no error register fires.

## Pitfall 1: CMAC TX engine needs continuous activity

If the FW does eth_cmac_link_init() then sits idle (e.g. polling for a host trigger), the MAC TX engine "goes to sleep" within seconds. Subsequent `ETH_TXQ_CMD = START_RAW` writes are silently no-ops — `MAC_TX_FRAMES_LO` stays at 0 indefinitely.

**Workaround:** mirror the production simple FW's pattern — fire q0 continuously from boot. If the FW is meant to be on-demand (like our `erisc_cmac_rdma_inject`), emit idle keep-alive frames at some neutral ethertype (we use 0xB588 → wire 0x88B5 IEEE Local Experimental) and switch the buffer/ethertype temporarily when "armed."

**Evidence:** `erisc_cmac_simple` runs ~21M MAC frames in 3s post-load. A no-TX injector accumulates 0 MAC frames over the same window — both with identical eth_cmac_link_init.

## Pitfall 2: `ETH_TXQ_TRANSFER_SIZE_BYTES < 128` silently drops TX

The WH ETH_TXQ has an effective minimum payload size somewhere between 64 and 128 bytes (post-L2 header bytes the TXQ DMAs from L1). Below that threshold, `START_RAW` returns immediately, CMD goes back to 0, but **no frame reaches the MAC**.

Bisect data (2026-05-23, external register pokes against running simple FW):

| `ETH_TXQ_TRANSFER_SIZE_BYTES` | Frames emitted in 500 ms |
|---|---|
| 1500 | 3,292,297 ✓ |
| 256 | 5,292,552 ✓ |
| 128 | 2,632,768 ✓ |
| **64** | **1,459 ✗** (essentially dead) |
| **46** | **0 ✗** |

So 128 B is the *floor*; 64 B silently no-ops at line rate. Workaround: pad small frames to ≥ 128 B post-L2 — the receiver reads the `length` field from the inner header anyway, so trailing pad bytes are ignored.

**Why both bugs hide:** `ETH_TXQ_CMD` goes 0 → 1 → 0 in microseconds whether the frame is actually transmitted or dropped, so polling CMD is no diagnostic. `event_counters[7]` (tx_stall) only fires if the *wait-for-CMD-0* loop times out, not if the TXQ silently swallows the START. The authoritative TX signal is `MAC_TX_FRAMES_LO` at `ETH_MAC_REGS_START + 0x81C` = `0xFFBA081C` (or `ETH_TXQ_PKT_END_CNT` at `ETH_TXQ0_REGS_START + 0x3C` = `0xFFB9003C`).

## Reusable injector pattern

`main_cmac_rdma_inject.cc` (in `budabackend-master/.../erisc_cmac_fpga/src/`) implements the dual-mode pattern:

```cpp
init_idle_buffer();            // fill TX_BUF0 with 1500-byte keep-alive pattern
eth_txq_reg_write(0, ETH_TXQ_CTRL,        ETH_TXQ_CTRL_USE_TYPE);
eth_txq_reg_write(0, ETH_TXQ_ETH_TYPE,    IDLE_ETHERTYPE_REG);  // 0xB588 wire 0x88B5
eth_txq_reg_write(0, 0x0C,                1536);                // MAX_PKT_SIZE
eth_txq_reg_write(0, ETH_TXQ_TRANSFER_START_ADDR, TX_BUF0_ADDR);
eth_txq_reg_write(0, ETH_TXQ_TRANSFER_SIZE_BYTES, 1500);        // idle frame size
// ... continuous tx_fire_q0() loop, check magic each iter, switch ETH_TYPE/TR_SIZE on arm.
```

When transitioning idle→armed or armed→idle, **always wait for `ETH_TXQ_CMD == 0` first** before changing TXQ registers — otherwise the in-flight frame may be emitted with mixed config and lost.

Use this pattern verbatim for any future TT-RDMA WH FW that needs on-demand opcode injection without breaking the continuous-TX requirement.
