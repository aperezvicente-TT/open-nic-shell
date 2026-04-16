# Plan: Integrating RDMA ERNIC from RecoNIC onto Open-NIC-Shell

## Context

RecoNIC already integrates the Xilinx ERNIC IP into a **forked** copy of open-nic-shell via a monolithic 425KB patch (`patches/open-nic-shell/rdma_onic.patch`, ~7978 lines, 39 files). The goal is to understand how to integrate the ERNIC into the **standalone** open-nic-shell at `/home/alex/mpi-shfs/fpga/open-nic-shell` cleanly.

**Key finding: ERNIC cannot be a pure plugin.** The standard plugin API only exposes AXI-Stream data (512-bit) and a small AXI-Lite control interface. ERNIC additionally requires:
1. **AXI4 Full memory interfaces** (64-bit addr, 512-bit data) to DDR4 for RDMA payload storage
2. **A dedicated AXI-Lite region** at BAR2 offset 0x200000 (2MB) for ERNIC registers
3. **Sideband signals** (IETH/IMMDT data, doorbell handshaking, QP control)

## Recommended Approach: Hybrid (Minimal Shell Mods + Plugin)

The cleanest path is structured shell modifications (guarded by `ifdef __RDMA_ENABLED__`) combined with a plugin for all datapath/classification logic.

---

## Data Flow Architecture

```
Host CPU (PCIe)
    |
QDMA Subsystem (H2C/C2H 512-bit AXI-Stream + AXI-MM bridge)
    |
box_250mhz [rdma_onic plugin]
    |--- Packet Classifier (P4 or fixed-function RTL)
    |       |--- RoCEv2 pkts --> RDMA Subsystem (ERNIC IP)
    |       |--- Non-RoCE pkts --> QDMA C2H (to host)
    |
    |--- RDMA Subsystem
    |       |--- AXI4-MM --> DDR4 Memory Controller (payload storage)
    |       |--- AXI-Lite <-- system_config (BAR2 @ 0x200000)
    |       |--- TX merge (RDMA + non-RDMA) --> Packet Adapter --> CMAC
    |
Packet Adapter (250MHz <-> 322MHz CDC)
    |
CMAC Subsystem (100Gbps Ethernet)
```

---

## Implementation Phases

### Phase 1: DDR4 Memory Controller

**New files** (copy from RecoNIC `base_nics/open-nic-shell/src/mem_ctrl/`):
- `src/mem_ctrl/au250/vivado_ip/dev_mem_ddr4_controller_au250.tcl`
- `src/mem_ctrl/au250/vivado_ip/vivado_ip.tcl`

**Modify** `script/build.tcl` (~4 lines): Add board-specific `mem_ctrl` directory lookup:
```tcl
if {[string equal $module mem_ctrl]} {
    set module_dir ${module_dir}/${board}
}
```

**Modify** `constr/au250/general.xdc` (~5 lines): DDR4 MMCM placement + INTERNAL_VREF constraints.

### Phase 2: RDMA Subsystem Module

**New directory** `src/rdma_subsystem/` (copy from RecoNIC `base_nics/open-nic-shell/src/rdma_subsystem/`):
- `rdma_subsystem.sv` - Instantiates Xilinx ERNIC IP
- `rdma_subsystem_wrapper.sv` - Wraps ERNIC with packet merge logic, non-RoCE bypass
- `vivado_ip/rdma_core.tcl` - ERNIC IP creation (v4.2, 32 QPs, 512-bit data)
- `vivado_ip/vivado_ip.tcl`

The build system auto-discovers `src/*/` directories, so this is picked up automatically.

**Prerequisite**: Xilinx ERNIC license required.

### Phase 3: AXI Memory Interconnects

**New files in `src/utility/`** (copy from RecoNIC):
- `axi_interconnect_to_dev_mem.sv` - Routes ERNIC AXI-MM to DDR4
- `axi_3to1_interconnect_to_dev_mem.sv` - Variant with compute port
- `vivado_ip/dev_mem_axi_crossbar.tcl` - 2x1 crossbar IP
- `vivado_ip/axi_clock_converter_for_mem_au250.tcl` - 250MHz-to-MIG clock CDC

### Phase 4: System Address Map Expansion

**Modify** `src/system_config/system_config_address_map.sv` (~80 lines):
- Add `m_axil_rdma_*` AXI-Lite output port (18 signals)
- Add RDMA slave at BAR2 base 0x200000 (2MB window)
- Shift box_250mhz base to 0x500000, box_322mhz to 0x400000

**Modify** `src/system_config/vivado_ip/system_config_axi_crossbar.tcl` (~10 lines):
- Add one more master port to AXI crossbar

**Modify** `src/system_config/system_config.sv` (~20 lines):
- Wire new RDMA AXI-Lite port through

### Phase 5: Top-Level Shell Wiring

**Modify** `src/open_nic_shell.sv` (~500-700 lines added, guarded by `ifdef __RDMA_ENABLED__`):
1. DDR4 top-level pins (`c0_ddr4_adr`, `c0_ddr4_ba`, `c0_sys_clk_p/n`, etc.)
2. Instantiate `rdma_subsystem_wrapper` - connect AXI-Lite, AXI-Stream, AXI-MM
3. Instantiate `axi_interconnect_to_dev_mem` - route ERNIC memory to DDR4
4. Instantiate DDR4 controller
5. Extend `box_250mhz` port list with RDMA sideband signals:
   - `m_axis_user2rdma_roce_from_cmac_rx_*` (classified RoCE pkts to ERNIC)
   - `s_axis_rdma2user_to_cmac_tx_*` (merged RDMA TX to CMAC)
   - `m_axis_user2rdma_from_qdma_tx_*` (non-RoCE to ERNIC TX merger)
   - `s_axis_rdma2user_ieth_immdt_*` (immediate data)
   - Doorbell signals (`s_resp_hndler_*`, `m_o_qp_sq_pidb_*`, etc.)

### Phase 6: Extend box_250mhz Port List

**Modify** `src/box_250mhz/box_250mhz.sv` (~50 lines):
- Add RDMA sideband ports to module declaration (guarded by `ifdef __RDMA_ENABLED__`)
- These flow through to the plugin via `user_plugin_250mhz_inst.vh`

### Phase 7: Create RDMA Plugin

**New directory** `plugin/rdma_onic/`:
```
plugin/rdma_onic/
  build_box_250mhz.tcl              # Sources plugin RTL + VitisNetP4 parser IP
  build_box_322mhz.tcl              # Copy from p2p (322MHz box unchanged)
  p2p_322mhz.sv                     # Copy from p2p
  rdma_onic_250mhz.sv               # Top-level 250MHz plugin (replaces p2p_250mhz)
  rdma_onic_plugin.sv               # Packet classification + QDMA/RDMA routing
  reconic_address_map.sv             # Plugin-internal AXI-Lite crossbar
  reconic.sv                         # Packet parser + filter + buffer
  packet_classification.sv           # RoCEv2 vs non-RDMA classifier
  packet_filter.sv
  packet_matcher.sv
  box_250mhz/
    user_plugin_250mhz_inst.vh       # Instantiates rdma_onic_250mhz + RDMA sideband ports
    box_250mhz_address_map_inst.vh
    box_250mhz_address_map.v
    box_250mhz_axi_crossbar.tcl
  box_322mhz/                        # Copy from p2p (passthrough)
    user_plugin_322mhz_inst.vh
    box_322mhz_address_map_inst.vh
    box_322mhz_address_map.v
    box_322mhz_axi_crossbar.tcl
```

Source files copied from: `RecoNIC/shell/plugs/rdma_onic_plugin/` and `RecoNIC/shell/top/`.

### Phase 8: QDMA AXI-MM Bridge (Optional)

Only needed if ERNIC must DMA to host memory (not just DDR4):

**Modify** `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au250.tcl` - Enable AXI-MM bridge
**Modify** `src/qdma_subsystem/qdma_subsystem.sv` - Expose `m_axi_*` / `s_axi_*` ports
**Modify** `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v` - Wire through AXI-MM

---

## Build Command

```bash
cd open-nic-shell/script
vivado -mode batch -source build.tcl -tclargs \
  -board au250 \
  -user_plugin ../plugin/rdma_onic \
  -tag rdma_build \
  -impl Performance_Retiming
```

---

## Summary of File Changes

| Category | Files Modified | Files Created |
|----------|---------------|---------------|
| DDR4 memory | `build.tcl`, `general.xdc` | `src/mem_ctrl/au250/` (2 files) |
| RDMA subsystem | - | `src/rdma_subsystem/` (4 files) |
| AXI interconnects | `vivado_ip.tcl` | `src/utility/` (4-5 files) |
| System address map | `system_config_address_map.sv`, `system_config.sv`, `system_config_axi_crossbar.tcl` | - |
| Top-level shell | `open_nic_shell.sv` | - |
| Box extension | `box_250mhz.sv` | - |
| Plugin | - | `plugin/rdma_onic/` (~15 files) |
| QDMA (optional) | 3 QDMA files | - |

**Total**: ~8 existing files modified, ~25 new files (mostly copied from RecoNIC)

---

## Prerequisites & Risks

- **Xilinx ERNIC License**: Required. Verify with `create_ip -name ernic -vendor xilinx.com`
- **VitisNetP4**: Needed for P4 packet classifier compilation. Can substitute with fixed-function RTL (`packet_classification.sv`) from RecoNIC
- **Vivado 2021.2+**: Required for ERNIC IP compatibility
- **Timing Closure**: Larger design; use `Performance_Retiming` implementation strategy
- **Board-Specific**: DDR4 pin constraints are AU250-specific initially; port to other boards later

---

## Verification

1. **Synthesis**: Build bitstream targeting AU250 with `Performance_Retiming` strategy
2. **Simulation**: Use RecoNIC's existing testbenches in `sim/` directory
3. **Hardware Test**: Program FPGA, bring up CMAC link, verify:
   - Non-RoCE traffic still flows through QDMA H2C/C2H (standard NIC function preserved)
   - ERNIC registers accessible at BAR2 + 0x200000
   - RDMA QP creation via `libreconic` API (`lib/rdma_api.h`)
   - RDMA Write/Send operations between two FPGA nodes
4. **Driver**: Standard `open-nic-driver` for NIC traffic; `libreconic` user-space library for RDMA operations
