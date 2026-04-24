# Tier 1b QDMA Integration Audit

Written 2026-04-17 at the end of the Tier 1a session. Tier 1a passed Phase 1 CSR bring-up 27/27 on both ERNICs. Next session picks up Tier 1b: wiring the QDMA AXI-MM slave bridge so host software can stage data into DDR4.

## What's committed so far (Tier 1b scope)

- `2b3941e` — `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`:
  - `en_axi_mm_qdma {false}` → `{true}`
  - `dma_intf_sel_qdma {AXI_Stream_with_Completion}` → `{AXI_MM_and_AXI_Stream_with_Completion}`
  - NEW: `en_bridge_slv {true}`
  - NEW: `axibar_highaddr_0 {0x000000FFFFFFFFFF}`
  - NEW: `axibar_notranslate {false}`
  - KEPT: `pf[0-3]_bar2_size_qdma {16}` (Tier 1a requires 16 MB for ERNIC1 at 0xa00000)
  - KEPT: MSIX {01F}, dma_reset_source_sel PCIe_User_Reset, PCI class codes 028000

**Consequence**: the QDMA IP will now synthesize with four new port groups exposed. Our current `qdma_subsystem_qdma_wrapper.v` does not know how to handle them. If we build now, synthesis will fail on unconnected QDMA IP ports.

## Audit: ours vs RecoNIC reference

Reference path: `/home/alex/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/`

### Features uniquely ours (worth preserving — a wholesale port would re-graft these)

| Feature | Our file:line | Why |
|---|---|---|
| `QDMA_ID` parameter | `qdma_subsystem.sv:21`, `qdma_subsystem_qdma_wrapper.v:22-24` | Dual-PF (2 CMAC = 2 QDMA instances) |
| Multi-board ref_clk ifdefs | `qdma_subsystem_qdma_wrapper.v:146-163` | `__au55n__`, `__au55c__`, `__au50__`, `__au280__` — HBM boards need 100 MHz ref |
| `USE_PHYS_FUNC==0` stub mode | `qdma_subsystem.sv:532-600` | Build path without QDMA traffic (lab/sim) |
| `axil_cfg_aclk` external input | `qdma_subsystem_qdma_wrapper.v:148` | Our clock routing |
| `usr_irq_in_*` as module ports | `qdma_subsystem.sv:100-102` | Our IRQ wiring path (RecoNIC forces these to 0 internally) |
| Dual-instance generate blocks | `qdma_subsystem_qdma_wrapper.v:287,459` | `generate if (QDMA_ID == 0) qdma_no_sriov ... else qdma_no_sriov_1 ...` |

RecoNIC does NOT have any of these. That's the cost of wholesale port.

### What RecoNIC adds (needed once `en_axi_mm_qdma=true`)

| Port group | RecoNIC wrapper lines | Port count | Must-wire? |
|---|---|---|---|
| `s_axib_*` (bridge slave) | 224-258 | 35 | **Yes** — Tier 1b's entire purpose |
| `m_axi_*` (QDMA DMA master) | 45-82 | 39 | Probably — see open question 1 |
| `s_axil_csr_*` + `s_csr_prog_done` | 202-221 | 18 + 1 | Probably — see open question 2 |
| `h2c_byp_in_mm_*` | 151-163 | 12 | Tie-off OK (we don't use MM descriptor bypass) |
| `c2h_byp_in_mm_*` | 187-199 | 13 | Tie-off OK |

Plus two new submodules in RecoNIC wrapper:
- `qdma_subsystem_axi_csr_cdc` — AXI-Lite CDC, 250 MHz (QDMA IP side) ↔ 125 MHz (our system AXI-Lite). Self-contained, ~45 lines of instantiation.
- `xpm_cdc_single` — single-bit CDC synchronizing `qdma_csr_prog_done` into axil_aclk.

Port totals: ~117 new ports (minus tie-offs, still ~92 "real") to add across both files.

### Clock / reset domain notes

- QDMA IP AXI-MM ports (`s_axib`, `m_axi`) run in `axis_aclk` (250 MHz). Same as our streaming ports. **No clock converter needed** between `axi_sys_mem_mux` output and QDMA `s_axib` — same domain.
- QDMA CSR AXI-Lite runs in `axis_aclk`. Our system AXI-Lite is 125 MHz. That's what `qdma_subsystem_axi_csr_cdc` bridges.
- `s_csr_prog_done` is a single-bit handshake from 250 MHz to 125 MHz domain — `xpm_cdc_single` with `SRC_INPUT_REG=1`, `DEST_SYNC_FF=4`.

## Recommended path: Option 3 — hybrid graft

Dismissed options:
- **Option 1 (wholesale port)** — replaces both files with RecoNIC's, then re-grafts QDMA_ID + multi-board ifdefs + USE_PHYS_FUNC=0 + axil_cfg_aclk + usr_irq ports. ~5 structural features to re-graft, each needs re-testing. Too much regression surface.
- **Option 2 (s_axib only, stub everything else)** — surgical but risky. Vivado synthesis will likely fail or mis-elaborate a QDMA IP with partially-wired MM port groups. Ruled out.

**Option 3** — add ~92 new ports to our existing wrapper module header + 2 CDC instances + propagate up to `qdma_subsystem.sv` module header + wire at top level. Our customizations untouched. Scope is clear and bounded.

## Open design questions (answer BEFORE touching RTL next session)

### Q1 — Where does `m_axi_*` point?

QDMA's AXI-MM DMA master for descriptor-driven H2C/C2H MM transfers. Three options:

- **Tie off** with AXI SmartConnect default slave. Safest if we only use the slave bridge (s_axib) for host→DDR4 staging and never use MM DMA engines. But QDMA IP may assert if master is tied off while MM mode is active.
- **Wire to `dev_mem` 4:1 crossbar** as a 5th master. Gives host a faster descriptor-driven path into DDR4 (avoids CPU-driven bridge-slave writes). But requires crossbar IP regen (5-master instead of 4) and expanding `dev_mem_4to1_axi_crossbar.tcl`.
- **Check RecoNIC's wiring** — what does their `open_nic_shell.sv` do with `m_axi_*`? The Tier 1a reference diff subagent report said "RecoNIC does not expose m_axi_bridge at top level" but the wrapper clearly has `m_axi_*` ports. Need to re-check whether RecoNIC routes it into the fabric or terminates it.

### Q2 — Does the `s_axil_csr_*` port need fabric-side programming?

- If the onic driver programs QDMA purely via the PCIe CSR path (internal to IP), we don't need to drive `s_axil_csr_*` from fabric — tie off.
- If AXI-MM mode requires descriptor ring setup via the AXI-Lite CSR port, we need to route `s_axil_csr_*` from our `system_config` AXI-Lite crossbar (adds a new port, new address-map entry, new crossbar master).
- PG302 (QDMA v4.0 PG) should answer this. Also check what the RecoNIC onic driver variant does — do they write to QDMA CSRs via `m_axil_pcie_*` or via an AXI-Lite path?

### Q3 — Can `h2c_byp_in_mm_*` / `c2h_byp_in_mm_*` be tied off?

Some Xilinx IPs reject unconnected input buses (elaboration errors). Need to verify:
- Tie `vld`/`mrkr_req` signals to 0 explicitly
- Tie address/length buses to 0
- Let `rdy` float (it's an output from QDMA)

PG302 should specify tie-off values. If not, copy the `.h2c_byp_in_mm_*(1'b0)`-style instantiation from any Xilinx example that uses `AXI_MM_and_AXI_Stream` without descriptor bypass.

### Q4 — Are all these ports actually required by our use case?

Tier 1b functional goal: **host mmaps BAR → writes to DDR4 for ERNIC SQ/RQ/CQ/DATBUF**. That ONLY needs `s_axib`. The other port groups are consequences of the IP config `AXI_MM_and_AXI_Stream_with_Completion`, not of our design need.

Is there a narrower IP config that exposes JUST `s_axib` + streaming? PG302 table of `dma_intf_sel_qdma` values:
- `AXI_Stream_with_Completion` — ST only (what we had before)
- `AXI_MM_with_Completion` — MM DMA only (drops streaming, won't work for our CMAC data path)
- `AXI_MM_and_AXI_Stream_with_Completion` — both (current choice)

If there's a "bridge-slave-only" flag separate from `en_axi_mm_qdma`, that would give us s_axib without the DMA engines. Worth searching PG302 for "Bridge mode" vs "DMA mode". Some QDMA variants have a pure-bridge config.

## Next session entry point

1. Read PG302 sections on Bridge Slave, AXI-Lite CSR, and descriptor bypass (answers Q2, Q3, Q4).
2. `grep` RecoNIC's `open_nic_shell.sv` for `m_axi_awvalid` / `m_axi_awaddr` to answer Q1 concretely.
3. Based on Q1-Q4 answers, finalize scope of port additions.
4. Execute hybrid graft:
   a. Add port declarations to `qdma_subsystem_qdma_wrapper.v` module header
   b. Wire the ports to the QDMA IP instance (inside both `QDMA_ID==0` and `QDMA_ID==1` generate arms)
   c. Instantiate `qdma_subsystem_axi_csr_cdc` + `xpm_cdc_single` (copy from RecoNIC)
   d. Propagate port group up through `qdma_subsystem.sv` module header
   e. Wire at `open_nic_shell.sv:~3384` — `axi_sys_mem_mux_*` → `qdma_subsystem.s_axib_*`
5. Run `ipgen` to verify the IP generates cleanly with new config.
6. Run synthesis-only build to catch connectivity errors before committing to full impl.
7. Only then full rebuild + `phase1_csr_bringup` sanity (BAR2 still 16M, existing ERNIC CSR still works) + Phase 2 design.

## File paths quick-reference

Our repo:
- `src/qdma_subsystem/qdma_subsystem.sv` (888L)
- `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v` (632L)
- `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` (updated 2b3941e)
- `src/open_nic_shell.sv:3384` (stub comment: "This will be connected when the QDMA s_axib port is wired")
- `src/utility/vivado_ip/dev_mem_4to1_axi_crossbar.tcl` (if Q1 → wire m_axi into crossbar)

Reference:
- `/home/alex/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/qdma_subsystem.sv` (1144L)
- `/home/alex/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v` (825L)
- `/home/alex/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/src/open_nic_shell.sv:1148-1784` (axi_sys_mem_* wiring to `s_axib`)

PG302 on disk (check this path exists):
- `/home/alex/Downloads/XilinxAmdDownloads/` (PG332 was found here for ERNIC; PG302 for QDMA should be nearby if downloaded)

---

# Session 2 addendum — 2026-04-17 (late)

## TL;DR
PG302 read end-to-end. Q1–Q4 all answered. TCL narrowed (working-tree edit, **not committed yet**). RTL graft planned to the exact line but **paused** on a directionality question that the next session must resolve before writing RTL.

## What was done
- Downloaded PG302 v5.1 (Nov 2025) to `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/pcie/pg302-qdma-en-us-5.1.pdf`.
- Converted to searchable markdown: `pg302-qdma.md` (10,324 lines) + `pg302-images/` (77 PNGs). Same sibling convention as PG332.
- Grepped RecoNIC `open_nic_shell.sv` for `m_axi_*` routing → **RecoNIC wires `m_axi_*` into a 4:1 dev_mem crossbar as a crossbar master** (RecoNIC: `open_nic_shell.sv:2535-2569`, into `axi_4to1_interconnect_to_dev_mem`). Answers audit Q1.
- TCL working-tree edit at `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`:
  - `dma_intf_sel_qdma` → `AXI_Stream_with_Completion` (reverted from MM+ST)
  - `en_axi_mm_qdma` → `false` (reverted from true)
  - `en_bridge_slv {true}` kept
  - `axibar_highaddr_0 {0x000000FFFFFFFFFF}` kept
  - `axibar_notranslate {false}` kept
  - `pf[0-3]_bar2_size_qdma {16}` kept (Tier 1a still needs 16 MB for ERNIC1 @ 0xa00000)
  - **Not yet committed** — waiting to batch with graft.

## Q1–Q4 final answers (from PG302 + RecoNIC evidence)

| Q | Answer |
|---|---|
| **Q1** (where does `m_axi_*` point?) | N/A — drop `en_axi_mm_qdma` means `m_axi_*` doesn't exist. Deferred to future "use DMA engines" decision. |
| **Q2** (`s_axil_csr_*` fabric-side prog?) | **Tie off / don't enable.** PG302 p163: this is for runtime Bridge-register + DMA-CSR access from fabric. `axibar_highaddr_0` is programmed statically at IP-gen so we don't need it. |
| **Q3** (bypass tie-offs?) | **Not needed** — `h2c_byp_in_mm_*` / `c2h_byp_in_mm_*` only exist when MM DMA + descriptor bypass are both enabled. We dropped MM DMA. |
| **Q4** (narrower IP config?) | **YES.** `en_bridge_slv` is a **separate IP toggle from `en_axi_mm_qdma`** (PG302 p162 Figure 27 — "Bridge Interface options" and "DMA Interface options" are independent panels). Bridge-slave-only gives us `s_axib_*` (~35 ports) without MM DMA (~92 total ports if we'd kept both on). |

## New scope (narrower) — ready to execute

| | Current (2b3941e) | Revised |
|---|---|---|
| New ports | ~92 | **~35** (`s_axib_*` only, from RecoNIC canonical) |
| CDC modules | 2 | **0** (s_axib runs `axis_aclk` 250 MHz, same as existing streaming) |
| Crossbar regen | 4→5-master | **None** (s_axib is a consumer, not crossbar master) |

## Exact insertion points (from Session 2 agents A/B/C)

### `qdma_subsystem_qdma_wrapper.v`
- Module header ends line 164 → insert 35 port declarations before it.
- `QDMA_ID==0` generate: lines 287-458, IP inst `qdma_no_sriov qdma_inst`, last port line 456 (`.phy_ready`) → append `.s_axib_*()` connections.
- `QDMA_ID==1` generate: lines 459-629, IP inst `qdma_no_sriov_1 qdma_inst`, last port line 628 → same.
- Clocks already in scope: `aclk_250mhz` / `aresetn_250mhz`.

### `qdma_subsystem.sv`
- Module header ends line 181 → insert 35 passthrough port declarations.
- `qdma_subsystem_qdma_wrapper` inst `qdma_wrapper_inst` at lines 321-461, last port line 460 → append `.s_axib_*(s_axib_*)`.
- `USE_PHYS_FUNC==0` stub block lines 532-600 → tie off **OUTPUTS** of the module's s_axib interface (8 signals: awready, wready, bid, bresp, bvalid, arready, rid, rdata, ruser, rresp, rlast, rvalid — tie to 0; ready signals OK at 0 to stall). Inputs to the module need no stub action (just unused wires).

### `open_nic_shell.sv`
- `qdma_subsystem` instantiated inside `generate for (i=0; i<NUM_QDMA; i++)` at lines 1671-1810. Instance `(` at line 1679.
- `axi_sys_mem_mux_*` master signals declared lines 1181-1219 (SINGLE bus, not per-QDMA).
- Stub comment to remove: lines 3419-3422 inside `__rdma_enabled__` block.

## RecoNIC canonical `s_axib_*` port list (ground truth)

From `RecoNIC/.../qdma_subsystem_qdma_wrapper.v:224-258`. 35 ports, widths confirmed:

```verilog
input   [3:0] s_axib_awid,          input  [63:0] s_axib_awaddr,
input   [3:0] s_axib_awregion,      input   [7:0] s_axib_awlen,
input   [2:0] s_axib_awsize,        input   [1:0] s_axib_awburst,
input         s_axib_awvalid,       output        s_axib_awready,
input [511:0] s_axib_wdata,         input  [63:0] s_axib_wstrb,
input         s_axib_wlast,         input         s_axib_wvalid,
output        s_axib_wready,        input  [63:0] s_axib_wuser,
output        s_axib_bvalid,        input         s_axib_bready,
output  [3:0] s_axib_bid,           output  [1:0] s_axib_bresp,
input   [3:0] s_axib_arid,          input  [63:0] s_axib_araddr,
input  [11:0] s_axib_aruser,        input  [11:0] s_axib_awuser,
input   [3:0] s_axib_arregion,      input   [7:0] s_axib_arlen,
input   [2:0] s_axib_arsize,        input   [1:0] s_axib_arburst,
input         s_axib_arvalid,       output        s_axib_arready,
output  [3:0] s_axib_rid,           output[511:0] s_axib_rdata,
output  [1:0] s_axib_rresp,         output        s_axib_rlast,
output        s_axib_rvalid,        input         s_axib_rready,
output [63:0] s_axib_ruser,
```

**Critical notes**:
- NO `awprot / awlock / awcache / awqos` exposed by QDMA IP (PG302 Tables 47-51 confirm; RecoNIC confirms).
- `awuser[11:0]` / `aruser[11:0]` — wider than PG302 documents (p118: awuser[7:0] = function_number). Upper 4 bits likely reserved/newer-variant. Tie upper bits to 0, function bits to 0 (single-PF path).
- `wuser[63:0]` / `ruser[63:0]` — per-byte parity. Tie `wuser` = 0 (no parity), let `ruser` float.

## THREE OPEN DECISIONS (block RTL write — next session must resolve first)

### Decision 1 — Directionality (IMPORTANT, may require rework)

PG302 is unambiguous:
- `m_axib_*` (AXI Bridge **Master**) = QDMA → fabric. Host writes a BAR typed "AXI Bridge Master" → lands on `m_axib` → fabric routes → DDR4 / CSR.
- `s_axib_*` (AXI Bridge **Slave**) = fabric → QDMA. Fabric initiates → QDMA masters PCIe onto host memory.

Session 1's audit stated the Tier 1b goal as "host mmap BAR → writes to DDR4 for SQ/RQ/CQ setup" but chose `s_axib`. Those are **inconsistent**:
- For host→DDR4 setup of queues-in-card-memory, need `m_axib` + a BAR typed AXI_Bridge_Master. (Our BAR2 is AXI_Lite_Master, reaches `m_axil` — that's why Tier 1a CSR bring-up works.)
- For ERNIC→host (queues-in-host-memory, ERNIC DMAs them), need `s_axib`. **This matches RecoNIC's pattern** + the stub comment in our `open_nic_shell.sv:3420` ("axi_sys_mem_mux output drives the QDMA bridge for host-memory DMA from ERNIC").

**Likely resolution**: ERNIC queues live in host memory (RecoNIC pattern), so `s_axib` IS the correct choice — the audit's goal-statement wording was just imprecise. Next session should confirm by inspecting the `onic-driver` variant that RecoNIC ships (where does it allocate SQ/RQ/CQ buffers?). If confirmed → proceed with `s_axib` graft. If card-DDR4 queues are actually desired → re-scope to `m_axib` + BAR reconfig.

### Decision 2 — Signal mismatch at `open_nic_shell.sv` wiring site

`axi_sys_mem_mux_*` (lines 1181-1219) ≠ `s_axib_*` signal sets:

| Signal | mux has? | `s_axib` has? | Resolution |
|---|---|---|---|
| `awprot / awlock / awcache / awqos` + ar-equivalents | ✅ | ❌ | Leave unconnected on mux side |
| `awuser[11:0] / aruser[11:0]` | ❌ | ✅ input | Tie to 0 (single PF) |
| `wuser[63:0]` | ❌ | ✅ input | Tie to 0 (no parity) |
| `ruser[63:0]` | ❌ | ✅ output | Leave unconnected |

Clean but not a blind passthrough — explicit tie-offs needed at the wiring site.

### Decision 3 — Multi-QDMA fan-out

`open_nic_shell.sv:1671-1810` instantiates `qdma_subsystem` inside `generate for (i=0; i<NUM_QDMA; i++)`. Dual-CMAC config → NUM_QDMA=2. But only ONE `axi_sys_mem_mux_*` bus (1181-1219).

Options:
- **A** (simplest): Wire mux → QDMA[0], tie off QDMA[1].s_axib_*.
- **B**: Add 1-to-2 demux — unnecessary complexity for Tier 1b.
- **C**: Verify which QDMA actually serves ERNIC — may be only one.

**Proposed default**: Option A. Grep `open_nic_shell.sv` for ERNIC→QDMA_ID binding to confirm.

## Artifacts this session
- PG302 searchable markdown: `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/pcie/pg302-qdma.md` (grep-friendly; PDF page markers `<!-- PDF page N -->` inline).
- PG302 images: `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/pcie/pg302-images/` (77 PNGs incl. Figure 1 architecture, Figure 27 Basic Tab).
- Audit evidence grep lines in `open_nic_shell.sv`:
  - Stub: `3419-3422`
  - `axi_sys_mem_mux_*` wires: `1181-1219`
  - `qdma_subsystem` inst (generate): `1671-1810`

## Revised Session 3 entry point (supersedes original)

1. **Resolve Decision 1** (directionality): grep the RecoNIC onic driver variant for how SQ/RQ/CQ buffers are allocated (host pages vs card DDR4). Likely confirms `s_axib` is correct.
2. **Resolve Decision 3** (fan-out): grep `open_nic_shell.sv` to find which QDMA_ID is bound to ERNIC. Default to Option A if ambiguous.
3. Apply RTL graft per insertion points above (Decision 2 tie-offs baked in).
4. Commit TCL revert + RTL graft as a single logical change: `build+rtl(qdma): Tier 1b Item 2 — bridge-slave-only narrow-scope graft`.
5. Run `script/build_2cmac_rdma_v2_ipgen.sh` → inspect generated `qdma_no_sriov.v` for the port list.
6. Synth-only build → catch connectivity errors cheaply.
7. Full rebuild → Phase 1 CSR regression (BAR2 16M, ERNIC CSR 27/27).
8. Phase 2 design (ERNIC RDMA data flow through `s_axib`).

---

# Session 3 addendum — 2026-04-17 (Decision 1 + Decision 3 resolved)

## Decision 1 — RESOLVED: `s_axib` is correct

**Verdict**: ERNIC queues live in **host memory** (default RecoNIC path). Wire `s_axib_*` (fabric → QDMA → host).

Evidence from RecoNIC userspace lib + driver:
- `RecoNIC/lib/rdma_api.c:453,459,476` — SQ/RQ/CQ allocated via `allocate_rdma_buffer(..., buf_location)` with `buf_location` defaulting to `HOST_MEM` (`examples/rdma_test/rdma_test.h:21`).
- `RecoNIC/lib/reconic.c:216-237` — `HOST_MEM` path pulls from pre-allocated hugepages; phys addr via `get_buffer_paddr`.
- `RecoNIC/lib/rdma_api.c:548-596` — host phys addrs written to ERNIC `SQBAi/CQBAi/RQBAi` CSRs.
- `RecoNIC/base_nics/open-nic-shell/src/open_nic_shell.sv:1743-1777` + comment `:1148` — QDMA `s_axib_*` wired to `axi_sys_mem_*`.

Session 1 wording ("host mmap BAR → DDR4 for queues") was imprecise; actual pattern is ERNIC DMAs host pages via QDMA bridge slave.

**Deferred**: `DEVICE_MEM` queue placement (would need `m_axib` + BAR type change + crossbar routing). Not in Tier 1b. Revisit only if profiling shows host-DMA is the bottleneck or a workload demands card-resident queues.

## Decision 3 — RESOLVED: Option A (shared mux → QDMA[0].s_axib, tie off QDMA[1].s_axib)

Current RTL in `open_nic_shell.sv`:
- Per-ERNIC outbound host-DMA buses exist: `axi_sys_mem_0_*` (lines 1017-1055) and `axi_sys_mem_1_*` (lines 1099-1137).
- Already merged upstream: `axi_interconnect_to_sys_mem_mux_inst` at lines 3160-3226 is a 2:1 arbiter producing a **single** `axi_sys_mem_mux_*` master (4-bit ID) at 3203-3222.
- Stub site: lines 3419-3422 ("This will be connected when the QDMA s_axib port is wired").
- No per-ERNIC-to-per-QDMA pairing in RTL.

Inherited from RecoNIC single-CMAC baseline (RecoNIC has 1 ERNIC; dual-ERNIC here reused the existing mux). Functional isolation of the two ERNICs is preserved; only peak host-DMA bandwidth is shared.

**Wiring**: `axi_sys_mem_mux_*` → `qdma_subsystem[0].s_axib_*` (with Decision 2 tie-offs). `qdma_subsystem[1].s_axib_*` → tie off handshake outputs at the module boundary.

## ERNIC independence — confirmed (reference for later phases)

Both ERNICs are fully independent at the RTL level:
- Separate instances `rdma_subsystem_0_inst` (`:2346`) and `rdma_subsystem_1_inst` (`:2611`).
- Separate CSR windows: ERNIC0 @ BAR2+0x800000, ERNIC1 @ BAR2+0xA00000 (`system_config_address_map.sv:347-348, 362-363, 870-906`).
- Strict 1:1 CMAC binding: ERNIC0↔CMAC0 (`:2365-2381`), ERNIC1↔CMAC1 (`:2630-2646`).
- Separate resets (`rdma_rstn` / `rdma_1_rstn`) and interrupts (`rdma0_intr` / `rdma1_intr`).
- Separate Tier 1 AXI crossbars (`:2876`, `:3020`).

Only shared resource is the downstream host-DMA path (the mux above). A user can bring up one port while the other is idle/down.

## Deferred architectural option — per-PF-per-ERNIC split

**Current model (post-Tier 1b)**:
- `NUM_PHYS_FUNC=2`, `NUM_QDMA=1`.
- QDMA IP exposes a **single** `m_axil_pcie_*` BAR2 master (`qdma_subsystem.sv:72-87`) — no per-PF demux inside the subsystem.
- System AXI-Lite crossbar has **one** slave input (`system_config_address_map.sv:535, 957-976`).
- **Consequence**: one driver instance on PF0 sees both ERNIC0 (@0x800000) and ERNIC1 (@0xA00000) in its BAR2. `NUM_PHYS_FUNC=2` gives a second PF with queue-space/MSI-X isolation but the **same** BAR2 layout — no per-PCI-function ERNIC split.

**To achieve one-PF-per-ERNIC** (each PF owns exactly one port):
1. Route the QDMA BAR2 AXI-Lite per-PF (QDMA IP can emit PF-tagged AXI-Lite; subsystem would need to preserve `awuser`/PF id instead of flattening).
2. Build a PF-steering demux: PF0 BAR2 → crossbar slice containing only ERNIC0; PF1 BAR2 → ERNIC1 slice.
3. Re-base each ERNIC to PF-local offset 0 (or keep global offsets and document per-PF maps).
4. Update `system_config_address_map.sv` and the onic-driver to bind one driver instance per PF.

**Scope**: Tier 2+ architectural rework, not Tier 1b. Record here so the option is not lost. Revisit if a multi-tenant / VM-passthrough use case requires true PCI-function-level isolation.

## Updated Session 4 entry point (supersedes Session 3 entry point above)

1. Decisions 1 and 3 are resolved (above). Decision 2 (signal mismatch tie-offs) is well-scoped and applied at the wiring site.
2. Apply RTL graft per Session 2 insertion points.
3. Commit TCL + RTL graft together (`build+rtl(qdma): Tier 1b Item 2 — bridge-slave-only narrow-scope graft`).
4. Run `script/build_2cmac_rdma_v2_ipgen.sh` → inspect generated `qdma_no_sriov.v` port list.
5. Synth-only build.
6. Full rebuild → Phase 1 CSR regression (27/27, BAR2 16M preserved).
7. Phase 2: ERNIC RDMA data flow through `s_axib` (driver + loopback test).

---

# Session 4 outcome — 2026-04-18

## Status: graft committed (`c92420d`), full build FAILED in opt_design

Synthesis completed (all port-matching errors from first run were due to stale QDMA IP cache; once the IP dir was deleted the regenerated IP matched the graft — 35/35 ports verified).

**Implementation failed at opt_design**:

```
ERROR: [Opt 31-67] LUT2 cell missing I0 input connection.
  Cell: qdma_if[0].qdma_subsystem_inst/qdma_wrapper_inst/qdma_inst/inst/rtl_wrapper_inst/
        csr_module.i_mst_axilite_csr/axil_pgm_noc_badr_0_d1_i_9
  Cause: Removal of unused logic caused a fanin path to an in-use LUT input to be trimmed.
```

The orphaned LUT is inside the **QDMA IP's bridge-slave CSR module**, specifically `axil_pgm_noc_badr_0` — the "program NoC base address register 0". This CSR is programmed at runtime via the `s_axil_csr_*` AXI-Lite interface.

## Re-evaluation of Session 2 Q2

Session 2 answered Q2 as "**Tie off / don't enable** the `s_axil_csr_*` interface — `axibar_highaddr_0` is programmed statically at IP-gen so we don't need it." That was based on a reading of PG302 p163.

**This failure suggests Q2 was wrong.** The QDMA IP's bridge-slave module has a runtime-programmable NoC BAR register (`axil_pgm_noc_badr_0`) that:
- Lives on the `s_axil_csr_*` path, and
- Must have a valid driver (or proper tie-off signaling "no runtime programming needed") for opt_design to clean up unused logic without leaving orphan LUT inputs.

With `s_axil_csr_*` left unconnected, synth correctly trimmed the CSR-to-register datapath, but opt_design's connectivity checker caught the resulting orphaned LUT.

## Three candidate fixes (pick one next session)

### Option A — Drive `s_axil_csr_*` from fabric (RecoNIC's approach)
- ~18 AXI-Lite port additions + `qdma_subsystem_axi_csr_cdc` (125↔250 MHz CDC) + `xpm_cdc_single` for `s_csr_prog_done`.
- Route through system_config AXI-Lite crossbar as a new master slice (or leave host-unreachable and driver-tied).
- This is what Session 2 originally inventoried at ~92 ports.
- Closest to validated RecoNIC pattern. Highest confidence but largest graft delta.

### Option B — Inspect the regenerated `qdma_no_sriov.v` for `s_csr_prog_done` and tie strategically
- The IP may expose a `s_csr_prog_done` signal indicating "host-side CSR programming complete / bypass CSR path".
- If present, driving it to `1'b1` (done without programming) + tying `s_axil_csr_*awvalid/arvalid=0` may be enough.
- Check `build/au200_2cmac_2pf_rdma_v2/vivado_ip/qdma_no_sriov/synth/qdma_no_sriov.sv` for the `s_axil_csr_*` / `s_csr_prog_done` port list.

### Option C — Enable axibar_notranslate
- Session 2 TCL has `axibar_notranslate {false}` (translation enabled, runtime CSR programs the table).
- If we set `axibar_notranslate {true}`, the IP may skip the translation register entirely and use pure pass-through (host PCIe address == fabric address).
- Simpler but loses the translation window capability. May not align with ERNIC's SQ/RQ buffer addressing.

## Recommended Session 5 first move

Run:
```
grep -E "s_axil_csr|s_csr_prog_done|pgm_noc" \
  build/au200_2cmac_2pf_rdma_v2/vivado_ip/qdma_no_sriov/synth/qdma_no_sriov.sv
```

That will list the exact CSR-path ports the regenerated IP emits. Then decide between Options A/B/C based on what's available and how Vivado elaborates them.

## Artifacts Session 4

- Commit `c92420d`: graft + TCL revert (working on the synth side, blocked at opt).
- Tier 1a preserved bitstream still at `build/_tier1a_preserved/open_nic_shell.bit`.
- Stale QDMA IP dir + failed impl_1 in `build/au200_2cmac_2pf_rdma_v2/` (can delete or leave; next run will regenerate anyway).
- `script/build_v2_full.log`: full log of the failed opt_design run.

---

# Session 5 addendum — 2026-04-18

## Root cause identified and fix applied (TCL only, no RTL change)

**Root cause** (deeper than Session 4 diagnosed): The opt_design error `[Opt 31-67]` was triggered by a driverless net **inside** the IP — `csr_module.i_mst_axilite_csr/s_axil_csr_araddr[4]`. When `s_axil_csr_araddr` is constant-tied to 0 at the IP port, Vivado constant-folds the address register write-enable path away, but the LUT consuming `araddr[4]` (`axil_pgm_noc_badr_0_d1_i_9`) survives trimming because its output is still load-bearing for the NoC BAR address register — leaving it with a driverless I0 input.

**Fix**: `axibar_notranslate {true}` (working-tree edit to `qdma_no_sriov_au200.tcl`).

- With `notranslate=false` (previous): IP instantiates a runtime-programmable BAR translation table (`axil_pgm_noc_badr_0`). Constant-tying `s_axil_csr_*` idle creates the orphaned LUT.
- With `notranslate=true` (now): IP uses pass-through addressing — `s_axib_awaddr` forwarded directly to PCIe unchanged. No translation registers → no orphaned LUT.

This is also **functionally correct** (not just a workaround): ERNIC writes host physical addresses directly into `s_axib_awaddr`. We need QDMA to forward those addresses verbatim to PCIe. A translation table with unprogrammed entries (reset=0) would have re-mapped ERNIC addresses to 0, breaking DMA. `notranslate=true` was the right setting all along.

**What `s_axil_csr_*` idle tie-off means now**: With `notranslate=true`, the translation registers are absent. `s_axil_csr_*` may still be emitted as a port by the IP (for other CSR registers), but the critical `axil_pgm_noc_badr_0` path is gone. The idle tie-off (awvalid=0, arvalid=0) in both wrapper generate arms is retained — harmless if the port still exists, and the IP's remaining CSR registers (if any) will see no transactions.

**Changes made this session**:
1. `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`: `axibar_notranslate {false}` → `{true}` (**not yet committed** — batch with build verification first)
2. Deleted `build/au200_2cmac_2pf_rdma_v2/vivado_ip/qdma_no_sriov/` to force IP regeneration.

## Session 5 next steps

1. Run `script/build_2cmac_rdma_v2_ipgen.sh` to regenerate IP with `notranslate=true` and verify `axil_pgm_noc_badr_0` no longer appears in `synth/qdma_no_sriov.sv`.
2. Run synth-only build — confirm opt_design passes.
3. Commit TCL change: `build(qdma): fix opt_design orphaned LUT — axibar_notranslate=true`.
4. Full rebuild → Phase 1 CSR regression (27/27, BAR2 16M preserved).
5. Phase 2: ERNIC RDMA data flow through `s_axib` (driver + loopback test).
