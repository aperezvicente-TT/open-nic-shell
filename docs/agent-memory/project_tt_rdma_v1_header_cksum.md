---
name: tt-rdma-v1-header-cksum-keep-default-off
description: "TT-RDMA-v1 header_cksum — endpoint RTL implements CRC32C validate but ships with CTRL.cksum_check_en=0; injector computes CRC32C always; matches today's ecosystem (no peer computes it) while keeping optionality"
metadata: 
  node_type: memory
  type: project
  originSessionId: ed34fe36-50cb-41d4-bdaf-0045ca258750
---

**Decided 2026-05-22 (revised same day):** ship the FPGA endpoint with CRC32C validate logic in RTL but **default-OFF** at silicon (`CTRL.cksum_check_en` bit defaults to 0). FW injector still computes CRC32C on every TX (harmless when endpoint ignores it; ready for future ecosystem turn-on).

**Why default-OFF, not default-ON:**

- Spec mandates the field but the entire WH ecosystem currently treats `header_cksum` as reserved-but-inert. All four WH FW variants (`targets/erisc/` real production, `erisc_cmac_simple/` TT-RDMA-v1 demo, `erisc_cmac_fpga/` newer fork, our `erisc_cmac_rdma_inject/` injector clone) ship **zero CRC32C infrastructure**.
- Even the real WH↔WH NoC-over-Ethernet routing FW (`targets/erisc/`) treats Ethernet FCS as the only integrity check — no software CRC, no end-to-end payload digest, hardware link-retransmit (`ETH_TXQ` retry engine) commented out with "avoid #2943 issues" (`eth_routing_v2.cpp:141-146`). The cultural pattern is "FCS is enough."
- Production WH FW writes `header_cksum = 0` (e.g. `erisc_cmac_simple/main_cmac.cc:675` for READ_RESP; other opcodes inherit host-staged bytes). With default-ON our endpoint would silently drop every real production frame.

**Why keep the RTL anyway:**

- The endpoint is strictly more capable than the demo. When the ecosystem decides to turn on integrity (switch enters the topology, a soak shows silent corruption, customer compliance ask), enabling it is a host CSR write — no bitstream re-spin, no FW change beyond turning on compute on the peer side.
- ~50 LoC RTL + ~20 LoC counter wiring. Small.

**Why injector still computes CRC32C:**

- Cost is negligible (bit-serial, ~448 ns/header at 500 MHz). Injector fires bursts of N frames for bring-up — not in any line-rate path.
- Forward-compatible: if someone flips `CTRL.cksum_check_en=1` to test the validate path, the injector's frames pass cleanly. No reload needed.
- Matches what production-grade peer FW *should* do when the ecosystem catches up.

## CSR contract

| Bit | Name | Default | Behavior |
|-----|------|---------|----------|
| `CTRL.cksum_check_en` (BAR2+0x008 bit 3) | header CRC32C validate enable | 0 (off) | When 0: RTL parses header but ignores bytes 28-31. When 1: RTL recomputes CRC32C over bytes [0..27], compares to bytes [28..31], drops mismatches, increments `0x330 hdr_cksum_fail`. |

Counter `0x330 hdr_cksum_fail` is reserved-not-wired today; wiring it up is part of the same RTL change.

## The directory taxonomy

| Path | What it is | header_cksum behavior |
|------|-----------|------------------------|
| `budabackend-master/src/firmware/riscv/targets/erisc/` | Real production WH FW (NoC-over-Ethernet routing) | N/A — no TT-RDMA awareness. FCS-only integrity, no software CRC at all. |
| `budabackend-master/src/firmware/riscv/targets/erisc_cmac_simple/` | TT-RDMA-v1 demo target. Git tag `tt-rdma-v1.0` @ commit `a061241`, ELF md5 `43bdcb46`. | Writes `=0` on TX (READ_RESP at `main_cmac.cc:675`; other opcodes inherit host-staged bytes). Ignores on RX (`main_cmac.cc:538-541` opcode-whitelist only). |
| `budabackend-master/src/firmware/riscv/targets/erisc_cmac_fpga/` | Newer fork for WH↔FPGA path | Same as erisc_cmac_simple (no CRC infra). |
| `fpga/wh-erisc-fpga/src/` | Standalone snapshot of erisc_cmac_simple | Same. |
| `erisc_cmac_rdma_inject` (new) | Our P1 deterministic injector | **Computes** CRC32C on TX (bit-serial, no table — ERISC_DATA tight). |

See [[tt-rdma-v1-endpoint-phase-c-landed]] for endpoint context, [[tt-rdma-v1-qdma-path-decision]] for QDMA path, [[dont-cite-ernic-as-good-architecture]] for ERNIC framing.
