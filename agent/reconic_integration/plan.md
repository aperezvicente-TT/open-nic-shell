# RecoNIC Integration onto Open-NIC-Shell: Step-by-Step Plan (Dual RDMA)

## Goal

Integrate **two** Xilinx ERNIC engines (hardware RoCEv2 RDMA) — one per CMAC port — plus packet classification + compute offload from the RecoNIC project into the standalone open-nic-shell, preserving the existing NIC functionality and plugin architecture.

The RecoNIC reference design uses dual RDMA engines (`rdma_subsystem` + `rdma_subsystem_1`), each bound to its own CMAC/QSFP port. This plan follows that architecture.

## Reference Material

- **RecoNIC source:** `/home/alex/fpga-wksp/fpga-nic/RecoNIC-main/`
- **RecoNIC architecture docs:** `RecoNIC-main/docs/rdma-rocev2-p4-integration/` (01-09 series)
- **Prior analysis:** `open-nic-shell/agent/openic_rdma_ernic.md`
- **Prior detailed plan:** `RecoNIC-main/docs/ernic-opennic-integration-plan.md`
- **Reference dual-RDMA top-level:** `RecoNIC/base_nics/open-nic-shell/src/open_nic_shell.sv` (lines 1917-3878)
- **Reference dual-RDMA build:** `RecoNIC/base_nics/open-nic-shell/build/au200_dual_rdma/`

## Key Constraint

**ERNIC cannot be a pure plugin.** The standard plugin API only exposes AXI-Stream (512-bit) + AXI-Lite (32-bit). Each ERNIC additionally requires:
1. AXI4-Full memory masters (64-bit addr, 512-bit data) routed to DDR4 — **6 masters per engine, 12 total**
2. A dedicated 2MB AXI-Lite BAR2 region for QP registers — **two regions: 0x200000 and 0x600000**
3. Sideband signals (doorbell, IETH/IMMDT, QP status) — **~35 signals per box_250mhz instance**

**Approach:** Hybrid -- `ifdef __RDMA_ENABLED__` guarded shell modifications + RDMA plugin for all datapath logic. Non-RDMA builds are unaffected.

---

## Dependency Graph

```
Step 1 (DDR4 ctrl) ──────────────┐
Step 2a (ERNIC0 subsystem) ──────┤
Step 2b (ERNIC1 subsystem) ──────┤
Step 3 (AXI fabric: 5:2×2 + ────┼──> Step 5 (top-level wiring, ──> Step 8 (build system)
        4:1 + 2:1 + CDC)        │     dual instantiation)              |
Step 4 (12-port addr map) ──────┘         |                       Step 9 (verification)
                                    Step 6 (box ports, ×2)
                                          |
                                    Step 7 (RDMA plugin + classifiers, ×2)
```

Steps 1, 2a, 2b, 3, 4 are independent (can be done in parallel).
Step 2a and 2b are identical except for IP naming — do 2a first, copy for 2b.
Step 5 depends on all of 1-4.
Step 7 needs Step 6.
Step 8 ties everything together.
Step 9 validates both RDMA engines independently.

---

## Step 1: DDR4 Memory Controller (Board-Specific)

**Why:** ERNIC stores RDMA payloads, WQEs, CQEs, and retry buffers in DDR4. Without this there is nowhere to put RDMA data.

**Source reference:** `RecoNIC/base_nics/open-nic-shell/src/mem_ctrl/`

### Files to create

| File | Source | Notes |
|------|--------|-------|
| `src/mem_ctrl/au250/vivado_ip/dev_mem_ddr4_controller_au250.tcl` | Copy from RecoNIC `base_nics/open-nic-shell/src/mem_ctrl/` | MIG IP for AU250 DDR4 (64-bit, 2400 MT/s) |
| `src/mem_ctrl/au250/vivado_ip/vivado_ip.tcl` | Copy from RecoNIC | IP discovery wrapper (sources the DDR4 TCL) |
| `constr/au250/pins_ddr4.xdc` | Extract from RecoNIC patch | DDR4 signal pin assignments for AU250 |

### Files to modify

| File | Change | Lines |
|------|--------|-------|
| `script/build.tcl` | Add board-specific `mem_ctrl` directory lookup: `if {[string equal $module mem_ctrl]} { set module_dir ${module_dir}/${board} }` | ~4 |
| `constr/au250/general.xdc` | Add DDR4 MMCM placement constraint + `INTERNAL_VREF` for DDR4 banks | ~5 |

### Verification

```bash
# In Vivado TCL console:
source src/mem_ctrl/au250/vivado_ip/dev_mem_ddr4_controller_au250.tcl
# Should generate MIG IP without errors
```

---

## Step 2a: RDMA Subsystem 0 (ERNIC IP Wrapper — CMAC0/QSFP0)

**Why:** Wraps the first Xilinx ERNIC IP instance, aggregates its 6 AXI-MM master ports, and provides clean interfaces for the rest of the system.

**Source reference:** `RecoNIC/base_nics/open-nic-shell/src/rdma_subsystem/`

### Files to create

| File | Purpose |
|------|---------|
| `src/rdma_subsystem/rdma_subsystem.sv` | Instantiates `rdma_core` ERNIC IP, exposes 6 AXI-MM masters + AXI-Stream TX/RX + AXI-Lite control |
| `src/rdma_subsystem/rdma_subsystem_wrapper.sv` | Packet merge logic (RDMA TX + non-RoCE bypass), doorbell/sideband wiring |
| `src/rdma_subsystem/vivado_ip/rdma_core.tcl` | ERNIC IP creation script (v4.2, 32 QPs, 512-bit data, 64-bit addr) |
| `src/rdma_subsystem/vivado_ip/vivado_ip.tcl` | IP discovery wrapper |

## Step 2b: RDMA Subsystem 1 (ERNIC IP Wrapper — CMAC1/QSFP1)

**Why:** Second ERNIC instance for the second CMAC port. Functionally identical to ERNIC0, differs only in module/IP naming.

**Source reference:** `RecoNIC/base_nics/open-nic-shell/src/rdma_subsystem/rdma_subsystem_1.sv`, `rdma_subsystem_wrapper_1.sv`

### Files to create

| File | Purpose |
|------|---------|
| `src/rdma_subsystem/rdma_subsystem_1.sv` | Instantiates `rdma_core_1` ERNIC IP (identical config to rdma_core) |
| `src/rdma_subsystem/rdma_subsystem_wrapper_1.sv` | Same merge/sideband logic as wrapper.sv, references rdma_subsystem_1 |
| `src/rdma_subsystem/vivado_ip/rdma_core_1.tcl` | Second ERNIC IP creation script (same parameters as rdma_core.tcl, different IP name) |

### Key finding from reference

The two instances are **functionally identical** — same parameters (32 QPs, 512b data, 64b addr, ERNIC v4.2), same port interfaces. Only the module names and instantiated IP names differ. Create ERNIC0 first, then copy-and-rename for ERNIC1.

### ERNIC IP Configuration

```tcl
# Key parameters in rdma_core.tcl:
C_NUM_QP                       = 32      # 32 Queue Pairs
C_S_AXI_LITE_ADDR_WIDTH        = 32
C_M_AXI_ADDR_WIDTH             = 64      # Full physical address space
C_M_AXI_DATA_WIDTH             = 512     # Match OpenNIC data width
C_EN_DEBUG_PORTS               = 1
C_MAX_WR_RETRY_DATA_BUF_DEPTH  = 2048
C_EN_INITIATOR_LITE            = 1
```

### ERNIC AXI-MM Masters (6 ports, all 512b data / 64b addr)

| # | Port Name | Function |
|---|-----------|----------|
| 1 | `m_axi_rdma_send_write_payload_store` | Store incoming WRITE/SEND payloads |
| 2 | `m_axi_rdma_rsp_payload` | Store READ response data |
| 3 | `m_axi_qp_get_wqe` | Fetch Work Queue Elements from SQ |
| 4 | `m_axi_payload_to_retry_buf` | Buffer outgoing payloads for retransmission |
| 5 | `m_axi_pktgen_get_payload` | Fetch payload for outgoing packets |
| 6 | `m_axi_write_completion` | Write completion entries to CQ |

### Prerequisite

Xilinx ERNIC license. Verify:
```tcl
create_ip -name ernic -vendor xilinx.com -library ip -version 4.0
```

---

## Step 3: AXI Memory Interconnect Fabric (3-Tier Hierarchy)

**Why:** Two ERNICs produce 12 AXI-MM masters total. The reference design uses a 3-tier interconnect hierarchy — NOT a flat crossbar — to funnel all traffic through a single DDR4 controller with clock domain crossing.

**Source reference:** `RecoNIC/base_nics/open-nic-shell/src/utility/`

### Architecture (from reference `open_nic_shell.sv` lines 2535-3284)

```
ERNIC0 (5 AXI-MM masters)              ERNIC1 (5 AXI-MM masters)
  │ get_wqe                               │ get_wqe
  │ get_payload                           │ get_payload
  │ completion                            │ completion
  │ send_write_payload                    │ send_write_payload
  │ rsp_payload                           │ rsp_payload
  ▼                                       ▼
┌─────────────────────┐           ┌─────────────────────┐
│ 5:2 sys_mem crossbar│           │ 5:2 sys_mem crossbar│  ← Tier 1 (per-ERNIC)
│ (axi_interconnect_  │           │ (axi_interconnect_  │
│  to_sys_mem_inst)   │           │  to_sys_mem_1_inst) │
└──┬──────────┬───────┘           └──┬──────────┬───────┘
   │sys_mem   │to_dev                │sys_mem   │to_dev
   ▼          ▼                      ▼          ▼
┌──────────┐  │                ┌──────────┐    │
│ 2:1 mux  │  │                │          │    │
│(sys_mem_ │◄─┼────────────────┘          │    │       ← Tier 2 (merge)
│ mux_inst)│  │                           │    │
└──┬───────┘  │   ┌───────────────────────┘    │
   │          │   │                            │
   ▼          ▼   ▼                            ▼
 QDMA     ┌────────────────────────────────────────┐
 bridge   │  4:1 dev_mem crossbar                  │  ← Tier 3 (to DDR4)
          │  (axi_interconnect_to_dev_mem_inst)    │
          │  S00: QDMA_MM                          │
          │  S01: Compute Logic (box_250mhz_0)     │
          │  S02: sys_crossbar_0 → dev_mem path    │
          │  S03: sys_crossbar_1 → dev_mem path    │
          └──────────────┬─────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ AXI Clock Converter │  250 MHz → MIG clock
              └──────────┬──────────┘
                         ▼
              ┌─────────────────────┐
              │  DDR4 MIG (single)  │
              └─────────────────────┘
```

### Files to create

| File | Purpose |
|------|---------|
| `src/utility/axi_5to2_interconnect_to_sys_mem.sv` | ERNIC0: 5 AXI-MM masters → 2 outputs (sys_mem + dev_mem path) |
| `src/utility/axi_5to2_interconnect_to_sys_mem_1.sv` | ERNIC1: same as above, separate instance |
| `src/utility/axi_4to1_interconnect_to_dev_mem.sv` | Merges QDMA + Compute + 2× sys_crossbar outputs → single DDR4 |
| `src/utility/axi_2to1_interconnect_to_sys_mem.sv` | Merges PF0 + PF1 sys_mem outputs → QDMA bridge |
| `src/utility/vivado_ip/dev_mem_4to1_axi_crossbar.tcl` | 4:1 crossbar IP (512b data, 5-bit ID) |
| `src/utility/vivado_ip/sys_mem_5to2_axi_crossbar.tcl` | 5:2 crossbar IP (512b data, 5-bit ID) |
| `src/utility/vivado_ip/sys_mem_2to1_axi_crossbar.tcl` | 2:1 mux IP (512b data, 5-bit ID) |
| `src/utility/vivado_ip/axi_clock_converter_for_mem.tcl` | 250 MHz → MIG clock CDC |

### 4:1 dev_mem Crossbar Configuration (from reference `dev_mem_4to1_axi_crossbar.tcl`)

```
Slave ports:  4 (S00=QDMA_MM, S01=Compute, S02=sys_xbar_0, S03=sys_xbar_1)
Master ports: 1 (M00 → DDR4 via clock converter)
Data width:   512 bits
Addr width:   64 bits
Master ID width: 5 bits
Slave thread ID width: 3 bits each
Write acceptance: 8 per slave
Read acceptance:  8 per slave
Write issuing:    16 per master
Read issuing:     16 per master
```

### 5:2 sys_mem Crossbar Configuration (one per ERNIC)

```
Slave ports:  5 (get_wqe, get_payload, completion, send_write_payload, rsp_payload)
Master ports: 2 (M00 → sys_mem/QDMA bridge, M01 → dev_mem crossbar)
Data width:   512 bits
Addr width:   64 bits
ID width:     5 bits
```

---

## Step 4: System Address Map Expansion (12-Port Crossbar, Dual ERNIC)

**Why:** Two ERNIC instances each need a dedicated 2MB BAR2 register window. The existing address map must be expanded with two additional crossbar master ports.

**Source reference:** `RecoNIC/base_nics/open-nic-shell/src/system_config/`

### Files to modify

| File | Change | Lines |
|------|--------|-------|
| `src/system_config/system_config_address_map.sv` | Add `m_axil_rdma_*` and `m_axil_rdma_1_*` output ports (18 AXI-Lite signals each), add two RDMA slaves at 0x200000 and 0x600000 | ~160 |
| `src/system_config/system_config.sv` | Wire both RDMA AXI-Lite ports through to top level | ~40 |
| `src/system_config/vivado_ip/system_config_axi_crossbar.tcl` | Expand to 12 master ports (M00-M11), add M08=ERNIC0, M11=ERNIC1 | ~30 |

### Full Address Map (from reference crossbar TCL — 12 master ports)

```
Port  Address Range         Size   Module
----  ---------------------- -----  ------
M00   (unused)               -      -
M01   0x01000 - 0x05FFF      20KB   QDMA subsystem
M02   0x08000 - 0x0AFFF      12KB   CMAC subsystem #0
M03   0x0B000 - 0x0BFFF      4KB    Packet adapter #0
M04   0x0C000 - 0x0EFFF      12KB   CMAC subsystem #1
M05   0x0F000 - 0x0FFFF      4KB    Packet adapter #1
M06   0x10000 - 0x11FFF      8KB    System monitor
M07   0x14000 - 0x16FFF      12KB   QDMA AXI bridge CSR
M08   0x200000 - 0x3FFFFF    2MB    ERNIC0 (NEW — CMAC0/QSFP0)
M09   0x500000 - 0x5FFFFF    1MB    BOX1 @ 322MHz
M10   0x400000 - 0x4FFFFF    1MB    BOX0 @ 250MHz
M11   0x600000 - 0x7FFFFF    2MB    ERNIC1 (NEW — CMAC1/QSFP1)
```

Total BAR2 size grows from 4MB to **8MB** (0x800000).

### ERNIC Internal Register Layout (within each 2MB window)

```
Offset 0x000000 - 0x00001C:  Protection Domain Table (PDT)
Offset 0x100000 - 0x1002AC:  Global Control Status Registers (GCSR)
Offset 0x180000 - 0x1800D8:  Per-Queue Control Status Registers (QCSR)
```

Both ERNIC0 (@ 0x200000) and ERNIC1 (@ 0x600000) use the same internal layout. The system config crossbar strips the base address before forwarding to each ERNIC.

### Address Translation

```verilog
// ERNIC0: accesses to 0x200000-0x3FFFFF → ERNIC0 sees 0x000000-0x1FFFFF
axil_rdma_awaddr   = axil_awaddr - 0x200000;
// ERNIC1: accesses to 0x600000-0x7FFFFF → ERNIC1 sees 0x000000-0x1FFFFF
axil_rdma_1_awaddr = axil_awaddr - 0x600000;
```

### Impact

The reference design does NOT shift existing addresses — ERNIC0 and ERNIC1 fit in previously unused gaps. Existing register offsets for CMAC, QDMA, box, etc. are unchanged. Driver `SHELL_END` must be updated from 0x400000 to 0x800000.

---

## Step 5: Top-Level Shell Wiring (Dual RDMA)

**Why:** Connect DDR4 pins, both RDMA subsystems, the 3-tier memory fabric, and sideband wiring into the top-level module.

**Depends on:** Steps 1, 2a, 2b, 3, 4 (all must be complete).

### File to modify

`src/open_nic_shell.sv` -- ~800-1000 lines added, all guarded by `` `ifdef __RDMA_ENABLED__ ``

### What gets added (all conditional)

1. **DDR4 top-level I/O pins:**
   - `c0_ddr4_adr[16:0]`, `c0_ddr4_ba[1:0]`, `c0_ddr4_bg[1:0]`
   - `c0_ddr4_dq[71:0]`, `c0_ddr4_dqs_t/c[17:0]`, `c0_ddr4_dm_dbi_n[8:0]`
   - `c0_ddr4_ck_t/c`, `c0_ddr4_cke`, `c0_ddr4_cs_n`, `c0_ddr4_odt`, `c0_ddr4_act_n`, `c0_ddr4_reset_n`
   - `c0_sys_clk_p/n` (DDR4 reference clock)

2. **Instantiate `rdma_subsystem_wrapper` (ERNIC0, lines ~1919-2236 in reference):**
   - AXI-Lite: `axil_rdma_*` from `system_config` (BAR2 @ 0x200000)
   - AXI-Stream RX: `cmac2rdma_roce_axis_*` from box_250mhz_0 (classified RoCE packets)
   - AXI-Stream TX: `rdma2cmac_axis_*` to box_250mhz_0 (merged RDMA + non-RDMA)
   - AXI-MM: 5 named master groups → `axi_interconnect_to_sys_mem_inst`

3. **Instantiate `rdma_subsystem_wrapper_1` (ERNIC1, lines ~2239-2533 in reference):**
   - AXI-Lite: `axil_rdma_1_*` from `system_config` (BAR2 @ 0x600000)
   - AXI-Stream RX: `cmac2rdma_1_roce_axis_*` from box_250mhz_1
   - AXI-Stream TX: `rdma2cmac_1_axis_*` to box_250mhz_1
   - AXI-MM: 5 named master groups → `axi_interconnect_to_sys_mem_1_inst`

4. **Instantiate 3-tier memory fabric:**
   - `axi_interconnect_to_sys_mem_inst` — ERNIC0's 5:2 crossbar
   - `axi_interconnect_to_sys_mem_1_inst` — ERNIC1's 5:2 crossbar
   - `axi_sys_mem_mux_inst` — 2:1 merge (PF0 + PF1 sys_mem → QDMA bridge)
   - `axi_interconnect_to_dev_mem_inst` — 4:1 crossbar (QDMA + Compute + 2× sys_xbar → DDR4)
   - `axi_clock_converter_for_ddr_inst` — 250 MHz → MIG clock CDC

5. **Instantiate DDR4 controller:**
   - Single MIG instance (`ddr4_inst`) → DDR4 pins

6. **Extend both `box_250mhz` instantiations:**
   - `box_250mhz_0_inst`: wire RDMA0 sideband ports (~35 signals) + compute AXI-MM
   - `box_250mhz_1_inst`: wire RDMA1 sideband ports (~35 signals), **tie off** AXI-Lite registers (delegated to ERNIC1), **tie off** compute AXI-MM (only port 0 has compute)

### Key detail from reference

`box_250mhz_1_inst` has its AXI-Lite register interface **tied off** (awvalid=0, arvalid=0) because its register space is handled by `rdma_subsystem_1_inst` directly. Its compute logic AXI-MM is also tied off — only ERNIC0/box0 supports compute offload.

### Source reference

RecoNIC's `open_nic_shell.sv` lines 1917-3878 (dual instantiation pattern)

---

## Step 6: Extend box_250mhz Port List (×2 Instances)

**Why:** Each box_250mhz instance needs ~35 RDMA sideband ports to communicate with its respective RDMA subsystem. Both box_250mhz_0 and box_250mhz_1 get the same port additions.

**Depends on:** Step 5 (ports must exist at top level to wire into box).

### File to modify

`src/box_250mhz/box_250mhz.sv` -- ~100 lines added, guarded by `` `ifdef __RDMA_ENABLED__ ``

### New ports per box instance (all conditional, ~35 signals)

**RDMA AXI-Stream — RX path (CMAC → classifier → ERNIC):**
- `m_axis_user2rdma_roce_from_cmac_rx_tvalid/tdata[511:0]/tkeep[63:0]/tlast` — output
- `m_axis_user2rdma_roce_from_cmac_rx_tready` — input

**RDMA AXI-Stream — TX path (ERNIC → CMAC):**
- `s_axis_rdma2user_to_cmac_tx_tvalid/tdata[511:0]/tkeep[63:0]/tlast` — input
- `s_axis_rdma2user_to_cmac_tx_tready` — output

**RDMA AXI-Stream — non-RoCE path (QDMA → ERNIC TX merger):**
- `m_axis_user2rdma_from_qdma_tx_tvalid/tdata[511:0]/tkeep[63:0]/tlast` — output
- `m_axis_user2rdma_from_qdma_tx_tready` — input

**Immediate data sideband:**
- `s_axis_rdma2user_ieth_immdt_tdata[63:0]/tlast/tvalid` — input
- `s_axis_rdma2user_ieth_immdt_trdy` — output

**Doorbell/QP handshaking (SQ producer index):**
- `m_o_qp_sq_pidb_hndshk[15:0]` — output
- `m_o_qp_sq_pidb_wr_addr_hndshk[31:0]` — output
- `m_o_qp_sq_pidb_wr_valid_hndshk` — output
- `m_i_qp_sq_pidb_wr_rdy` — input

**Doorbell/QP handshaking (RQ consumer index):**
- `m_o_qp_rq_cidb_hndshk[15:0]` — output
- `m_o_qp_rq_cidb_wr_addr_hndshk[31:0]` — output
- `m_o_qp_rq_cidb_wr_valid_hndshk` — output
- `m_i_qp_rq_cidb_wr_rdy` — input

**Response handler (CQ doorbell):**
- `s_resp_hndler_i_send_cq_db_cnt_valid` — input
- `s_resp_hndler_i_send_cq_db_addr[9:0]` — input
- `s_resp_hndler_i_send_cq_db_cnt[31:0]` — input
- `s_resp_hndler_o_send_cq_db_rdy` — output

**RX packet handler (RQ doorbell):**
- `s_rx_pkt_hndler_i_rq_db_data_valid` — input
- `s_rx_pkt_hndler_i_rq_db_addr[9:0]` — input
- `s_rx_pkt_hndler_i_rq_db_data[31:0]` — input
- `s_rx_pkt_hndler_o_rq_db_rdy` — output

### Dual-box wiring at top level

At top level, signals are distinguished by suffix:
- box_250mhz_0: `cmac2rdma_roce_axis_*`, `rdma2cmac_axis_*`, `resp_hndler_o_*`
- box_250mhz_1: `cmac2rdma_1_roce_axis_*`, `rdma2cmac_1_axis_*`, `resp_hndler_1_o_*`

### Note on doorbell signals

The reference design has TODO comments (lines 298-311 in rdma_onic_plugin.sv) — doorbell signals are currently **tied to constants**. They should be wired through for full QP notification support.

### Source reference

`RecoNIC/base_nics/open-nic-shell/src/box_250mhz/box_250mhz.sv`, `RecoNIC/shell/plugs/rdma_onic_plugin/box_250mhz.sv` (313 lines)

---

## Step 7: Create RDMA Plugin

**Why:** All datapath logic (packet classification, RoCEv2 steering, TX merge, register decode) lives here, keeping the shell modifications minimal.

**Depends on:** Step 6 (box_250mhz must expose RDMA sideband ports).

### Plugin directory structure

```
plugin/rdma_onic/
  build_box_250mhz.tcl                  # Sources plugin RTL + classifier IP
  build_box_322mhz.tcl                  # Copy from p2p (322MHz box unchanged)
  p2p_322mhz.sv                         # Copy from p2p (passthrough)
  rdma_onic_plugin.sv                   # Top: addr map + reconic shell
  reconic.sv                            # Packet classification + filter + buffering
  reconic_address_map.sv                # Plugin-internal AXI-Lite 1-to-3 crossbar
  rn_reg_control.sv                     # Statistics registers (RoCE/non-RoCE counters)

  packet_classification/
    packet_classifier_wrapper.sv        # Unified wrapper: selects backend via ifdef
    packet_filter.sv                    # is_rdma demux (RoCEv2 vs non-RDMA)

    p4/                                 # Backend 1: VitisNetP4 (requires license)
      packet_parser.p4                  # P4 source (263-bit metadata extraction)

    rtl/                                # Backend 2: Fixed-function RTL (no license)
      packet_classifier_rtl.sv          # EtherType->IPv4->UDP:4791->BTH parser

    hls/                                # Backend 3: Vitis HLS (free)
      packet_classifier_hls.cpp         # C/C++ classifier
      packet_classifier_hls.h           # AXI-Stream types + metadata struct
      run_hls.tcl                       # Vitis HLS synthesis script

  vivado_ip/
    reconic_axil_crossbar.tcl           # 1-to-3 AXI-Lite crossbar
    packet_parser.tcl                   # VitisNetP4 IP (only for P4 backend)

  box_250mhz/
    user_plugin_250mhz_inst.vh          # Instantiates rdma_onic_plugin + sideband wiring
    box_250mhz_address_map_inst.vh      # Register decode instantiation
    box_250mhz_address_map.v            # Address decoder RTL
    box_250mhz_axi_crossbar.tcl         # Plugin AXI crossbar IP

  box_322mhz/                           # Passthrough (copy from p2p)
    user_plugin_322mhz_inst.vh
    box_322mhz_address_map_inst.vh
    box_322mhz_address_map.v
    box_322mhz_axi_crossbar.tcl
```

### Classifier backends (build-time switchable)

| Backend | Define | License | Latency | Flexibility |
|---------|--------|---------|---------|-------------|
| VitisNetP4 (P4) | `__CLASSIFIER_P4__` | VitisNetP4 | 23 cycles (92 ns) | Runtime table updates |
| Fixed-function RTL | `__CLASSIFIER_RTL__` | None | ~5 cycles (20 ns) | Recompile to change |
| Vitis HLS (C/C++) | `__CLASSIFIER_HLS__` | Vitis HLS (free) | ~10-15 cycles | Recompile to change |

All three produce the same output interface:
- `is_rdma` (1-bit): RoCEv2 classification flag
- Metadata bus: opcode, PSN, MSN, r_key, DMA length, IP src/dst, UDP ports
- 512-bit AXI-Stream passthrough (packet data unchanged)

### Core datapath (per box_250mhz instance — runs independently on each CMAC port)

```
RX: CMAC_N -> xpm_fifo_sync (512 entries) -> classifier_N -> is_rdma=1 to ERNIC_N
                                                           -> is_rdma=0 to QDMA C2H

TX: ERNIC_N TX ----+
    QDMA H2C ------+--> merge arbiter --> CMAC_N TX adapter
```

Each box_250mhz instance (0 and 1) contains its own independent classifier and merge arbiter. The plugin RTL is instantiated once per box, parameterized by PORT_ID.

### Source files to copy from

| Plugin file | RecoNIC source |
|-------------|---------------|
| `rdma_onic_plugin.sv` | `shell/plugs/rdma_onic_plugin/rdma_onic_plugin.sv` (434 lines) |
| `reconic.sv` | `shell/top/reconic.sv` |
| `reconic_address_map.sv` | `shell/plugs/rdma_onic_plugin/reconic_address_map.sv` (236 lines) |
| `packet_filter.sv` | `shell/packet_classification/packet_filter.sv` (476 lines) |
| `packet_parser.p4` | `shell/packet_classification/packet_parser.p4` (451 lines) |
| `rn_reg_control.sv` | `shell/utilities/rn_reg_control.sv` |
| IP TCL scripts | `shell/plugs/rdma_onic_plugin/vivado_ip/*.tcl` |

### Plugin register space (within box_250mhz AXI-Lite window)

```
Offset 0x0000: Table control (P4 classifier runtime, if P4 backend)
Offset 0x2000: RecoNIC shell registers (rn_reg_control: version, counters, timer)
Offset 0x3000: Compute logic registers (if compute offload enabled)
```

---

## Step 8: Build System Integration

**Why:** Wire `__RDMA_ENABLED__` and classifier selection into the Vivado build flow. Must enumerate both `rdma_subsystem` and `rdma_subsystem_1` modules.

**Depends on:** All prior steps (this is the final assembly).

### Files to modify

| File | Change | Lines |
|------|--------|-------|
| `script/build.tcl` | Add `-rdma {0,1}` and `-classifier {p4,rtl,hls}` flags; set verilog defines; add `mem_ctrl`, `rdma_subsystem` to module list when `-rdma 1`; source both `rdma_core.tcl` and `rdma_core_1.tcl` | ~40 |
| `script/board_settings/au250.tcl` | Add DDR4-specific parameters | ~5 |

### Key build parameters for dual RDMA (from reference `DESIGN_PARAMETERS`)

```
-num_cmac_port 2        # 2 CMAC ports (both active)
-num_phys_func 2        # 2 physical functions (one per RDMA port)
-rdma 1                 # Enable RDMA subsystems
-classifier rtl         # Classifier backend (rtl/p4/hls)
```

### Build commands

**AU250 dual RDMA with RTL classifier (no extra licenses):**
```bash
cd open-nic-shell/script
vivado -mode batch -source build.tcl -tclargs \
  -board au250 -user_plugin ../plugin/rdma_onic \
  -tag dual_rdma_rtl -rdma 1 -classifier rtl \
  -num_phys_func 2 -num_cmac_port 2 \
  -impl 1 -jobs 16
```

**AU250 dual RDMA with P4 classifier:**
```bash
vivado -mode batch -source build.tcl -tclargs \
  -board au250 -user_plugin ../plugin/rdma_onic \
  -tag dual_rdma_p4 -rdma 1 -classifier p4 \
  -num_phys_func 2 -num_cmac_port 2 \
  -impl 1 -jobs 16
```

**Non-RDMA regression (must still work):**
```bash
vivado -mode batch -source build.tcl -tclargs \
  -board au250 -user_plugin ../plugin/p2p \
  -tag baseline -impl 1 -jobs 16
```

---

## Step 9: Verification

### 9a. IP Generation Check (fast, no synthesis)

```bash
vivado -mode batch -source build.tcl -tclargs \
  -board au250 -user_plugin ../plugin/rdma_onic \
  -tag rdma_ipcheck -rdma 1 -classifier rtl -synth_ip 1 -impl 0
```

All IPs (ERNIC, DDR4 MIG, AXI crossbars, clock converters) should generate cleanly.

### 9b. Non-RDMA Regression

Build with `-rdma 0` or the original `p2p` plugin to confirm `ifdef` guards don't break baseline NIC functionality.

### 9c. Full Synthesis + Implementation

```bash
vivado -mode batch -source build.tcl -tclargs \
  -board au250 -user_plugin ../plugin/rdma_onic \
  -tag rdma_full -rdma 1 -classifier rtl \
  -impl 1 -post_impl 1 -jobs 16
```

Use `Performance_Retiming` implementation strategy for timing closure (larger design).

**Resource estimate:** Dual ERNIC + 3-tier interconnect + DDR4 adds ~250-300K LUTs on a ~850K LUT AU250 (~30-35% utilization for RDMA alone).

### 9d. Hardware Validation (Dual RDMA)

1. **Program FPGA** with generated bitstream
2. **Verify both CMAC links up** — non-RDMA NIC traffic on both ports via QDMA H2C/C2H
3. **Read ERNIC0 registers** at BAR2 + 0x200000 via `pcimem` or devmem
4. **Read ERNIC1 registers** at BAR2 + 0x600000 — verify independent access
5. **Create QP on port 0** via `libreconic` API with `port_id=0`
6. **Create QP on port 1** via `libreconic` API with `port_id=1`
7. **RDMA Write test on port 0** (`write.c -P 0`)
8. **RDMA Write test on port 1** (`write.c -P 1`)
9. **Simultaneous dual-port RDMA** — run RDMA on both ports concurrently, verify no DDR4 contention deadlock
10. **RDMA Send/Recv test** on each port (`send_recv.c -P 0`, `-P 1`)

### 9e. Driver

- Standard `open-nic-driver` for non-RDMA NIC traffic
- `libreconic` userspace library for RDMA operations (mmap BAR2, post WQEs, poll CQ)

---

## File Change Summary (Dual RDMA)

| Category | Repo | Modified | Created |
|----------|------|----------|---------|
| DDR4 memory | shell | `build.tcl`, `constr/au250/general.xdc` | `src/mem_ctrl/au250/` (2), `constr/au250/pins_ddr4.xdc` |
| RDMA subsystem (×2) | shell | -- | `src/rdma_subsystem/` (7 files: .sv×4 + .tcl×3) |
| AXI interconnects (3-tier) | shell | -- | `src/utility/` (8 files: 4 .sv wrappers + 4 .tcl crossbar IPs) |
| System address map (12-port) | shell | 3 files in `src/system_config/` | -- |
| Top-level shell | shell | `src/open_nic_shell.sv` (~800-1000 lines) | -- |
| Box extension (×2 instances) | shell | `src/box_250mhz/box_250mhz.sv` (~100 lines) | -- |
| RDMA plugin (per-box classifier) | shell | -- | `plugin/rdma_onic/` (~20 files incl. 3 classifier backends) |
| Build system | shell | `build.tcl`, `board_settings/au250.tcl` | -- |
| Driver BAR2/regs | driver | `onic_register.h` (SHELL_END→0x800000), `onic_hardware.c` | -- |
| libreconic (dual-port) | reconic | `reconic_reg.h` (verify base addresses), `reconic.c` (verify port_id) | -- |
| **Total** | | **~10 files** | **~37 files** |

---

## Prerequisites

| Requirement | Needed when | How to check |
|-------------|-------------|--------------|
| Xilinx ERNIC license | Always (for RDMA) | `create_ip -name ernic -vendor xilinx.com` in Vivado |
| VitisNetP4 license | Only with `-classifier p4` | `create_ip -name vitis_net_p4` in Vivado |
| Vitis HLS | Only with `-classifier hls` | `which vitis_hls` |
| Vivado 2021.2+ | Always | ERNIC v4.0 compatibility |
| AU250 board files | Board builds | Already in `constr/au250/` |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ERNIC license unavailable | Cannot synthesize either RDMA subsystem | Use RTL classifier (no extra license); ERNIC license is the hard requirement |
| ERNIC license doesn't allow 2 instances | Can only build single-RDMA | Verify multi-instantiation with Xilinx; fall back to single-ERNIC build |
| Timing closure | Dual ERNIC + 3-tier interconnect increases design size significantly | Use `Performance_Retiming` strategy; add pipeline stages at crossbar boundaries |
| DDR4 bandwidth saturation | Dual ERNIC at line rate overwhelms single DDR4 channel | Start with single channel; measure bandwidth; split to dual DDR4 if needed (AU250 has 4 banks) |
| DDR4 MIG pin conflicts | Build failure | Verify pin XDC against Xilinx AU250 board schematic |
| Address map: 8MB BAR2 exceeds default | Driver/OS fails to map full BAR2 | Verify PCIe BAR2 size is ≥8MB in QDMA IP configuration |
| RecoNIC code targets older Vivado | IP version mismatches | Update IP version numbers in TCL scripts to match your Vivado install |
| Deadlock in shared DDR4 crossbar | Both ERNICs block waiting for DDR4 | 4:1 crossbar uses round-robin arbitration; verify no circular dependency in AXI ordering |

---

## Step 10: Driver Changes (open-nic-driver)

**Why:** The FPGA shell changes are useless without software that can talk to ERNIC. RecoNIC uses a **userspace** approach -- mmap BAR2 directly, post WQEs, poll CQs, all without kernel RDMA verbs. The open-nic-driver needs small but critical updates to support this.

**Key insight:** The ONIC kernel driver does NOT need RDMA awareness. RDMA operates independently via BAR2 mmap from userspace. The driver changes are about compatibility, not RDMA plumbing.

### 10a. BAR2 Mapping Size

The driver currently maps BAR2 with a 4MB window:
```c
// onic_hardware.c
pci_iomap_range(pdev, 2, 0x0, 0x400000);  // SHELL_END = 0x400000
```

With dual RDMA, BAR2 grows to **8MB** (ERNIC0 at 0x200000, ERNIC1 at 0x600000, end at 0x800000).

| File | Change |
|------|--------|
| `onic_register.h` | Update `SHELL_END` from `0x400000` to `0x800000` |
| `onic_hardware.c` | Update `pci_iomap_range` size to `0x800000` |

**Note:** Existing register offsets (CMAC, QDMA, box) are unchanged — the reference design does NOT shift addresses. Only the mapping size grows.

### 10b. QDMA AXI-MM Bridge Enablement (for host memory RDMA)

If ERNIC needs to DMA to **host** memory (not just FPGA DDR4), the QDMA AXI-MM bridge must be enabled. RecoNIC configures 8 BDF address translation windows (128GB each) to map host physical addresses into the FPGA's address space.

This is handled by `libreconic` userspace code (`reconic.c:setup_qdma_bdf_windows()`), not the kernel driver. However, the QDMA IP must be built with AXI-MM enabled:

| File | Change |
|------|--------|
| `qdma_no_sriov_au250.tcl` (shell side) | Enable `C_AXI_MM_ENABLE` in QDMA IP generation |

### 10c. Character Device for DDR4 DMA (optional)

RecoNIC uses a character device (`/dev/reconic-mm`) for host-initiated reads/writes to FPGA DDR4. This is only needed for:
- Loading initial data into DDR4 before RDMA operations
- Debugging DDR4 contents

For basic RDMA (ERNIC manages DDR4 autonomously), this is NOT required. ERNIC's 6 AXI-MM masters handle all DDR4 access in hardware.

If needed later:

| File | Change |
|------|--------|
| New: `onic_ddr4.c` | Char device: open/read/write/lseek to DDR4 via QDMA AXI-MM |
| `onic_main.c` | Register char device in probe, deregister in remove |
| `Makefile` | Add `onic_ddr4.o` to build |

### 10d. libreconic Userspace Library (Dual-Port API)

RecoNIC's `lib/` directory is the RDMA control plane. It mmaps BAR2 and operates ERNIC directly from userspace. The library already supports dual RDMA via a `port_id` parameter.

### Dual-port register offsets (from reference `reconic_reg.h`)

```c
#define RN_RDMA_BASE_ADDRESS_0       0x00200000  // ERNIC0 (CMAC0/QSFP0)
#define RN_RDMA_BASE_ADDRESS_1       0x00600000  // ERNIC1 (CMAC1/QSFP1)
#define RN_RDMA_BASE_ADDRESS         RN_RDMA_BASE_ADDRESS_0  // Default
// Delta between ports: 0x400000 (4MB)
```

### Dual-port device API (from reference `reconic.h`)

```c
struct rn_dev_t {
  uint32_t* axil_ctl;           // BAR2 base pointer
  uint32_t  axil_map_size;      // 0x00800000 (8MB for dual RDMA)
  uint8_t   port_id;            // 0=QSFP0, 1=QSFP1
  // ...
};

// Create device for specific port
struct rn_dev_t* create_rn_dev(
  char* pcie_resource, int* fd,
  uint32_t num_hugepages, uint32_t num_qp,
  uint8_t port_id                // 0 or 1
);
```

### Port offset calculation (from reference `rdma_api.c`)

```c
if (rn_dev->port_id == 0) {
    rdma_dev->axil_ctl = rn_dev->axil_ctl;
} else {
    uint32_t delta = RN_RDMA_BASE_ADDRESS_1 - RN_RDMA_BASE_ADDRESS_0;  // 0x400000
    rdma_dev->axil_ctl = (uint32_t*)((uint8_t*)rn_dev->axil_ctl + delta);
}
```

### Char device per port

```
/dev/reconic-mm0  → DDR4 access for port 0
/dev/reconic-mm1  → DDR4 access for port 1
```

### Example usage (from reference `write.c`)

```bash
# RDMA Write on port 0 (QSFP0)
./write -d /dev/reconic-mm0 -P 0 ...

# RDMA Write on port 1 (QSFP1)
./write -d /dev/reconic-mm1 -P 1 ...
```

| Library file | Purpose | Adaptation needed |
|--------------|---------|-------------------|
| `reconic.c/h` | Device init, BAR2 mmap, hugepage alloc | Update `axil_map_size` to 0x800000; `port_id` already supported |
| `reconic_reg.h` | ERNIC register offsets (GCSR, QCSR, PDT) | Verify `RN_RDMA_BASE_ADDRESS_0/1` match our address map |
| `rdma_api.c/h` | QP creation, WQE posting, CQ polling | Port offset logic already exists — verify delta matches |
| `memory_api.c/h` | DDR4 access via char device | Dual char device (`/dev/reconic-mm0`, `/dev/reconic-mm1`) |
| `control_api.c/h` | Register read/write helpers | Unchanged |

### Driver change summary (dual RDMA)

| Change | Required? | Effort |
|--------|-----------|--------|
| BAR2 mapping size → 0x800000 (8MB) | Yes | 2 lines |
| QDMA AXI-MM bridge enable (shell TCL) | Only for host-memory RDMA | 1 line |
| Character device for DDR4 (×2 ports) | No (optional for debug) | ~250 lines |
| libreconic dual-port register offsets | Yes | Verify existing `RN_RDMA_BASE_ADDRESS_0/1` constants match |
| libreconic `port_id` API | Already exists in reference | Verify/copy from reference |
| Kernel RDMA verbs (ib_device) | No | N/A — RecoNIC is userspace |

**The driver work is small.** The reference already supports dual RDMA via `port_id`. Main adaptation: verify register base addresses (0x200000/0x600000) and BAR2 size (0x800000) match our address map.

---

## Optional Extension: Compute Offload (Phase 2)

After dual RDMA is working, the RecoNIC compute logic can be added. **Note: in the reference, only box_250mhz_0 (ERNIC0/CMAC0) has compute offload. box_250mhz_1's compute AXI-MM is tied off.**

1. Copy `shell/compute/lookside/` into the plugin
2. Add `compute_logic_wrapper.sv`, `control_command_processor.sv`
3. Add HLS kernels (`cl_box.v`, `mmult.v`) — requires Vitis HLS compilation
4. Compute AXI-MM master already accounted for in the 4:1 dev_mem crossbar (S01 port)
5. Expose compute registers at plugin offset 0x3000

This is fully contained within the plugin — no additional shell modifications needed. The 4:1 crossbar already has an S01 port reserved for compute logic.

---

## Optional Extension: AU280 Board Support (Phase 3)

1. Create `src/mem_ctrl/au280/vivado_ip/` (DDR4 MIG for AU280)
2. Create `constr/au280/pins_ddr4.xdc`
3. Update `constr/au280/general.xdc` with MMCM placement
4. Add `script/board_settings/au280.tcl` DDR4 parameters
5. AU280 also has HBM -- could be used as additional payload buffer (future work)
