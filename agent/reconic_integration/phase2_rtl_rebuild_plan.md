# Phase 2 RTL Rebuild Plan — post Phase 0 closure

Date: 2026-04-16
Supersedes the "Phase 2 fix list" in `status.md`.

## Why a rebuild is required

Phase 0 closure (see `status.md` Phase 0 Results section) proved three independent RTL-level blockers for end-to-end RDMA on the current `au200_2cmac_2pf_rdma` bitstream:

1. **ERNIC AXI-Lite crossbar windows too small.** Current 256 KB; PG332 v4.3 Table 9 requires 2 MB. GCSR (`ERNIC+0x100000`) and QCSR (`ERNIC+0x180000`) are physically unreachable. Confirmed empirically by `phase0c_pd_table.c` — writes to `BAR2+0x220000` landed in MR-table PD entry 512, not XRNICCONF.
2. **QDMA has no AXI-MM bridges.** `en_axi_mm_qdma {false}` in the QDMA TCL config means (a) `axi_sys_mem_mux_*` dead-ends at the top-level (host can't reach ERNIC output), and (b) no host→DDR4 staging path for source/destination buffers.
3. **BAR2 too small for full address map.** Currently 4 MB; with Task A's 16 MB layout (CMS preserved at `0x300000`, ERNICs moved to `0x800000`/`0xA00000`) BAR2 needs 16 MB.

Plus two software-level consequences:
4. **libreconic `reconic_reg.h` offsets are for ERNIC v4.0.** Our IP is v4.2 (`rdma_core.tcl:19`). GCSR and QCSR moved. Every register macro in `reconic_reg.h` at `RN_RDMA_BASE_ADDRESS + 0x02XXXX` or `+ 0x22XXX` is wrong.
5. **Driver `SHELL_END` needs bump** from `0x400000` → `0x800000` (trivial, already tracked).

## Pre-rebuild tasks (do before touching TCL)

These three tasks nail down decisions that propagate through every later file change. Skipping them = rebuild wasted.

### Pre-rebuild Task A — Layout decision: 16 MB BAR, CMS stays

**Driver audit result (2026-04-16)**: `open-nic-driver/hwmon/xmc.c` has CMS/XMC register offsets hardcoded:

| File:line | Hardcoded offset | Purpose |
|---|---|---|
| `hwmon/xmc.c:4412,4415` | `hw->addr + 0x320000` | CMS status register poke |
| `hwmon/xmc.c:4437` | `hw->addr + 0x328000` | XMC `base_addrs[i]` root |
| `onic_register.h:33` | comment "CMS register space, 0x320000 to 0x330000" | SHELL_END documentation |

Moving CMS from `0x300000` → `0x080000` (the original 8 MB layout proposed in Item 1) breaks hwmon. 3-line patch, but risks: CMS firmware may have baked-in BAR offset assumptions, xmc.c has 4000+ lines with further offsets we haven't fully audited, and any future Xilinx CMS/XOCL update lands on the existing `0x3XXXXX` assumption.

**Decision: 16 MB BAR2, keep CMS at `0x300000`. Zero driver impact.**

**Final layout** (supersedes Item 1's 8 MB layout):

| Addr | Size | Slave | Change from current |
|---|---|---|---|
| `0x000000–0x01FFFF` | ~128 KB | system regs (config/QDMA0-1/CMAC0-1/adapters/sysmon/PTP) | **unchanged** |
| `0x300000` | 256 KB | CMS | **unchanged** |
| `0x340000` | 4 KB | QSPI | **unchanged** |
| `0x400000` | 1 MB | BOX0 @ 250 MHz | **unchanged** (stays where RDMA build put it) |
| `0x500000` | 1 MB | BOX1 @ 322 MHz | **unchanged** |
| **`0x800000–0x9FFFFF`** | **2 MB** | **ERNIC0** | moved from `0x200000`, expanded from 256 KB |
| **`0xA00000–0xBFFFFF`** | **2 MB** | **ERNIC1** | moved from `0x600000`, expanded from 256 KB |
| BAR2 size | 16 MB | — | was 4 MB (`pf0_bar2_size_qdma {16}`) |

**Only M13 and M14 in the crossbar TCL change.** Every other slave keeps its address. Driver is 100% untouched except `SHELL_END 0x400000 → 0x1000000` in `onic_register.h`.

**Sub-consequences for the plan:**
- Item 1's TCL block is trimmed down (no CMS/QSPI moves, no BOX0/BOX1 moves).
- `libreconic/reconic_reg.h`: `RN_RDMA_BASE_ADDRESS 0x00200000 → 0x00800000`, `RN_RDMA_1_BASE_ADDRESS 0x00600000 → 0x00A00000`, `RN_RDMA_PORT_DELTA 0x00400000 → 0x00200000`, `RN_SCR_MAP_SIZE 0x00800000 → 0x01000000`.
- Driver `SHELL_END` bumps to `0x1000000` (16 MB) not `0x800000`.

### Pre-rebuild Task B — Address-tag spreadsheet

Pins down how every AXI flow in the design is addressed so the crossbars route as intended. Confirms no two masters fight for the same region.

**Traffic flows:**

| # | Traffic | Source | AXI address written at source | Routes through (in order) | Lands at |
|---|---|---|---|---|---|
| 1 | Host → ERNIC CSRs | PCIe BAR2 | `{BAR2_base} + 0x800000` (ERNIC0) or `0xA00000` (ERNIC1) | QDMA AXI-Lite master → `system_config_axi_crossbar` M13 or M14 | ERNIC AXI-Lite slave (2 MB window) |
| 2 | Host → QDMA bridge-config CSRs (AXIB BDF tables etc.) | PCIe BAR2 | `{BAR2_base} + 0x014000` (must verify — see Item 5 below) | `system_config_axi_crossbar` M07 (QDMA#1 CSR window `0x012000–0x016FFF`) | QDMA IP bridge CSR space |
| 3 | Host → DDR4 staging | PCIe BAR4 (new) | `{BAR4_base} + ddr_offset` | QDMA `m_axi_bridge` (PCIe→AXI) → `dev_mem_4to1` S00 → DDR4 MIG | DDR4 (34-bit addr) |
| 4 | ERNIC → DDR4 (WQE/SQ/CQ/data buffers) | ERNIC 5 AXI masters | `0xA350_0000_0000_0000 + ddr_offset` (tag from PG332) | `sys_mem_5to2` (per-ERNIC) M01 → `dev_mem_4to1` S02 (ERNIC0) or S03 (ERNIC1) → DDR4 MIG | DDR4 (34-bit addr) |
| 5 | ERNIC → host memory (optional, CQEs if not in DDR4) | ERNIC 5 AXI masters | `0x0000_0000_XXXXXXXX` (untagged, routes to M00 of 5-to-2) | `sys_mem_5to2` M00 → `sys_mem_2to1_mux` → QDMA `s_axib` (AXI→PCIe) → host physical addr (via QDMA AXIB BDF table) | Host DRAM |
| 6 | Compute logic → DDR4 (unused in our design) | `axi_compute_logic_*` master from each ERNIC subsystem | arbitrary | `dev_mem_4to1` S01 → DDR4 MIG | DDR4 |

**Key decisions:**

1. **QDMA bridge slave BAR = BAR4** (standard Xilinx choice; BAR0 stays MSIX, BAR2 stays AXI-Lite CSRs). TCL param `CONFIG.pf0_bar4_size_qdma` — size it to cover the DDR4 region you want to stage through. 256 MB is generous; 64 MB is probably sufficient for first bring-up.

2. **QDMA `axibar_highaddr_0`** (from RecoNIC): `0x000000FFFFFFFFFF` means a 40-bit AXI window. The `pciebar2axibar` config sets the base; pick `0x0000_0000_0000_0000` so bridge-translated addresses enter `dev_mem_4to1` S00 untagged (goes straight to DDR4 via M00). Then DDR4 MIG sees the low 34 bits of whatever BAR4 offset was written.

3. **ERNIC→DDR4 tag `0xA350...`** is established by the 5-to-2 crossbar (`sys_mem_5to2_axi_crossbar.tcl:48`). ERNIC must program its internal buffer base addresses (DATBUFBA, SQBAMSB, RQBAMSB, CQBAMSB) with the `0xA350_0000_XX_XXXX_XXXX` prefix. libreconic currently sets MSB to the hugepage physical address (untagged); **needs rewrite** to emit the DDR4 tag. Flag this for Item 5.

4. **S00 in `dev_mem_4to1` is already exposed** (from `axi_interconnect_to_dev_mem.sv:34`). `open_nic_shell.sv:3199-3211` currently ties S00 to zero — replace that tie-off with the wiring to QDMA `m_axi_bridge_*`.

5. **No two masters present conflicting addresses to the same slave.** Verified: flows #3 (host→DDR4) and #4 (ERNIC→DDR4) both terminate at DDR4 MIG but enter via different slave ports of the dev_mem crossbar. Flow #5 (ERNIC→host) uses the M00 tag (`0x0`) of the 5-to-2 crossbar which routes to the separate sys_mem_mux path, not DDR4.

**Validation commands (post-rebuild):**
- `lspci -vv -s 82:00.0 | grep Region` should show 4 regions: Region 0 (256 KB, MSIX/unused), Region 2 (16 MB, AXI-Lite), Region 4 (64 MB or 256 MB, bridge).
- Host→DDR4 round-trip: mmap BAR4, write sentinel, use QDMA's C2H to read it back (or vice versa).
- ERNIC→DDR4 verification waits for Phase 2.

### Pre-rebuild Task C — MIG calibration status register

**Goal**: Expose DDR4 MIG's `c0_init_calib_complete` signal to host via an AXI-Lite readable status register, so pre-Phase-1 we can confirm DDR4 is alive before trusting anything downstream.

**Proposed register**: add one word to the system_config block at offset `0x00020` (inside the existing 4 KB system-config slave at `0x000000`). 1 bit in use: `[0] = ddr4_init_calib_complete`. Default 0; sets to 1 when MIG finishes calibration.

**Implementation**:
- `src/system_config/system_config.sv`: add an input port `input wire c0_init_calib_complete`. Add a new read-only register at address `0x20` that exposes this bit. Existing build-time/version regs are at `0x04/0x08` area; `0x20` is clear.
- `src/open_nic_shell.sv:3378+`: route `c0_init_calib_complete` (currently generated by the DDR4 MIG IP, or in the `else` branch set to `1'b1` for sim) into the `system_config` instance.
- `src/system_config/system_config_address_map.sv`: no changes (system_config stays at M00 `0x000000` with 4 KB window).

**Pre-flight check (post-rebuild, before Phase 1)**: 
```c
uint32_t calib = *(uint32_t *)(bar2_base + 0x20);
if (!(calib & 0x1)) { fprintf(stderr, "DDR4 NOT CALIBRATED — bail\n"); exit(1); }
```

**Why this matters for us specifically**: Phase 0's "XRNICCONF reads 0 / NUM_QP=0" misinterpretation was plausible-but-wrong because "MIG not calibrated → ERNIC held in reset → CSRs read 0" is a known failure mode. Future debugging saves a day if we can rule it out in 1 line.

**Cost**: ~15 lines RTL, one extra port on system_config, one register write in status.md's validation procedure. No timing/resource risk.

---

## Rebuild scope — 5 work items

All items must land in one rebuild cycle; partial landings don't produce a testable bitstream.

### Item 1: Expand ERNIC crossbar windows (16 MB layout per Task A)

**File**: `src/system_config/vivado_ip/system_config_axi_crossbar.tcl` (RDMA build branch, lines 64-74)

Only M13/M14 change. Everything else stays unchanged from the current RDMA build — BOX0/BOX1/CMS/QSPI keep their existing addresses.

**Current** (RDMA build path, lines 64-74 in TCL):
```tcl
CONFIG.M08_A00_BASE_ADDR {0x0000000000500000}     ;# BOX1 — unchanged
CONFIG.M09_A00_BASE_ADDR {0x0000000000400000}     ;# BOX0 — unchanged
CONFIG.M13_A00_BASE_ADDR {0x0000000000200000}     ;# ERNIC0 — MOVES
CONFIG.M13_A00_ADDR_WIDTH {18}                    ;# 256 KB — WRONG
CONFIG.M14_A00_BASE_ADDR {0x0000000000600000}     ;# ERNIC1 — MOVES
CONFIG.M14_A00_ADDR_WIDTH {18}                    ;# 256 KB — WRONG
```

**Target**:
```tcl
set_property -dict {
    CONFIG.NUM_MI {15}
    CONFIG.M08_A00_BASE_ADDR  {0x0000000000500000}   ;# BOX1 — unchanged
    CONFIG.M09_A00_BASE_ADDR  {0x0000000000400000}   ;# BOX0 — unchanged
    CONFIG.M13_A00_BASE_ADDR  {0x0000000000800000}   ;# ERNIC0 — moved (was 0x200000)
    CONFIG.M13_A00_ADDR_WIDTH {21}                   ;# 2 MB (PG332 Tbl 9) — was 18
    CONFIG.M14_A00_BASE_ADDR  {0x0000000000A00000}   ;# ERNIC1 — moved (was 0x600000)
    CONFIG.M14_A00_ADDR_WIDTH {21}                   ;# 2 MB — was 18
} [get_ips $axi_crossbar]
```

M10 (CMS @ `0x300000`), M11 (QSPI @ `0x340000`), and the base block (M00-M07, M12) keep their existing definitions from lines 20-60 of the TCL file — no override needed in the RDMA branch. Compared to the previous plan draft this is 2 lines of real change (M13/M14 base+width) plus dropping 4 lines of unnecessary moves.

**Side files that must mirror:**

- `src/system_config/system_config_address_map.sv` — update the RDMA-branch block comments (lines 51-84 per earlier audit): ERNIC0 `0x200000` → `0x800000`, ERNIC1 `0x600000` → `0xA00000`. Also update the `localparam C_RDMA0_BASE_ADDR`/`C_RDMA1_BASE_ADDR` values (around line 362-363). Address widths on those localparams go `20 → 21` bits.
- `agent/reconic_integration/status.md` address map table — update ERNIC rows.

### Item 2: Enable QDMA AXI-MM bridges + bump BAR2

**File**: `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`

**Diff from current (`|`) vs RecoNIC reference (`|`)**:

| Key | Current | Target (from `RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`) |
|---|---|---|
| `CONFIG.en_axi_mm_qdma` | `false` | `true` |
| `CONFIG.en_bridge_slv` | (not set) | `true` |
| `CONFIG.dma_intf_sel_qdma` | `AXI_Stream_with_Completion` | `AXI_MM_and_AXI_Stream_with_Completion` |
| `CONFIG.axibar_highaddr_0` | (not set) | `0x000000FFFFFFFFFF` |
| `CONFIG.axibar_notranslate` | (not set) | `false` |
| `CONFIG.vdm_en` | (not set) | `1` |
| `CONFIG.csr_axilite_slave` | (not set) | `true` |
| `CONFIG.en_gt_selection` | (not set) | `true` |
| `CONFIG.dma_reset_source_sel` | `PCIe_User_Reset` | `Phy_Ready` |
| `CONFIG.pf0_bar2_size_qdma` | `4` (MB) | **`16`** (Task A — covers ERNIC1 at `0xA00000`+`2MB`) |
| `CONFIG.pf1_bar2_size_qdma` | `4` | `16` |
| `CONFIG.pf2_bar2_size_qdma` | `4` | `16` |
| `CONFIG.pf3_bar2_size_qdma` | `4` | `16` |
| `CONFIG.pf0_bar4_size_qdma` | (not set) | **`64`** (new; QDMA bridge BAR for host→DDR4 staging; Task B) |
| `CONFIG.pf0_bar4_scale_qdma` | (not set) | `Megabytes` |

The full replacement block can be copied from RecoNIC's reference (cross-check `PF[0-3]_MSIX_CAP_TABLE_SIZE_qdma` values — RecoNIC uses `009`/`008`, we have `01F` for higher queue-vector counts; keep our values).

### Item 3: Wire the new QDMA bridge ports at top-level

**File**: `src/open_nic_shell.sv`

**3a — Replace the dead-end stub at lines 3384-3388** (`// Tie off sys_mem mux → QDMA bridge path`):
```systemverilog
// ERNIC → PCIe: axi_sys_mem_mux drives the QDMA AXI slave bridge
// (AXI-MM → PCIe host). Connection to qdma_subsystem.s_axib.
```
And actually wire `axi_sys_mem_mux_*` to the `s_axib_*` port set on `qdma_subsystem` (see Item 4 for port names).

**3b — Wire QDMA's `m_axi_bridge_*` (PCIe → AXI master) into the `dev_mem` 4-to-1 crossbar** so the host can stage source/destination buffers into DDR4. This adds a 4th master (or replaces one of the three current masters) into `axi_interconnect_to_dev_mem_inst`. The `dev_mem_4to1_axi_crossbar.tcl` IP already supports 4 slave ports — verify current slot assignments and assign one to QDMA.

### Item 4: `qdma_subsystem.sv` — expose bridge ports

**File**: `src/qdma_subsystem/qdma_subsystem.sv` (currently 888 lines, no `s_axib` or `m_axi_bridge` references)

Add port declarations for the QDMA IP's slave bridge and master bridge interfaces, and forward them through the wrapper. Reference the RecoNIC version of the same file for exact port list (standard AXI4 64-bit addr, 512-bit data; ports named `s_axib_aw*`, `s_axib_w*`, `s_axib_b*`, `s_axib_ar*`, `s_axib_r*` and `m_axi_bridge_*` similarly).

### Item 5: Rewrite `libreconic/reconic_reg.h` against PG332 v4.3

**File**: `/home/alex/mpi-shfs/fpga/libreconic/reconic_reg.h` (currently uses ERNIC v4.0 offsets and old layout bases)

**Base address changes** (from Task A decision):
- `RN_RDMA_BASE_ADDRESS`:    `0x00200000` → **`0x00800000`** (ERNIC0 new location)
- `RN_RDMA_1_BASE_ADDRESS`:  `0x00600000` → **`0x00A00000`** (ERNIC1 new location)
- `RN_RDMA_PORT_DELTA`:      `0x00400000` → **`0x00200000`** (new delta between ports)
- `RN_SCR_MAP_SIZE`:         `0x00800000` → **`0x01000000`** (16 MB BAR)
- `RN_PC_BASE_ADDRESS` (BOX0): stays at `0x00400000`

**DDR4 address tag for ERNIC buffer programming** (from Task B):
All register offsets programming DDR4-resident buffers (DATBUFBA/MSB, SQBAi/MSBi, RQBAi/MSBi, CQBAi/MSBi, ERRBUFBA/MSB) must be written with the tag `0xA350_0000_XXXX_XXXX`. This means the *_MSB registers get `0xA350_0000` in their high bits plus any DDR4 offset bits above bit 32. Current libreconic sets these to hugepage physical address MSB (untagged) — needs rewrite. Alternatively, define:
```c
#define DEV_MEM_AXI_TAG_MSB   0xA3500000u
```
and OR it into every MSB write.

**Key v4.3 register offset migrations** (relative to ERNIC AXI-Lite slave base):

| Register | Old (v4.0) | New (v4.3) |
|---|---|---|
| XRNICCONF | `+0x020000` | **`+0x100000`** |
| XRNICADCONF | `+0x020004` | **`+0x100004`** |
| MACXADDLSB | `+0x020010` | **`+0x100010`** |
| MACXADDMSB | `+0x020014` | **`+0x100014`** |
| IPv6XADD1..4 | `+0x020020..2C` | **`+0x100020..2C`** |
| REQERRBUFBA | `+0x020060` | **`+0x100060`** |
| IPV4XADD | `+0x020070` | **`+0x100070`** |
| FATALERRBUFBA | `+0x020088` | **`+0x100088`** |
| DATBUFBA / MSB | `+0x0200A0/A4` | **`+0x1000A0/A4`** |
| RESPERRBUFBA / MSB | `+0x0200B0/B4` | **`+0x1000B0/B4`** |
| RQBAi | `+0x022008 + (i-1)*0x100` | **`+0x180008 + (i-1)*0x100`** |
| SQBAi | `+0x022010 + (i-1)*0x100` | **`+0x180010 + (i-1)*0x100`** |
| CQBAi | `+0x022018 + (i-1)*0x100` | **`+0x180018 + (i-1)*0x100`** |
| RQBAMSBi | — (new in v4.3?) | **`+0x1800C0 + (i-1)*0x100`** |
| SQBAMSBi | — | **`+0x1800C8 + (i-1)*0x100`** |
| CQBAMSBi | — | **`+0x1800D0 + (i-1)*0x100`** |

**Additional attention**:
- PG332 v4.3 splits 64-bit addresses into LSB + MSB registers. Some v4.0 code assumed 32-bit addressing. Audit libreconic for every place that programs a 64-bit base address and ensure the MSB register is also written (and tagged with `0xA3500000` for DDR4).
- `RN_PC_BASE_ADDRESS = 0x400000` (BOX0) is unchanged under Task A's layout.
- `config_rn_dev_axib_bdf` writes to `RN_QDMA_CSR_BASE_ADDRESS = 0x00014000`. After Item 2 enables the QDMA slave bridge, verify that bridge-config CSRs are actually exposed at offset `0x2420+` inside QDMA subsystem #1's 20 KB window (`0x012000–0x016FFF`). If RecoNIC's QDMA wrapper layout differs from ours, `RN_QDMA_CSR_BASE_ADDRESS` needs updating.

**Validation**: after rewriting, `rdma_test/phase1_csr_bringup.c` should reach XRNICCONF and round-trip it with NUM_QP=0x20 in [15:8].

### Item 6 (trivial): Driver BAR range

**File**: `open-nic-driver/onic_register.h`

```c
#define SHELL_END   0x1000000   /* 16 MB per Task A layout; was 0x400000 */
```

## Reference: working donor design

RecoNIC's `base_nics/open-nic-shell/` has items 1-4 already implemented. Diff-port rather than re-derive:

- `RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` — full QDMA config for item 2
- `RecoNIC/base_nics/open-nic-shell/src/qdma_subsystem/qdma_subsystem.sv` — `s_axib` + `m_axi_bridge` ports for item 4
- `RecoNIC/base_nics/open-nic-shell/src/open_nic_shell.sv` — the wiring for item 3 (specifically the `rdma_subsystem_wrapper` → `qdma_subsystem` sys_mem path and the `qdma_subsystem` → `dev_mem_crossbar` host-staging path)

Note: RecoNIC's layout has a **single** ERNIC at `0x40000`, not dual ERNICs at `0x200000`/`0x400000`. Their TCL gives only **one** `M*_A00_BASE_ADDR` for ERNIC. Our layout is dual-ERNIC and requires per-instance base addresses — preserve our dual arrangement; copy only the QDMA bridge config.

## Validation matrix after rebuild

After `./script/build_2cmac_rdma.sh` produces a new bitstream and driver loads:

| Check | Command | Expected |
|---|---|---|
| BAR2 size | `lspci -vv -s 82:00.0 \| grep "Region 2"` | 8 MB |
| Driver probe | `dmesg \| grep onic` | existing behavior + new ERNIC probe if item 6 adds it |
| ERNIC GCSR reachable | `sudo ./phase0_ernic_probe 0000:82:00.0` **with offsets updated to GCSR=0x100000** | XRNICCONF NUM_QP[15:8]=0x20 (32), writable round-trip on MAC/IPv4 |
| Phase 1 CSR bring-up | `sudo ./phase1_csr_bringup` (after libreconic rewrite in item 5) | completes through `allocate_rdma_qp` without hang; CSRs round-trip |
| Phase 2 RDMA WRITE loopback | (new program) | CQE posted, data arrives at remote DDR4 buffer |

## Risk register

| Risk | Mitigation |
|---|---|
| Vivado can't route the 15-port crossbar with 2 MB per ERNIC window | Fallback: compress other slaves; or move ERNIC0 to `0x800000+` with BAR2=16 MB |
| QDMA AXI-MM bridge requires `dsc_byp_mode` change that breaks existing ST path | Compare to RecoNIC's config, which keeps ST working alongside MM |
| ERNIC v4.2 PG332 register map we're using is actually v4.3 — minor offset differences exist between .2 and .3 | Before Phase 1, run a GCSR-sweep probe at the new offsets; if XRNICCONF[15:8] ≠ 0x20, bisect against PG332 v4.2 (check /home/alex/Downloads/ for v4.2-specific docs) |
| RecoNIC's `config_rn_dev_axib_bdf` assumes QDMA CSRs at specific BAR offsets that differ from our shell | Compare `RN_QDMA_CSR_BASE_ADDRESS` (0x14000 in RecoNIC) against our actual QDMA subsystem CSR base. Update or skip. |
| MR-table entries > 1023 still unreachable even with 2 MB window | 2 MB = 0x200000, / 0x100 stride = 8192 entries. Our IP has `C_NUM_QP=32` and probably `C_NUM_MR=2048` — fits in 0.5 MB. OK. |

## Estimated effort

- Items 1-4 (RTL): 1-2 days. Mostly diff-port from RecoNIC, careful TCL params, re-route system_config address map.
- Item 5 (libreconic rewrite): 1 day. Every register macro and every call site that assumes 32-bit addresses.
- First synthesis + impl + bitstream: 4-8 h of Vivado time.
- Phase 1 validation: 2-4 h.
- Total: ~4 days before Phase 2 RDMA WRITE is testable.

## Out of scope (for this rebuild)

- Kernel-side RDMA probe (the ~40-line `onic_hardware.c` version print) — can land independently either before or after the rebuild.
- Ib_device registration (true RDMA verbs) — separate project; not needed for internal testing via libreconic.
- Interoperability with ConnectX or other standard RoCE NICs — validate loopback first.
