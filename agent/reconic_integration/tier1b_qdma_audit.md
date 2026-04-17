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
