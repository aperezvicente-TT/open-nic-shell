# Production FPGA NIC — Master Plan

Written 2026-04-18. One synthesis target. No interim states that get discarded.

---

## The constraint

Synthesis takes hours. Every build that produces a non-production-quality bitstream is a wasted
cycle. The rule: **do not synthesize until all RTL for a milestone is complete and correct.**

---

## Two parallel tracks

```
RTL track          ──── Milestone A: production bitstream ────────────────────▶
Software track     ──────────────── Milestone B: kernel RDMA driver ──────────▶
                                            │
                                    Milestone C: ibverbs
```

RTL and software are independent after Milestone A. Software development does not require
re-synthesis unless a hardware bug is found.

---

## Track 1 — RTL (one synthesis to production)

### Current state (committed, blocked)

- `c92420d`: `s_axib_*` graft + TCL revert. Synthesis passes. `opt_design` fails: orphaned LUT
  inside QDMA IP CSR module (`axil_pgm_noc_badr_0_d1_i_9`) because `s_axil_csr_*` is
  constant-tied to 0 — Vivado folds the fanin path, leaving a driverless LUT input.
- Working-tree: `axibar_notranslate {true}` applied as diagnostic. **Do not synthesize this.**
  It is functionally wrong for production (removes QDMA DMA window enforcement) and was only
  explored to understand the root cause.

### Root cause of opt_design failure

`s_axil_csr_*` must be driven by register outputs (not literals) for Vivado to preserve the CSR
logic. The CDC bridge (`qdma_subsystem_axi_csr_cdc`) provides register-output fanin. Without it,
literal-zero tie-offs cause constant-folding → orphaned LUT.

**The fix is Milestone A item 1 below — not `notranslate=true`.**

---

### Milestone A — Production RTL (single synthesis target)

Revert `axibar_notranslate` to `false` and complete all RTL changes below before synthesizing.

#### A1 — Wire `s_axil_csr_*` through hierarchy + CDC bridge

**What**: 19-port AXI-Lite path from QDMA IP → fabric, with 125↔250 MHz CDC.

**Files to change**:
- `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v`
  - Remove literal tie-offs from both generate arms (lines 530–542, 751–762)
  - Add 19 port declarations + `csr_prog_done` output to module header
  - Connect ports to both QDMA IP instances
- `src/qdma_subsystem/qdma_subsystem.sv`
  - Add 19 passthrough port declarations
  - Connect to `qdma_wrapper_inst`
  - `USE_PHYS_FUNC==0` stub: tie output signals to 0 (awready, wready, bvalid, arready, rvalid,
    bresp, rdata, rresp, rlast — outputs of the module's s_axil_csr slave interface)
- `src/qdma_subsystem/qdma_subsystem.sv` — instantiate `qdma_subsystem_axi_csr_cdc`
  (copy verbatim from RecoNIC `src/qdma_subsystem/qdma_subsystem.sv` lines ~462–510).
  This is a self-contained Xilinx AXI-Lite CDC IP instantiation, no new IP needed.
- `src/qdma_subsystem/qdma_subsystem.sv` — instantiate `xpm_cdc_single` for `csr_prog_done`
  (copy from RecoNIC, ~8 lines). `SRC_INPUT_REG=1`, `DEST_SYNC_FF=4`.

**Why this fixes opt_design**: CDC register outputs are not constants. Vivado cannot fold them.
The `axil_pgm_noc_badr_0` register receives real (non-constant) fanin → no orphaned LUT.

Port list (from `tier1b_qdma_audit.md` Session 2, confirmed against regenerated IP):
```
s_axil_csr_awaddr[31:0]   s_axil_csr_awprot[2:0]   s_axil_csr_awvalid
s_axil_csr_awready        s_axil_csr_wdata[31:0]    s_axil_csr_wstrb[3:0]
s_axil_csr_wvalid         s_axil_csr_wready         s_axil_csr_bvalid
s_axil_csr_bresp[1:0]     s_axil_csr_bready         s_axil_csr_araddr[31:0]
s_axil_csr_arprot[2:0]    s_axil_csr_arvalid        s_axil_csr_arready
s_axil_csr_rdata[31:0]    s_axil_csr_rresp[1:0]     s_axil_csr_rvalid
s_axil_csr_rready         csr_prog_done
```

#### A2 — Add `m_axil_qdma_csr_*` to system address map

**File**: `src/system_config/system_config_address_map.sv`

Add slave index + base address matching RecoNIC's layout:
```verilog
localparam C_QCSR_INDEX    = 15;   // (or next available, adjust C_NUM_SLAVES)
localparam C_QCSR_BASE_ADDR = 32'h14000;  // 0x14000–0x16FFF, 12 bits
```
Add `m_axil_qdma_csr_*` output ports and address decode/mux logic (copy pattern from any
existing slave entry in the file).

**File**: `src/open_nic_shell.sv`
Wire `system_config_inst.m_axil_qdma_csr_*` → `qdma_subsystem_inst[0].s_axil_csr_*`
(QDMA[0] only — same fan-out decision as `s_axib`: single CSR bus).

#### A3 — Revert `axibar_notranslate`

**File**: `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`
```
CONFIG.axibar_notranslate {true}   →   CONFIG.axibar_notranslate {false}
```

Delete `build/au200_2cmac_2pf_rdma_v2/vivado_ip/qdma_no_sriov/` to force IP regeneration.

#### A4 — MSI-X interrupt audit (pre-synthesis, may need RTL changes)

Before synthesizing, audit interrupt wiring. If per-CQ vectors are needed, change RTL now.

Questions to answer (grep + PG332):
1. Is `rdma0_intr` / `rdma1_intr` a single rolled-up wire or a bus?
2. How many CQs per ERNIC can be active simultaneously?
3. Are 32 MSI-X vectors (`PF_MSIX_CAP_TABLE_SIZE = 0x01F`) sufficient for
   QDMA queues + ERNIC0 CQs + ERNIC1 CQs + admin?
4. Does the kernel RDMA driver need per-CQ MSI-X, or is a shared + status-register poll OK?

If per-CQ vectors are needed: add demux RTL now. If status-register poll is sufficient: no
RTL change needed.

#### A5 — Batch commit + synthesis

All A1–A4 changes committed as a single logical change before running any build.
Commit message: `rtl(qdma): Tier 1b complete — s_axil_csr_* production wiring + CDC bridge`

Build sequence:
1. `ipgen` → inspect regenerated `qdma_no_sriov.sv`: `axil_pgm_noc_badr_0` must be present
   and driven from `s_axil_csr_araddr` (not constant).
2. Synth-only → confirm opt_design passes.
3. Full rebuild → Phase 1 CSR regression (27/27, BAR2 16M preserved).
4. RDMA DMA test: ERNIC loopback Write, verify data arrives in host buffer.

**This is the only synthesis run for Milestone A.**

---

## Track 2 — Software (no synthesis dependency after Milestone A)

### Milestone B — Kernel RDMA provider driver

Replace the RecoNIC userspace model entirely. The driver registers with the Linux RDMA subsystem
and handles all hardware programming. Userspace touches nothing except via standard ibverbs.

**What to discard from RecoNIC**:
- `lib/reconic.c:get_buffer_paddr()` — reads `/proc/self/pagemap`, IOMMU-unsafe
- `lib/reconic.c:config_rn_dev_axib_bdf()` — userspace programs DMA windows, moves to kernel
- All userspace BAR2 direct writes for queue management — kernel-managed via mmap doorbell

**Driver structure** (build on top of onic-driver):

```
onic_rdma_probe()
    ib_alloc_device()
    ib_set_device_ops(&onic_rdma_dev_ops)
    ib_register_device()

onic_rdma_dev_ops = {
    .query_device        → report ERNIC capabilities
    .query_port          → report link state / speed from CMAC
    .alloc_pd / dealloc_pd
    .reg_user_mr         → pin_user_pages() + dma_map_sg() → IOVA
                           → program ERNIC PDT with base IOVA + length + rkey
                           → program QDMA DMA window via BAR2+0x14000
    .dereg_mr            → unmap + unpin
    .create_cq           → dma_alloc_coherent() for CQ ring
                           → program ERNIC CQ base + depth + MSI-X vector
    .destroy_cq
    .create_qp           → program ERNIC QP: SQ base IOVA + depth, RQ base IOVA + depth
    .destroy_qp
    .post_send           → write WQE to SQ ring, ring doorbell
    .post_recv           → write RQE to RQ ring, ring doorbell
    .poll_cq             → read CQEs from CQ ring (no syscall on data path)
    .req_notify_cq       → arm CQ for MSI-X
    .mmap                → expose doorbell page to userspace (kernel bypass for post_send)
}
```

**Memory registration (IOMMU path)**:
```
ibv_reg_mr(pd, va, length, access)
  → kernel: pin_user_pages_fast(va, npages)
  → kernel: dma_map_sg(pdev, sgl, nents, DMA_BIDIRECTIONAL)
            returns IOVAs — works with or without IOMMU
  → if ERNIC needs contiguous range AND pages are non-contiguous:
       iommu_map() to create contiguous IOVA window
  → program ERNIC PDT[n]: base_iova, length, rkey
  → program QDMA window[n]: base_iova, length (via BAR2+0x14000)
```

This works with IOMMU enabled (enterprise default) and without it (physical addr == IOVA).

### Milestone C — ibverbs userspace provider

After Milestone B, the kernel driver is complete. The provider library is a thin userspace shim.

```
onic_alloc_context()   → mmap doorbell page from driver
onic_post_send()       → write WQE to mmaped SQ ring, write doorbell (no syscall)
onic_post_recv()       → write RQE to mmaped RQ ring, write doorbell
onic_poll_cq()         → read CQEs from mmaped CQ ring (no syscall)
onic_create_qp/cq()    → call kernel via ioctl (once, setup only)
onic_reg_mr()          → call kernel via ioctl (once, setup only)
```

Data-path operations (`post_send`, `post_recv`, `poll_cq`) are kernel-bypass — no syscall.
Control-path operations (`reg_mr`, `create_qp`) go through the kernel.

**Validation**: `ibv_rc_pingpong` between two hosts. Then `perftest` suite for latency/bandwidth.

---

## What success looks like

| Milestone | Verification |
|---|---|
| A (RTL) | Phase 1 CSR 27/27 + ERNIC DMA Write loopback passes |
| B (kernel driver) | `ibv_devices` lists device; `ibv_devinfo` shows port state UP |
| C (ibverbs) | `ibv_rc_pingpong` works; `ib_write_lat` within expected range |

---

## Immediate next action

**Do not synthesize yet.** Complete A1–A4 first (RTL + pre-synthesis audits), then one build.

Start with A1: open `qdma_subsystem_qdma_wrapper.v`, remove the literal tie-offs, add the 19
port declarations, connect to both QDMA IP generate arms. Then A2 (address map), then A3 (revert
TCL), then A4 (interrupt audit), then commit and synthesize once.
