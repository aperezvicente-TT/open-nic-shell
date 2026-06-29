# QID Graft Spec — pure-Ethernet 1-PF / N-CMAC for OpenNIC (au200)

Goal: make a single QDMA PF drive N CMAC ports by threading an **absolute queue-id**
through the shell, so the `eth_2cmac_1pf` plugin can demux TX by qid and tag RX by
source CMAC. This is the only RTL remaining; the plugin datapath module and the
multi-netdev driver are already done.

Source of truth for every hunk: branch `feature/rdma-ernic-v528-diag-csr`
(extract the qid plumbing only; leave all ERNIC/DDR/sysdma behind).

## The datapath contract
- **H2C (TX):** QDMA exposes each packet's queue-id on `m_axis_h2c_tuser_qid[10:0]`.
  Plugin: `cmac = qid[6 +: clog2(N)]` (PER_CMAC_QUEUES=64), demuxes to CMAC TX.
- **C2H (RX):** plugin tags each packet with `s_axis_c2h_tuser_qid = cmac*64`.
  With `EXT_QID=1`, QDMA uses that qid as the descriptor's queue (NOT internal RSS),
  carried **in lockstep with data** through the c2h slice/clk-converter TUSER
  (widened 96→107: `{qid[10:0], ptp_ts[79:0], size[15:0]}`) — no side-FIFO, which
  is what fixed the dual-CMAC misroute (project_b7_dual_cmac_qid_misroute).
- Driver invariant: `ONIC_PER_CMAC_QUEUES == 64`; CMAC c owns abs qid `[c*64,(c+1)*64)`.

## Files to graft (port from the branch)

| File | How | ERNIC-coupled? | Risk |
|---|---|---|---|
| `qdma_subsystem.sv` | wholesale copy | no (0 refs) | low |
| `qdma_subsystem_function.sv` | wholesale copy | no (0 refs) | **med-high** (TUSER widths) |
| `qdma_subsystem_qdma_wrapper.v` | wholesale copy | no (0 refs) | low |
| `qdma_subsystem_c2h.sv` | 2-line diff | refs are pre-existing comments | low |
| `vivado_ip/qdma_no_sriov_au200.tcl` | apply qid/EXT_QID hunks (17 ln) | no | low |
| `vivado_ip/qdma_subsystem_clk_converter*.tcl` | **VERIFY TUSER_WIDTH=107** (code NOTE) | no | **med** (width mismatch = corruption) |
| `box_250mhz.sv` | add 2 qid ports + passthrough | no | low |
| `open_nic_shell.sv` | 2 qid interconnect nets (~13 ln, skip ERNIC bulk) | extract only qid | med (big file) |

## Interface (from qdma_subsystem.sv on the branch)
```
parameter int EXT_QID = 0;                              // 1 for the eth plugin
output [11*NUM_PHYS_FUNC-1:0] m_axis_h2c_tuser_qid;     // H2C qid → plugin
input  [11*NUM_PHYS_FUNC-1:0] s_axis_c2h_tuser_qid;     // plugin → C2H (EXT_QID=1)
```
`open_nic_shell` instantiates qdma_subsystem with `EXT_QID(1)` and wires these two
buses to box_250mhz (and thence the plugin). NUM_PHYS_FUNC=1.

## Execution order (synth-gate after each step)
1. **qdma_subsystem RTL** — copy the 4 files; verify clk_converter IP TUSER=107;
   apply au200 IP tcl. OOC-elaborate the subsystem (read_verilog parse at minimum).
2. **box_250mhz.sv** — add qid ports; the plugin include already expects them.
3. **open_nic_shell.sv** — add the 2 qid nets; set `EXT_QID(1)` on qdma_subsystem.
4. **Full build** — `-user_plugin ../plugin/eth_2cmac_1pf -num_phys_func 1 -num_cmac_port 2`.

## Out of scope
- ERNIC / DDR4 / sysdma / compute-AXI (all skipped — pure Ethernet).
- N>2 CMACs: stock `build.tcl` caps `num_cmac_port` at 2; >2 needs separate CMAC
  instantiation work. This graft makes 1-PF/2-CMAC work and is N-ready in the plugin.

## Risk notes
- The single highest-risk item is the **c2h TUSER width chain** (slice + clk_converter
  IP + buf_fifo all must agree at 107 bits). Verify the IP customization explicitly.
- Port the *fixed* (v5.2.10+) version of `qdma_subsystem_function.sv` — earlier
  revisions had the misroute bug; the branch tip has the lockstep-TUSER fix.
