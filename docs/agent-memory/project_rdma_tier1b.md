---
name: RDMA ERNIC Tier 1b in progress
description: CSR blocker FIXED (CDC bridge in wrapper); build running; dual-CMAC driver complete with MSI-X split fix
type: project
originSessionId: 53a9219d-413d-4f6a-a2e9-3099e2757bc2
---
Dual ERNIC (RoCEv2) integration on open-nic-shell, branch `feature/rdma-ernic`.

**Tier 1a — COMPLETE 2026-04-17.** Bitstream `au200_2cmac_2pf_rdma_v2` (BAR2 = 16 MB, ERNIC windows 2 MB, libreconic rewritten against PG332 v4.3). Phase 1 CSR bring-up passes 27/27 on both ERNICs. Validated on desktop-2, BDF `0000:01:00.0`. Tier 1a bitstream preserved at `build/_tier1a_preserved/open_nic_shell.bit`.

**Tier 1b — BUILD IN PROGRESS 2026-04-21.** Goal: wire QDMA bridge slave for ERNIC host-mem DMA.

**CSR opt_design blocker — FIXED.** Session 4 failure (orphan LUT in `axil_pgm_noc_badr_0`) was caused by tying off `s_axil_csr_*`. Fixed by implementing Option A: `qdma_subsystem_axi_csr_cdc` CDC bridge wired in `qdma_subsystem_qdma_wrapper.v` at line 361, crossing `s_axil_csr_*` from 125 MHz (axil_aclk) slave to 250 MHz (axis_aclk) master into QDMA IP. TCL at `src/qdma_subsystem/vivado_ip/qdma_subsystem_axi_csr_cdc.tcl` (untracked on disk, needs commit).

**Current build**: `au200_2cmac_2pf_rdma_v2`, started 2026-04-21 ~11:58. Has bridge slave + CSR fix. Will produce 32 MSI-X vectors (PF0_MSIX_CAP_TABLE_SIZE=0x01F). Driver handles this with 15 queues/CMAC split.

**MSI-X fix**: `qdma_no_sriov_au200.tcl` updated to `0x081` (130 vectors → 64/CMAC). Committed to shell branch. Takes effect on next IP regen rebuild.

**Driver** (branch `feature/ernic-v4.2-rebuild`, commit `68297e3`): dual-CMAC single-PF complete. MSI-X split bug fixed — `onic_init_capacity` runs before `onic_init_hardware` so `num_cmacs` is 0 at split time; guard changed to `MASTER_PF` flag only.

**Why:** Dual-ERNIC RDMA WRITE loopback is the end goal; bridge wiring is the last structural blocker. ERNIC `axi_sys_mem` → `s_axib` → PCIe → host DRAM.

**How to apply:** Current build expected to complete in ~4-6 hours from start. Next step: flash bitstream, reload driver, verify both `enp1s0` and secondary CMAC1 net_device come up with 15 queues each, then test ERNIC data plane.

**Architectural scope note:** This targets host CPU memory as the RDMA data target. Not compute-in-network (on-FPGA DDR4/HBM).
