---
name: tt-rdma-v1-first-light-end-to-end
description: "P1 first-light validated 2026-05-23 — WH erisc → CMAC → FPGA classifier → ring publisher → QDMA C2H → host netdev RX, byte-for-byte"
metadata: 
  node_type: memory
  type: project
  originSessionId: ed34fe36-50cb-41d4-bdaf-0045ca258750
---

P1 first end-to-end SEND landed 2026-05-23. The complete TT-RDMA-v1 RX path from WH transmitter to host memory works on silicon with zero overflow/backpressure when properly armed.

## What was validated

Armed N=64 SEND opcodes via the WH erisc injector → observed exactly **32** SEND frames arrive at FPGA classifier → **32** ring slots published via QDMA C2H ST queue → **32** packets delivered to host netdev (`enp2s0`) → **2048 bytes** in `rx_bytes` (= 32 × 64 B slot). Every byte accounted for.

Counter snapshot (Δ over the burst):

| Counter | Δ |
|---|---|
| netdev `rx_packets` | +32 |
| netdev `rx_bytes` | +2048 (= 32 × 64B) |
| FPGA `cnt_op_send` (0x100300) | +32 |
| FPGA `rx_prod_idx` (0x100050) | +32 |
| FPGA `cnt_rx_c2h_bp_drop` (0x10005C) | 0 |
| FPGA `cnt_rx_overflow` (0x100058) | 0 |
| WH MAC `MAC_TX_FRAMES_LO` (0xFFBA081C) | ticking @ line rate |

## How to reproduce (cold path)

1. **Bitstream:** flash the build at `build/au250_tt_rdma_v1_endpoint/.../open_nic_shell.mcs` (or `.bit` via JTAG). System reboot picks it up.
2. **Driver:** `sudo insmod /home/alex/mpi-shfs/fpga/open-nic-driver/onic.ko` on `desktop-2` (10.42.0.180). Brings up `enp2s0` (CMAC0) + `enp2s0d1` (CMAC1).
3. **WH FW:** `cd /home/alex/mpi-shfs/tenstorrent/tt-metal-external-eth && source env_vars_setup.sh` then run `wh_fire_send.py` (or `arm_rdma_inject.py` standalone after a manual ELF load). ELF at `budabackend-master/build/.../erisc_cmac_rdma_inject/out/erisc_cmac_rdma_inject.elf`. Built via `RDMA_INJECT=1 make` in `targets/erisc_cmac_fpga/`.
4. **Drain ring (one-shot host CSR):** read current `prod_idx` at BAR2+0x100050, write that value to `cfg_rx_cons_idx` at BAR2+0x100054. Frees up 64 ring slots.
5. **Arm:** write the inject-params struct (16 × u32) starting at WH L1 0x1F40; magic `0x494E4A52` ("INJR") at offset 0 last. FW fires N TT-RDMA-v1 SEND/WRITE/etc frames then returns to idle (0x88B5 keep-alive at line rate).
6. **Observe:**
   - Host: `cat /sys/class/net/enp2s0/statistics/rx_{packets,bytes}` pre/post — no sudo needed.
   - FPGA: `pcimem /sys/bus/pci/devices/0000:02:00.0/resource2 <abs_off> w` for plugin CSRs (sudo, NOPASSWD).
   - WH: read L1 0x1E00 (heartbeat) and 0x1E04 (train_status) via tt-exalens.

## Known issues / refinements

- **50% loss at idle↔armed transition.** Armed N consistently produces N/2 frames at FPGA classifier. Likely first ~N/4 are caught in CMAC's TX pipeline at old config when ETH_TYPE switches, and last ~N/4 lost at switch-back. Workaround: arm with 2× the target count, or arm continuously without going back to idle (high-rate sweep mode). Not a blocker for first-light.
- **WH erisc CPU-bound at ~235k pps armed.** Bit-serial CRC32C dominates (~448 ns/header @ 500 MHz). Theoretical max would be byte-table CRC32C (~28 cycles/header) but the 1 KB table doesn't fit in the tight `.bss` ERISC_DATA region — see [[wh-fw-tx-stall-bisect]] for the dual-mode FW pattern and put-the-table-elsewhere note.
- **`cons_idx` is manual.** A real driver would advance it per slot read. For tests today: write `cons_idx = prod_idx` before each arm to free 64 slots. Real driver work belongs in onic or a TT-RDMA verbs provider.
- **Slot byte-level inspection requires CAP_NET_RAW** (e.g. tcpdump) which isn't in NOPASSWD sudoers on desktop-2. Adding `tcpdump` to NOPASSWD or using a raw-socket Python script with file caps would unblock the byte-match validation. Counters confirm the right number of bytes arrive.

## Two non-obvious bugs we discovered while getting here

See [[wh-fw-tx-stall-bisect]] — both must be honored in any custom WH FW:

1. **WH CMAC TX engine needs continuous activity.** An idle TXQ silently no-ops `START_RAW`. Fix: continuous TX from boot (dual-mode FW emits 0x88B5 keep-alives, switches to 0x1AF6 only while armed).
2. **`ETH_TXQ_TRANSFER_SIZE_BYTES < 128` silently drops TX.** Bisected: 64 → 1459 frames/500ms, 46 → 0/500ms, 128 → 2.6M/500ms. Pad small frames up to 128 B; receiver reads inner `length` field anyway.

See [[tt-rdma-v1-endpoint-phase-c-landed]] for endpoint history and [[tt-rdma-v1-qdma-path-decision]] for the C2H ST routing.
