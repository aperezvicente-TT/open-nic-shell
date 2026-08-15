# eth_2cmac_1pf — Shell Integration Contract

`eth_2cmac_1pf_250mhz.sv` is a **pure-ethernet, single-PF / N-CMAC** user
plugin for the OpenNIC `box_250mhz`. It needs the QDMA **absolute queue ID**
(`tuser_qid`) plumbed through the shell on BOTH the H2C (TX) and C2H (RX)
boundaries. That plumbing **does NOT exist on `main`** — it was added on
branch `feature/rdma-ernic-v528-diag-csr`. Until the hooks below are grafted
onto the shell, this plugin will elaborate/synthesize standalone but will
**not bind into the shell** (the qid ports on `user_plugin_250mhz_inst.vh`
have no driver) and even if forced-bound, RX qid routing is a no-op
(qdma_subsystem ignores `s_axis_c2h_tuser_qid` unless `EXT_QID=1`).

This graft is **OUT OF SCOPE** for the plugin work; this file documents
exactly what must be added, and how `feature/rdma-ernic-v528-diag-csr` does
it, so the shell side can be reproduced.

---

## What the plugin consumes / produces

The plugin's module ports (already present in `eth_2cmac_1pf_250mhz.sv`):

- **Input**  `s_axis_qdma_h2c_tuser_qid  [11*NUM_INTF*NUM_QDMA-1:0]`
  Absolute H2C queue ID. The TX demux uses the top bits
  (`qid[$clog2(PER_CMAC_QUEUES) +: $clog2(NUM_INTF)]`, `PER_CMAC_QUEUES=64`)
  to choose the owning CMAC.
- **Output** `m_axis_qdma_c2h_tuser_qid  [11*NUM_INTF*NUM_QDMA-1:0]`
  Absolute C2H queue ID. The RX arbiter emits `qid = cmac*PER_CMAC_QUEUES`
  per granted CMAC (sourced from the per-CMAC FIFO TUSER).

Both are wired in `box_250mhz/user_plugin_250mhz_inst.vh` to identically
named `box_250mhz.sv` ports — which is the graft below.

---

## Required shell additions

### 1. `src/box_250mhz/box_250mhz.sv` — add two ports (RDMA branch: +149 lines)

Add to the module port list:

```verilog
// Absolute qid forwarded from QDMA so the plugin can demux H2C to CMAC.
input   [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_qid,
// Plugin tags CMAC-encoded absolute qid here.  Ignored by qdma_subsystem
// when EXT_QID=0 (non-RDMA builds).
output  [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_qid,
```

In the **non-user-block / passthrough branch** of `box_250mhz.sv` (the
`else` that ties off the user-plugin signals), tie the C2H qid output:

```verilog
assign m_axis_qdma_c2h_tuser_qid = 0;
```

The two new ports are then referenced by name inside
`box_250mhz/user_plugin_250mhz_inst.vh` (already wired in this plugin's
copy of that file).

> Reference: `git show feature/rdma-ernic-v528-diag-csr:src/box_250mhz/box_250mhz.sv`
> and `git diff main feature/rdma-ernic-v528-diag-csr -- src/box_250mhz/box_250mhz.sv`
> (box_250mhz.sv lines ~52-66 for the ports, ~278 for the tie-off).

### 2. `src/open_nic_shell.sv` — carry qid between qdma_subsystem and box_250mhz

Add the two interconnect nets and wire them on both modules:

```verilog
wire [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_qid;
wire [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_qid;
```

- On the **qdma_subsystem** instance:
  - `.m_axis_h2c_tuser_qid (axis_qdma_h2c_tuser_qid[...])`  (per-PF slice)
  - `.s_axis_c2h_tuser_qid (axis_qdma_c2h_tuser_qid[...])`  (per-PF slice)
- On the **box_250mhz** instance:
  - `.s_axis_qdma_h2c_tuser_qid (axis_qdma_h2c_tuser_qid)`
  - `.m_axis_qdma_c2h_tuser_qid (axis_qdma_c2h_tuser_qid)`

> Reference: `feature/rdma-ernic-v528-diag-csr:src/open_nic_shell.sv`
> lines ~433/444 (net decls), ~1826/1837 (qdma_subsystem), ~2219/2230 (box_250mhz).

### 3. `src/qdma_subsystem/*` — EXT_QID support (RDMA branch: ~1000 lines)

The C2H qid the plugin emits is only honored if qdma_subsystem is built with
`EXT_QID=1`, which makes C2H take the queue ID from `s_axis_c2h_tuser_qid`
instead of internal RSS. Files involved on the feature branch:

- `qdma_subsystem.sv`           — `parameter int EXT_QID = 0`; new ports
  `m_axis_h2c_tuser_qid [11*NUM_PHYS_FUNC-1:0]` and
  `s_axis_c2h_tuser_qid [11*NUM_PHYS_FUNC-1:0]`; threads them to
  `qdma_subsystem_function`/`_c2h`; passes `.EXT_QID(EXT_QID)` down.
- `qdma_subsystem_function.sv`  — `parameter int EXT_QID`; H2C qid FIFO that
  emits the per-beat qid on `m_axis_h2c_tuser_qid`; C2H slice/CDC that keeps
  `s_axis_c2h_tuser_qid` byte-locked to the data and drives
  `m_axis_c2h_tuser_qid` when `EXT_QID=1`.
- `qdma_subsystem_c2h.sv`       — packs qid into the C2H packet-FIFO TUSER /
  ECC bits so it stays paired with the beat
  (`s_axis_tuser = {ptp_ts, size, qid}`).
- `qdma_subsystem_qdma_wrapper.v` and the `vivado_ip/*.tcl` (QDMA IP
  regen with the wider C2H ST user / EXT_QID descriptor bypass).

> Reference: `git diff main feature/rdma-ernic-v528-diag-csr -- src/qdma_subsystem`.
> The plugin only requires that `EXT_QID=1` be plumbed for the C2H qid to take
> effect; the H2C qid path (`m_axis_h2c_tuser_qid`) is needed regardless so the
> TX demux sees a real qid.

---

## Build-flow note

`build_box_250mhz.tcl` in this plugin reads only `eth_2cmac_1pf_250mhz.sv`
and `rdma_diag_csr.sv`. Both depend on shell utilities already present on
`main` (`src/utility/generic_reset.sv`, `src/utility/axi_stream_packet_fifo.sv`),
so no extra `read_verilog` of plugin-local helpers is needed. The
`axi_stream_packet_fifo` pulls in the Xilinx `axis_data_fifo` IP via the
shell's normal IP build, so a standalone OOC elaboration of just these two
files will need that IP available.

## Parameter / driver contract

- `PER_CMAC_QUEUES = 64` (power of two) is hard-coded in the RTL. The host
  driver's `ONIC_PER_CMAC_QUEUES` MUST equal 64.
- CMAC `c` owns absolute qid range `[c*64, (c+1)*64)`. RX traffic from CMAC
  `c` is tagged `qid = c*64` (lands on that CMAC's first netdev queue; RSS
  spreading is a follow-up).
- `NUM_INTF` (= `NUM_CMAC_PORT`) supported 2..8.
- `NUM_QDMA` may be 1 or equal to `NUM_INTF`:
  - `NUM_QDMA == 1` — **qid-steered mode** (the original behaviour). One H2C
    slot demuxed to the owning CMAC by absolute qid; an N-way round-robin
    arbiter muxes the CMAC RX FIFOs onto C2H slot 0. The `PER_CMAC_QUEUES = 64`
    contract above applies.
  - `NUM_QDMA == NUM_INTF` (> 1) — **1:1 pinned mode**, selected automatically.
    QDMA endpoint `c` is wired straight to CMAC `c`: no qid demux, no arbiter,
    no shared backpressure between endpoints. The CMAC-select bits of the qid
    carry no meaning in this mode (there is one destination per endpoint), but
    the qid is still forwarded intact for per-queue steering *within* an
    endpoint, and each endpoint keeps its own independent qid space.
  - Any other combination is not supported.
- The plugin `$display`s which mode it elaborated; check the synthesis log.
