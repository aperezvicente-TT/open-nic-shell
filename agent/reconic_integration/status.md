# RecoNIC ERNIC Integration — Status Tracker

Last updated: 2026-04-17

## Summary

Dual Xilinx ERNIC (RoCEv2 RDMA) integration onto open-nic-shell — one ERNIC per CMAC port. **Tier 1a COMPLETE 2026-04-17**: rebuilt bitstream `au200_2cmac_2pf_rdma_v2` (ERNIC 2 MB crossbar windows, BAR2 = 16 MB, PG332 v4.3 register map in libreconic) loaded on `0000:01:00.0` (desktop-2). Phase 1 CSR bring-up passes 27/27 on both ERNIC0 and ERNIC1. Tier 1b (QDMA AXI-MM bridge + DMA buffer wiring) is the next milestone before Phase 2 RDMA WRITE loopback. See `tier1a_validation_runbook.md` for reproduction, `phase2_rtl_rebuild_plan.md` for scope history.

## Tier 1a — COMPLETE 2026-04-17

Validated on desktop-2, BDF `0000:01:00.0`, bitstream `au200_2cmac_2pf_rdma_v2`.

| Gate | Result |
|---|---|
| BAR2 size (lspci Region 2) | **16 M** on PF0 and PF1 ✓ |
| ERNIC0 GCSR reachable (BAR2+0x900000) | ✓ |
| ERNIC1 GCSR reachable (BAR2+0xb00000) | ✓ |
| Phase 1 CSR bring-up ERNIC0 | **27 / 27** ✓ |
| Phase 1 CSR bring-up ERNIC1 | **27 / 27** ✓ |

### What changed since 2026-04-16

- RTL: `system_config_axi_crossbar` ERNIC0/1 windows expanded 256 KB → 2 MB (PG332 v4.3 Table 9 footprint).
- QDMA TCL: `pf0_bar2_size_qdma` 4 → 16 (MB) — ERNIC1 now inside host-visible BAR.
- libreconic `reconic_reg.h`: offsets rewritten against PG332 v4.3 (GCSR 0x100000, QCSR 0x180000, PDT stride 0x100).
- Test `phase1_csr_bringup.c`: two register-map corrections (both userspace-only, no re-flash needed):
  - **XRNICCONF NUM_QP is software-written config, not IP-reported capability**. Test 1 now writes NUM_QP[15:8]=0x20, reads back, restores — consistent with libreconic's `(udp_sport<<16)|(num_qp<<8)|config_8bit` packing at `rdma_api.c:131`.
  - **QPADVCONFi bit[6] is reserved per PG332 v4.3** (DSCP/ECN gap inside the traffic_class field at [7:0]). Expected read-back of 0x5555_5555 is 0x5555_**15**55.

### Artifacts

- `phase1_ernic0.log` — ERNIC0 run, 27/27
- `phase1_ernic1.log` — ERNIC1 run, 27/27 (console captured, not tee'd)
- `rdma_test/phase1_csr_bringup.c` — idempotent; re-runnable without rebuilding bitstream

### What Tier 1a does NOT prove

Every Phase 1 test is save-write-restore against AXI-Lite. It confirms the register plane is decoded, the IP is not held in reset, and the 2 MB crossbar windows are live. It does **not** exercise the QDMA s_axib path, CMAC RoCEv2 traffic, MIG DDR4 calibration, or any DMA buffer register (SQBAi/RQBAi/CQBAi/DATBUFBA). Those are Tier 1b / Phase 2.

---

## RTL Blocker discovered 2026-04-16 — Items 1/1b/5 resolved in Tier 1a; Items 2/3/4 remaining

## RTL Blocker discovered 2026-04-16

Audit evidence (all verified by direct file read):

| Finding | Location | Impact |
|---|---|---|
| `axi_sys_mem_mux_*` wired out of `axi_interconnect_to_sys_mem_mux_inst` but has **no downstream consumer** (comment stub: "This will be connected when the QDMA s_axib port is wired") | `src/open_nic_shell.sv:3384-3388` | ERNIC's host-memory AXI-MM master floats. Any SQ/RQ/CQ/DATBUF placed in host memory will stall. |
| QDMA IP built ST-only | `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl:43-44`: `dma_intf_sel_qdma {AXI_Stream_with_Completion}`, `en_axi_mm_qdma {false}` | No QDMA slave bridge (host→DDR4) and no master bridge (ERNIC→host). |
| BAR2 = 4 MB | `qdma_no_sriov_au200.tcl:31-32`: `pf0_bar2_size_qdma {4}` | ERNIC1 (system offset `0x600000`) is outside the host-visible BAR → **ERNIC1 is unreachable on current bitstream**. Only ERNIC0 can be probed. |
| DDR4 path IS wired (good news) | `utility/vivado_ip/sys_mem_5to2_axi_crossbar.tcl:45-48` — M00 `0x0` (sys_mem, dead), M01 `0xa350_0000_0000_0000` (sys_to_dev, live) | ERNIC-DDR4 traffic works if buffer addresses have `0xa350...` tag, but host cannot stage data into DDR4 without a QDMA slave bridge. |

**Consequence for the end goal:** Phase 2 (actual RDMA WRITE loopback, CMAC0↔CMAC1) is blocked pending a rebuild that enables QDMA AXI-MM (slave bridge for host→DDR4 data staging, master bridge for ERNIC→host if desired). RecoNIC's reference `base_nics/open-nic-shell` has all four RTL/TCL changes needed — diff-portable.

Fix list for Phase 2 rebuild (see `phase0_1_plan.md` "When Phase 2 becomes possible"):
1. `qdma_no_sriov_au200.tcl`: enable `en_axi_mm_qdma`, `en_bridge_slv`, switch `dma_intf_sel_qdma`, set `axibar_highaddr_0`, bump `pf0_bar2_size_qdma` to 8.
2. `qdma_subsystem.sv`: expose `s_axib_*` + `m_axi_bridge_*` ports.
3. `open_nic_shell.sv:3384`: wire `axi_sys_mem_mux_*` → QDMA `s_axib`; QDMA `m_axi_bridge` → `dev_mem` 4-to-1 crossbar.
4. `open-nic-driver/onic_register.h`: `SHELL_END` `0x400000` → `0x800000`.

## Phase 0 Results — CLOSED 2026-04-16

### Definitive finding

**The original Phase 0 and 0.5 probes were never touching ERNIC GCSR.** They were writing to the Protection Domain / Memory Region Table at PD entry 512. Phase 0.6 (`rdma_test/phase0c_pd_table.c`) closed the investigation by round-tripping all 8 PG332 v4.3 Table 8 per-PD registers at entry 512 and confirming the 0x100 stride at entry 513.

**Root cause**: ERNIC IP version mismatch — the bitstream uses ERNIC **v4.2** (`src/rdma_subsystem/vivado_ip/rdma_core.tcl:19`), but libreconic's `reconic_reg.h` was authored against ERNIC **v4.0**. The register map moved between versions:

| Region | ERNIC v4.0 (RecoNIC/libreconic) | ERNIC v4.2/4.3 (our bitstream, per PG332) |
|---|---|---|
| MR/PD Table | 0x000000 | 0x000000 (unchanged — 2048 × 0x100 stride) |
| GCSR (XRNICCONF, MAC, IPv4, IPv6, DATBUFBA) | **0x020000** | **0x100000** |
| QCSR (per-QP SQ/RQ/CQ base addrs) | **0x022000** | **0x180000** |
| Total AXI-Lite space required | ~140 KB | **2 MB** (PG332 v4.3 Table 9) |

### What is reachable on the current bitstream

- **MR/PD Table entries 0–1023** (BAR2 + 0x200000 – 0x23FFFF, aka first 256 KB of ERNIC0's crossbar window).
- **Phase 0/0.5 writes to "XRNICCONF" `@0x220000` were actually PDPDNUM for PD entry 512** (24-bit wide, which is why `0xDEADBEEF` read back as `0x00ADBEEF`).

### What is NOT reachable

- GCSR (XRNICCONF, MAC, IPv4, IPv6, DATBUFBA, error buffers, interrupt controls)
- QCSR (SQBAi, RQBAi, CQBAi, QPCONFi, DESTQPCONFi)
- MR Table entries 1024–2047 (need 0x40000–0x7FFFF, outside our 256 KB window)

### Phase 0.6 evidence

Part A — PD[512] full 8-register round-trip (all writable registers round-trip at their PG332-specified widths):

| Register | Offset in PD slot | Width per PG332 | Write `0xA5A5A5A5` → readback |
|---|---|---|---|
| PDPDNUM | 0x00 | 24-bit | `0x00A5A5A5` ✓ |
| VIRTADDRLSB | 0x04 | 32-bit | `0xA5A5A5A5` ✓ |
| VIRTADDRMSB | 0x08 | 32-bit | `0xA5A5A5A5` ✓ |
| BUFBASEADDRLSB | 0x0C | 32-bit | `0xA5A5A5A5` ✓ |
| BUFBASEADDRMSB | 0x10 | 32-bit | `0xA5A5A5A5` ✓ |
| BUFRKEY | 0x14 | 8-bit | `0x000000A5` ✓ |
| WRRDBUFLEN | 0x18 | 32-bit | `0xA5A5A5A5` ✓ |
| ACCESSDESC | 0x1C | mixed ([31:16], [3:0]) | `0xA5A50001` — **access-type field [3:0] clamped** |

ACCESSDESC note: wrote `0b0101` to access-type [3:0], got `0b0001`. PG332 defines only `0b0000` (R), `0b0001` (W), `0b0010` (R+W) as supported values. The IP correctly rejected the unsupported encoding and latched the first supported subset — WAD.

Part B — PD[513].PDPDNUM at offset `0x220100` (= +0x100 from PD[512]) round-trips with the same 24-bit mask. Confirms 0x100 stride.

Part C — Read `BAR2 + 0x300000` (where GCSR would live if the crossbar window were 2 MB): returned `0xB000F000` / `0xB8080050` / `0xB000F001`. Not `0xFFFFFFFF` (so BAR is mapped) and not an XRNICCONF-shaped value. These are **CMS registers**; the system_config crossbar routes 0x300000 to M10 (CMS), not ERNIC.

Part D — Window edge: `[0x23FFF0] = 0x00000000` (last address inside ERNIC0 window; reads as 0 from unused PD slot), `[0x240000] = 0xFFFFFFFF` (first address past ERNIC0 window; no slave decodes this gap region).

### Consequence for the plan

Phase 1 (libreconic CSR-only bring-up) is **BLOCKED** on this bitstream: every register libreconic wants to touch (XRNICCONF, MACXADDLSB, IPV4XADD, SQBAi, etc.) lives at offsets ≥ 0x100000 inside ERNIC, which is outside the 256 KB crossbar window.

Phase 2 was already blocked. The new blocker (ERNIC window size) is additive, not orthogonal.

**Required RTL rebuild is now 5-item** (was 4). See `phase2_rtl_rebuild_plan.md` for detail:
1. Expand ERNIC0/1 AXI-Lite crossbar windows from 256 KB → 2 MB (PG332 v4.3 Table 9).
2. Re-layout `system_config_address_map.sv` to avoid ERNIC/CMS/BOX overlap.
3. Enable QDMA AXI-MM bridges (`en_axi_mm_qdma`, `en_bridge_slv`) and bump BAR2 to ≥ 8 MB.
4. Wire `axi_sys_mem_mux` → QDMA `s_axib`; QDMA `m_axi_bridge` → `dev_mem` crossbar.
5. Rewrite `libreconic/reconic_reg.h` against PG332 v4.3 offsets (GCSR 0x100000, QCSR 0x180000).

### Artifacts

- `rdma_test/phase0_ernic_probe.c` — initial 5-test probe (misinterpreted, documentation value)
- `rdma_test/phase0b_ernic_enable.c` — enable-sequence probe (misinterpreted, documentation value)
- `rdma_test/phase0c_pd_table.c` — closure probe (definitive)
- `rdma_test/phase0c_output.txt` — captured user output
- PG332 v4.3 reference on disk: `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/cmac-us/pg332-ernic.md`

---

## Overall Progress

| Step | Description | Status | Notes |
|------|-------------|--------|-------|
| 1 | Build system scaffolding | **DONE** | `-rdma`, `-classifier` flags; `__rdma_enabled__` define |
| 2 | Plugin skeleton | **DONE** | `plugin/rdma_onic/` (13 files), passthrough base |
| 3 | RTL packet classifier + filter | **DONE** | `packet_classifier_rtl.sv` (217L), `packet_filter.sv` (361L) |
| 4 | System address map (15-port crossbar) | **DONE** | ERNIC0@0x200000(M13), ERNIC1@0x600000(M14), BOX0→0x400000, BOX1→0x500000 |
| 5 | DDR4 memory controller | **DONE** | MIG IP from RecoNIC (MTA18ASF2G72PZ-2G3, 2400MT/s, 512b AXI) |
| 6 | Dual ERNIC IP wrappers | **DONE** | `rdma_subsystem` + `rdma_subsystem_1` (4 RTL, 3 TCL) |
| 7 | 3-tier AXI memory fabric | **DONE** | 5:2×2 + 2:1 + 4:1 + CDC (4 RTL, 4 TCL) |
| 8 | Top-level wiring + box ports | **DONE** | `open_nic_shell.sv`: 1274→3447 lines; `box_250mhz.sv`: 135→227 lines |
| 9 | Plugin wiring + libreconic | **DONE** | Classifier→ERNIC routing, TX merge, dual-port userspace API |
| 10 | First synthesis + bitstream | **DONE** | `au200_2cmac_2pf_rdma` loaded on 0000:82:00.0/.1, driver brings up netdevs |
| 11 | RTL audit | **DONE 2026-04-16** | Found blocker (see above): QDMA AXI-MM disabled, `axi_sys_mem_mux` dead-end, BAR2=4MB |
| 12 | Phase 0 — ERNIC0 liveness probe | **DONE (misleading pass; see Closure)** | Closed 2026-04-16 — probe was hitting PD table, not GCSR. ERNIC crossbar window too small for v4.2. |
| 13 | Phase 1 — CSR-only libreconic bring-up | **DONE 2026-04-17** | Tier 1a v2 bitstream passes 27/27 on both ERNICs (`phase1_ernic0.log`). |
| 14 | Phase 2 — RDMA WRITE loopback | **BLOCKED** | Tier 1b rebuild required: QDMA `en_axi_mm_qdma`/`en_bridge_slv`, wire `axi_sys_mem_mux` → QDMA `s_axib`, expose `s_axib_*` ports, populate DMA buffer regs in libreconic (Items 2/3/4 + 5-remaining). |

## File Inventory

### Modified (10 files, +2716 / -181 lines)

| File | Change |
|------|--------|
| `script/build.tcl` | `-rdma`, `-classifier` options; conditional module discovery; `__rdma_enabled__` define; DDR4 XDC sourcing |
| `src/open_nic_shell.sv` | +2173 lines: DDR4 pins, dual ERNIC wrappers, 3-tier fabric, DDR4 MIG, box sideband wiring (all ifdef guarded) |
| `src/box_250mhz/box_250mhz.sv` | +92 lines: 72 RDMA sideband ports per instance (ifdef guarded) |
| `src/system_config/system_config_address_map.sv` | +167 lines: 15-port crossbar, dual ERNIC AXI-Lite ports, address translation |
| `src/system_config/system_config.sv` | +76 lines: dual RDMA AXI-Lite port wiring |
| `src/system_config/vivado_ip/system_config_axi_crossbar.tcl` | +12 lines: M13/M14 config, BOX shift, NUM_MI=15 |
| `src/utility/vivado_ip/vivado_ip.tcl` | +4 IPs: sys_mem_5to2, dev_mem_4to1, sys_mem_2to1, axi_clock_converter_for_mem |
| `constr/au200/timing.xdc` | PTP timing constraints (pre-existing, unrelated) |
| `src/ptp_subsystem/ptp_subsystem.sv` | PTP CDC changes (pre-existing, unrelated) |
| `agent/ptp_ieee15888_timestamp/status.md` | PTP status updates (pre-existing, unrelated) |

### New — Plugin (16 files)

| File | Purpose |
|------|---------|
| `plugin/rdma_onic/rdma_onic_250mhz.sv` (647L) | Main plugin: classifier→ERNIC routing, TX merge, sideband passthrough |
| `plugin/rdma_onic/rn_reg_control.sv` (569L) | Statistics registers (RoCE/non-RoCE counters, timer, version) |
| `plugin/rdma_onic/packet_classification/packet_classifier_rtl.sv` (217L) | Fixed-function RoCEv2 parser (IPv4/UDP/4791/BTH) |
| `plugin/rdma_onic/packet_classification/packet_filter.sv` (361L) | is_rdma demux with dual xpm_fifo_sync (512 entries each) |
| `plugin/rdma_onic/p2p_322mhz.sv` | 322MHz passthrough (copied from p2p) |
| `plugin/rdma_onic/build_box_250mhz.tcl` | Sources plugin RTL |
| `plugin/rdma_onic/build_box_322mhz.tcl` | 322MHz build (copied from p2p) |
| `plugin/rdma_onic/box_250mhz/user_plugin_250mhz_inst.vh` | Plugin instantiation + RDMA sideband port connections |
| `plugin/rdma_onic/box_250mhz/box_250mhz_address_map*.` | Address map + crossbar (3 files, from p2p) |
| `plugin/rdma_onic/box_322mhz/*` | 322MHz plugin files (4 files, from p2p) |

### New — RDMA Subsystem (7 files)

| File | Purpose |
|------|---------|
| `src/rdma_subsystem/rdma_subsystem.sv` (37.6KB) | ERNIC0 IP instantiation + port exposure |
| `src/rdma_subsystem/rdma_subsystem_wrapper.sv` (39.8KB) | ERNIC0 wrapper (reset sync, TX merge) |
| `src/rdma_subsystem/rdma_subsystem_1.sv` (37.6KB) | ERNIC1 (mechanical rename) |
| `src/rdma_subsystem/rdma_subsystem_wrapper_1.sv` (39.8KB) | ERNIC1 wrapper (mechanical rename) |
| `src/rdma_subsystem/vivado_ip/rdma_core.tcl` | ERNIC0 IP creation (v4.0, 32 QP, 512b, 64b addr) |
| `src/rdma_subsystem/vivado_ip/rdma_core_1.tcl` | ERNIC1 IP creation (identical config) |
| `src/rdma_subsystem/vivado_ip/vivado_ip.tcl` | Lists both: `rdma_core rdma_core_1` |

### New — Memory Fabric (8 files)

| File | Purpose |
|------|---------|
| `src/utility/axi_interconnect_to_sys_mem.sv` (46.6KB) | Tier 1: ERNIC0 5:2 crossbar |
| `src/utility/axi_interconnect_to_sys_mem_1.sv` (34.7KB) | Tier 1: ERNIC1 5:2 crossbar |
| `src/utility/axi_interconnect_to_sys_mem_mux.sv` (16.7KB) | Tier 2: 2:1 sys_mem merge |
| `src/utility/axi_interconnect_to_dev_mem.sv` (34.2KB) | Tier 3: 4:1 dev_mem crossbar + CDC |
| `src/utility/vivado_ip/sys_mem_5to2_axi_crossbar.tcl` | 5:2 crossbar IP config |
| `src/utility/vivado_ip/dev_mem_4to1_axi_crossbar.tcl` | 4:1 crossbar IP config |
| `src/utility/vivado_ip/sys_mem_2to1_axi_crossbar.tcl` | 2:1 mux IP config |
| `src/utility/vivado_ip/axi_clock_converter_for_mem.tcl` | 250MHz→MIG clock CDC |

### New — DDR4 + Constraints (3 files)

| File | Purpose |
|------|---------|
| `src/mem_ctrl/au250/vivado_ip/dev_mem_ddr4_controller_au250.tcl` | MIG IP config (170L) |
| `src/mem_ctrl/au250/vivado_ip/vivado_ip.tcl` | IP discovery |
| `constr/au250/pins_ddr4.xdc` | MMCM placement, VREF, clock routing |

### New — Build Scripts (1 file)

| File | Purpose |
|------|---------|
| `script/build_2cmac_rdma.sh` | AU200, 2 CMAC, 2 PF, RDMA enabled, RTL classifier |

### New — Software (17 files)

| File | Purpose |
|------|---------|
| `libreconic/reconic_reg.h` | **Updated**: ERNIC0@0x200000, ERNIC1@0x600000, BOX0@0x400000, 8MB BAR2, `RN_PORT()` macro |
| `libreconic/rdma_api.h` | **Updated**: `port_id` field in rdma_dev_t, `create_rdma_dev_port()` API |
| `libreconic/rdma_api.c` | **Updated**: pointer-offset strategy for dual-port addressing |
| `libreconic/reconic.c, reconic.h` | Device init, BAR2 mmap, hugepage alloc (unchanged) |
| `libreconic/control_api.c/h` | Register read/write helpers (unchanged) |
| `libreconic/memory_api.c/h` | DDR4 memory access (unchanged) |
| `libreconic/auxiliary.c/h` | Utilities (unchanged) |
| `libreconic/Makefile` | Builds `libreconic.so` |
| `rdma_test/write.c, read.c, send_recv.c` | RDMA test apps (copied from RecoNIC) |
| `rdma_test/rdma_test.h` | Test common header |
| `rdma_test/Makefile` | Builds test binaries |

### New — Documentation (4 files)

| File | Purpose |
|------|---------|
| `agent/reconic_integration/plan.md` | Full integration plan (dual RDMA architecture) |
| `agent/reconic_integration/status.md` | This file |
| `agent/reconic_integration/phase0_1_plan.md` | Phase 0 (ERNIC liveness probe) + Phase 1 (CSR-only bring-up) — post-RTL-audit verification plan (2026-04-16) |
| `agent/reconic_integration/phase2_rtl_rebuild_plan.md` | Unified RTL+libreconic rebuild plan after Phase 0 closure (2026-04-16). Supersedes the Phase 2 fix list in this file. |
| `agent/openic_rdma_ernic.md` | Original single-ERNIC analysis |

## Address Map (when `-rdma 1`)

```
BAR2 Offset     Size    Module                Crossbar Port
─────────────── ─────── ───────────────────── ─────────────
0x000000        4KB     System config         M00
0x001000        20KB    QDMA subsystem #0     M01
0x008000        12KB    CMAC subsystem #0     M02
0x00B000        4KB     Packet adapter #0     M03
0x00C000        12KB    CMAC subsystem #1     M04
0x00F000        4KB     Packet adapter #1     M05
0x010000        8KB     System monitor        M06
0x012000        20KB    QDMA subsystem #1     M07
0x018000        12KB    PTP subsystem         M12
0x200000        256KB   ERNIC0 (CMAC0)        M13  ← NEW
0x300000        256KB   CMS                   M10
0x340000        4KB     QSPI                  M11
0x400000        1MB     BOX0 @ 250MHz         M09  (shifted from 0x100000)
0x500000        1MB     BOX1 @ 322MHz         M08  (shifted from 0x200000)
0x600000        256KB   ERNIC1 (CMAC1)        M14  ← NEW
```

ERNIC internal layout (within each 256KB window):
```
+0x00000   PDT (Protection Domain Table)
+0x20000   GCSR (Global Control/Status Registers)
+0x20200   QCSR (Per-QP Registers, stride 0x100, 32 QPs)
```

**Non-RDMA builds**: 13-port crossbar, original addresses (BOX0@0x100000, BOX1@0x200000), no ERNIC.

## Bugs Found and Fixed

| # | Bug | Date | Fix |
|---|-----|------|-----|
| 1 | Crossbar address overlap: ERNIC0 2MB window (0x200000-0x3FFFFF) overlapped CMS (0x300000) | 2026-04-15 | Reduced ERNIC crossbar window from 21-bit (2MB) to 18-bit (256KB). ERNIC only uses ~140KB internally. |
| 2 | `axi_sys_mem_mux_*` master never connected to QDMA slave bridge — ERNIC host-memory traffic floats | 2026-04-16 | **OPEN** — requires RTL rebuild (see Phase 2 fix list) |
| 3 | QDMA IP built ST-only (`en_axi_mm_qdma {false}`) — no host→DDR4 path, no ERNIC→host path | 2026-04-16 | **OPEN** — requires QDMA TCL update + rebuild |
| 4 | BAR2 size 4 MB, ERNIC1 at offset `0x600000` out of range — ERNIC1 unreachable from host | 2026-04-16 | **OPEN** — `pf0_bar2_size_qdma {4}` → `{8}` on next build |
| 5 | ERNIC IP version mismatch: v4.2 IP in bitstream, libreconic `reconic_reg.h` offsets against v4.0. GCSR moved from 0x20000 to 0x100000; QCSR from 0x22000 to 0x180000. Crossbar window (256 KB) is too small for v4.2's 2 MB AXI-Lite footprint. | 2026-04-16 | **OPEN** — requires both RTL (expand crossbar windows) and libreconic rewrite |

## Build Status

### First Build: AU200, 2 CMAC, 2 PF, Dual RDMA

```bash
./script/build_2cmac_rdma.sh
# vivado -mode batch -source build.tcl -tclargs \
#   -board au200 -tag 2cmac_2pf_rdma -rdma 1 -classifier rtl \
#   -user_plugin ../plugin/rdma_onic \
#   -num_cmac_port 2 -num_phys_func 2 -impl 1 -post_impl 1
```

| Phase | Status | Notes |
|-------|--------|-------|
| IP generation (AXI crossbars, CDC, MIG) | **DONE** | All IPs synthesized, crossbar overlap fixed |
| IP generation (ERNIC) | **PENDING** | Requires ERNIC license verification |
| Plugin sourcing | PENDING | After IP gen |
| Synthesis | PENDING | |
| Implementation | PENDING | Use Performance_Retiming strategy |
| Bitstream | PENDING | |

### Resource Estimate

~250-300K LUTs (dual ERNIC + DDR4 + fabric) on top of baseline (~850K available on AU250, similar on AU200).

## Driver Changes Required (Step 10)

| Change | File | Effort |
|--------|------|--------|
| BAR2 size: 0x400000 → 0x800000 | `onic_register.h` (`SHELL_END`), `onic_hardware.c` (`pci_iomap_range`) | 2 lines |
| No other kernel driver changes | — | RDMA is userspace via libreconic |

## libreconic Register Offset Changes

| Define | Old (RecoNIC) | New (open-nic-shell) |
|--------|---------------|----------------------|
| `RN_RDMA_BASE_ADDRESS` | 0x00040000 | 0x00200000 |
| `RN_RDMA_1_BASE_ADDRESS` | (none) | 0x00600000 |
| `RN_RDMA_PORT_DELTA` | (none) | 0x00400000 |
| `RN_PC_BASE_ADDRESS` | 0x100000 | 0x400000 |
| `RN_SCR_MAP_SIZE` | 0x00400000 (4MB) | 0x00800000 (8MB) |

ERNIC sub-offsets (GCSR, QCSR, PDT) are relative to base — unchanged.

Dual-port API: `create_rdma_dev_port(rn_dev, port_id)` — port 0 = ERNIC0, port 1 = ERNIC1.

## Prerequisites for Hardware Validation

| Requirement | Status | Check |
|-------------|--------|-------|
| Xilinx ERNIC license | **UNVERIFIED** | `create_ip -name ernic -vendor xilinx.com -library ip -version 4.0` |
| Vivado 2021.2+ | OK | ERNIC v4.0 compatibility |
| Hugepage support | OK | `cat /proc/meminfo \| grep Huge` |
| Two FPGA nodes (for RDMA test) | OK | desktop (AU200) + desktop-2 (Mellanox or second FPGA) |

## Repos

| Repo | Branch | Path |
|------|--------|------|
| Shell | `feature/rdma-ernic` | `/home/alex/mpi-shfs/fpga/open-nic-shell/` |
| Driver | `dev/driver-improvements` | `/home/alex/mpi-shfs/fpga/open-nic-driver/` |
| libreconic | (untracked) | `/home/alex/mpi-shfs/fpga/libreconic/` |
| Test apps | (untracked) | `/home/alex/mpi-shfs/fpga/rdma_test/` |
| Reference | main | `/home/alex/fpga-wksp/fpga-nic/RecoNIC-main/` |
