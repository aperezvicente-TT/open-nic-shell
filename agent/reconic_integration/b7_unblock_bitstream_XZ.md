# B7 Unblock — v4 bitstream enabling Route X (host→DDR4 via BAR4) and keeping Route Z (ERNIC→host via s_axib)

Design doc + patch SKETCH.  DO NOT apply to source.  Sibling of F5/B3/B5/B6/B7 design docs.

Written 2026-04-23 to unblock Track B7's acceptance path: host staging WQEs/MR
payloads into DDR4.  v3 already ships Route Z wired (Session 4 graft, commit
`c92420d` + Session 5 TCL fix in `tier1b_qdma_audit.md`), so the remaining
delta vs v3 is purely additive — Route X.  The doc keeps Route Z bookkeeping
visible for completeness, but the actual patch surface is ~Route X only.

Status flag for every structural claim that hasn't been eyeball-confirmed
against PG302 v5.1 Ch 3 tables: **VERIFY**.  §11 is the consolidated list.

---

## 1. Scope, rationale, acceptance gate

### What v4 unlocks

- **Route X (host → DDR4, MMIO)**.  BAR4 on PF0 is typed `AXI_Bridge_Master`
  and sized 1 GiB.  Host `memcpy_toio(bar4 + off, …)` lands on QDMA's
  internal AXI-Bridge-Master pipe, exits the IP on `m_axi_*` (the QDMA DMA
  engine's MM interface), and is routed by the existing
  `axi_interconnect_to_dev_mem` crossbar into DDR4.  This is the B7
  acceptance path: the driver can now stage WQEs + MR payloads without
  going through ERNIC→host DMA.
- **Route Z (ERNIC → host, bus mastering)**.  Already live in v3 via
  `axi_sys_mem_mux_*` → `qdma_subsystem[0].s_axib_*`.  Retained unchanged
  in v4 so future host-memory MRs don't need another rebuild.

### Independence evidence

PG302 v5.1, p162 Figure 27 ("Basic Tab") separates "Bridge Interface
options" from "DMA Interface options" — the two toggles `en_bridge_slv`
and `en_axi_mm_qdma` are independent IP-gen knobs.  RecoNIC's AU200
reference enables both (`RecoNIC/.../qdma_no_sriov_au200.tcl` lines 46-49).

### Acceptance

After flashing v4:
1. `lspci -vv -s <bdf>` shows BAR4 present at the configured size (1 GiB
   recommended; see §3 VERIFY).
2. Driver `pci_iomap(pdev, 4, 0)` succeeds, returning a valid iomem cookie.
3. DDR4 round-trip probe: driver does `writel(MAGIC, bar4 + 0x10);
   rmb(); readl(bar4 + 0x10)` — value comes back as MAGIC (modulo ECC
   scrub latency).  New probe — add to `tools/probe_bar4_ddr4.sh`.
4. Phase F2 MSI-X counter probe: unchanged behaviour (CSR path on BAR2
   untouched).
5. ERNIC CSR 27/27 regression on BAR2 @ 0x800000 / 0xA00000: unchanged.
6. `ibv_rc_pingpong` with the B7 driver progresses past
   `post_recv × 16` → INIT→RTR→RTS → one successful `post_send`, then
   fails at `poll_cq` (B8 stub).

### Non-goals / deferred

- `m_axib` (AXI Bridge Master exit path) — not added.  BAR4 uses the DMA
  master `m_axi_*`, not the bridge master.  Choice rationale: our DDR4
  slave already sits on a 4:1 crossbar that accepts `s_axi_qdma_mm_*` and
  has a stubbed slot for it (see §7 line-numbered evidence).  Adding
  `m_axib` would require a new crossbar master plus address-decode logic
  — strictly more work for no B7 benefit.  Revisit if Tier 2 demands
  host access to non-DDR4 AXI spaces (e.g., ERNIC CSRs from the host side
  via PCIe bridge).
- Route Z direction reversal (DEVICE_MEM queue placement with queues
  in DDR4) — deferred per `tier1b_qdma_audit.md` Session 3 Decision 1.

---

## 2. Delta vs v3 — three columns

| Layer | v3 has | Route X adds (new) | Route Z (already in v3) |
|---|---|---|---|
| IP config TCL | `en_axi_mm_qdma=false`, `dma_intf_sel=AXI_Stream_with_Completion`, `en_bridge_slv=true`, `axibar_notranslate=true` (Session 5 fix), BAR2=16 MB, MSIX=0x01F | `en_axi_mm_qdma=true`, `dma_intf_sel=AXI_MM_and_AXI_Stream_with_Completion`, BAR4 enable + size + type + pciebar2axibar_4, `pciebar2axibar_0` for DMA BAR | `en_bridge_slv=true` kept; `axibar_notranslate=true` kept (per Session 5 orphan-LUT fix) |
| QDMA wrapper (`qdma_subsystem_qdma_wrapper.v`) | `s_axib_*` ports declared + wired to IP in both `QDMA_ID==0/1` arms | ~32 `m_axi_*` port declarations in module header; `.m_axi_*(…)` connects in both generate arms | unchanged |
| QDMA subsystem (`qdma_subsystem.sv`) | `s_axib_*` passthroughs + wired to wrapper + `USE_PHYS_FUNC==0` stub ties off s_axib outputs | ~32 `m_axi_*` passthroughs + wrapper connects + stub block tie-offs for `m_axi_*` outputs | unchanged |
| Top (`open_nic_shell.sv`) | `axi_sys_mem_mux_*` → `qdma_subsystem[0].s_axib_*` (lines 1833-1885-ish), `s_axi_qdma_mm_*` on `axi_interconnect_to_dev_mem` stubbed all-0 (line ~3425) | Pull `m_axi_*` up through `qdma_subsystem` inst; feed the existing stubbed `s_axi_qdma_mm_*` input of the crossbar | unchanged |
| Stub comment `open_nic_shell.sv:3419-3422` | "axi_sys_mem_mux output drives the QDMA bridge for host-memory DMA from ERNIC" (stale; Route Z is wired but s_axi_qdma_mm is NOT) | Comment rewritten to document the now-live QDMA `m_axi_*` → dev_mem crossbar master path | n/a |

Total RTL LoC delta: ~140 new lines + ~15 modified.  Detailed estimate in §10.

---

## 3. IP config TCL edits — `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`

Starting point: v3's current file (our repo, HEAD).  Full unified-style diff
as a single `tcl` block (human applies manually):

```tcl
# Before (v3, lines 43-47):
#     CONFIG.dma_intf_sel_qdma {AXI_Stream_with_Completion}
#     CONFIG.en_axi_mm_qdma {false}
#     CONFIG.en_bridge_slv {true}
#     CONFIG.axibar_highaddr_0 {0x000000FFFFFFFFFF}
#     CONFIG.axibar_notranslate {false}

# After (v4):
    CONFIG.dma_intf_sel_qdma {AXI_MM_and_AXI_Stream_with_Completion}
    CONFIG.en_axi_mm_qdma {true}
    CONFIG.en_bridge_slv {true}
    CONFIG.axibar_highaddr_0 {0x000000FFFFFFFFFF}
    CONFIG.axibar_notranslate {true}

    # ------------------------------------------------------------------
    # BAR4 — host-visible MMIO window into DDR4 (Route X)
    # ------------------------------------------------------------------
    # BAR4 is typed as AXI DMA Bridge.  With `en_axi_mm_qdma=true`, host
    # writes to PF0 BAR4 are forwarded to the QDMA IP's m_axi_* (AXI-MM
    # master) port, which the shell routes into the dev_mem crossbar ->
    # DDR4 slave.  VERIFY — PG302 v5.1 p166-167 documents the Type
    # selection as "DMA / AXI Lite Master / AXI Bridge Master".  For
    # BAR4 defaulting to AXI Bridge Master, the exit port is m_axib.
    # For the DMA Bridge path (m_axi_*), BAR0 is the canonical DMA BAR.
    # Two realistic routings:
    #   Option A:  BAR4 = AXI Bridge Master -> m_axib -> (new crossbar
    #              master into dev_mem).  Requires new m_axib wiring on
    #              top of m_axi.
    #   Option B:  Enlarge BAR0 (DMA) so host mmap on BAR0 hits the MM
    #              descriptor engine -> m_axi_* -> dev_mem crossbar.
    #              No new BAR, reuses existing m_axi path.
    # RecoNIC's au200 reference enables BOTH en_axi_mm_qdma + en_bridge_slv
    # and relies on BAR4 as Bridge.  VERIFY whether their driver actually
    # uses BAR4 for MMIO writes or only uses BAR0 descriptor-engine DMA.
    # Until verified, prefer Option A (matches RecoNIC shape) with the
    # caveat that we must ALSO add m_axib wiring in a follow-on rev.
    # For this patch sketch we encode Option A to match RecoNIC; see §8
    # "phased rollout" for the fallback to Option B.

    CONFIG.pf0_bar4_enabled_qdma           {true}                     ;# VERIFY exact attr name
    CONFIG.pf0_bar4_type_qdma              {AXI_Bridge_Master}        ;# VERIFY enum string
    CONFIG.pf0_bar4_scale_qdma             {Gigabytes}                ;# VERIFY enum string
    CONFIG.pf0_bar4_size_qdma              {1}                        ;# 1 GiB; VERIFY allowed sizes
    CONFIG.pf0_bar4_prefetchable_qdma      {true}                     ;# VERIFY attr name
    CONFIG.pf0_bar4_64bit_qdma             {true}                     ;# VERIFY attr name (consume BAR4+BAR5)

    # PCIe BAR -> AXI address translation.  BAR4 lands on AXI address
    # 0x0000_0000_0000_0000 (the dev_mem crossbar's address map bases
    # DDR4 at 0x0; VERIFY from system_config_address_map.sv line
    # ranges 825-870 or wherever DDR4 is mapped).
    CONFIG.pf0_pciebar2axibar_4            {0x0000000000000000}       ;# VERIFY attr name
    CONFIG.axibar_highaddr_1               {0x000000003FFFFFFF}       ;# 1 GiB window top; VERIFY attr index

    # Keep PF1-3 unchanged (no BAR4 on secondary PFs for v4).
```

**VERIFY items for this block** (all flagged `;# VERIFY` inline):

- Exact TCL attribute spellings (`pf0_bar4_type_qdma`, `_scale_qdma`,
  `_prefetchable_qdma`, `_64bit_qdma`, `pciebar2axibar_4`).  PG302 Ch 2
  lists the IP customization UI labels; the TCL attribute names can be
  verified by running the IP-gen flow once and dumping
  `report_property [get_ips qdma_no_sriov]` or by consulting the IP's
  component.xml in the build dir.
- `pf0_bar4_type_qdma {AXI_Bridge_Master}` assumes the enum value matches
  the UI label verbatim.  PG302 p166 says "AXI Bridge Master" — the IP
  may use `{AXI_Bridge_Master}` or `{AXI Bridge Master}` or
  `{axi_bridge_master}`.  **Must be confirmed with IP-gen dry-run before
  committing.**
- `axibar_highaddr_1` index assumption — `axibar_highaddr_0` is already
  used for BAR0's DMA translation in v3.  PG302 indexes the highaddr
  registers per translation window, not per BAR; VERIFY which index BAR4
  maps to.
- BAR4 size: 1 GiB chosen as a balance between "enough to stage MR
  payloads up to 64 KiB × many QPs" and "not bigger than DDR4 itself" (16
  GiB total on AU200 but sharded among ERNIC queues + test buffers).
  Could bump to 4 GiB if address-map accommodates.

---

## 4. `qdma_no_sriov` IP port additions

Route X (`m_axi_*`) is the only new port group.  Route Z (`s_axib_*`) is
already present.  Route Z's canonical port list is in
`tier1b_qdma_audit.md` §188 (35 ports) — no change here.

### 4.1 `m_axi_*` — QDMA DMA master (AXI4-MM, 512b data, 64b addr)

Port list verbatim from RecoNIC's `qdma_subsystem_qdma_wrapper.v` lines
45-82 (RecoNIC = ground truth; PG302 v5.1 Table 13 matches):

```verilog
// AXI-MM master from QDMA DMA engine.  250 MHz axis_aclk domain.
// Directions below are relative to the QDMA IP.  In our wrapper module
// they are REVERSED (wrapper sees them as inputs/outputs from the IP
// instance, so awid is OUTPUT of the wrapper to the external fabric).

// Outputs from QDMA IP (wrapper forwards as outputs of wrapper module)
output [3:0]   m_axi_awid,
output [63:0]  m_axi_awaddr,
output [31:0]  m_axi_awuser,
output [7:0]   m_axi_awlen,
output [2:0]   m_axi_awsize,
output [1:0]   m_axi_awburst,
output [2:0]   m_axi_awprot,
output         m_axi_awvalid,
output         m_axi_awlock,
output [3:0]   m_axi_awcache,
output [511:0] m_axi_wdata,
output [63:0]  m_axi_wuser,
output [63:0]  m_axi_wstrb,
output         m_axi_wlast,
output         m_axi_wvalid,
output         m_axi_bready,
output [3:0]   m_axi_arid,
output [63:0]  m_axi_araddr,
output [31:0]  m_axi_aruser,
output [7:0]   m_axi_arlen,
output [2:0]   m_axi_arsize,
output [1:0]   m_axi_arburst,
output [2:0]   m_axi_arprot,
output         m_axi_arvalid,
output         m_axi_arlock,
output [3:0]   m_axi_arcache,
output         m_axi_rready,

// Inputs to QDMA IP (wrapper forwards as inputs to wrapper module)
input          m_axi_awready,
input          m_axi_wready,
input  [3:0]   m_axi_bid,
input  [1:0]   m_axi_bresp,
input          m_axi_bvalid,
input          m_axi_arready,
input  [3:0]   m_axi_rid,
input  [511:0] m_axi_rdata,
input  [1:0]   m_axi_rresp,
input          m_axi_rlast,
input          m_axi_rvalid,
```

**Port count: 38** (27 outputs + 11 inputs).

Differences vs RecoNIC `s_axib` port conventions (the v3 Route Z graft)
worth noting:

- `m_axi_awuser` / `m_axi_aruser` are 32-bit on `m_axi_*` vs 12-bit on
  `s_axib_*`.  They carry QDMA-internal function/queue metadata; our
  downstream crossbar does not use them — leave unconnected at the top
  level (not tied to 0 at the wrapper boundary — that's the IP's output).
- No `m_axi_awregion` / `m_axi_arregion` (differs from `s_axib_*`).
- `m_axi_wuser[63:0]` matches `s_axib_wuser[63:0]` (parity, 1 bit per
  byte).
- No `m_axi_awqos` / `m_axi_arqos` — same as `s_axib`.  **VERIFY**
  against PG302 v5.1 Ch 3 Table 13 — RecoNIC's wrapper is the evidence
  but the table should be cross-checked.

---

## 5. `qdma_subsystem_qdma_wrapper.v` edits

### 5.1 Module-header port additions

Insert the 38-port `m_axi_*` declarations at line ~200 (right after the
existing `s_axib_ruser` declaration, before the module header closes at
line ~205).  The exact insertion line: immediately after the current
line 200 (`output  [63:0] s_axib_ruser,`).

```verilog
  // ============================================================
  // Route X — QDMA AXI-MM master (DMA engine output).
  // Connected to dev_mem 4:1 crossbar via axi_interconnect_to_dev_mem
  // in open_nic_shell.sv.  250 MHz axis_aclk domain.
  // ============================================================
  output [3:0]   m_axi_awid,
  output [63:0]  m_axi_awaddr,
  output [31:0]  m_axi_awuser,
  output [7:0]   m_axi_awlen,
  output [2:0]   m_axi_awsize,
  output [1:0]   m_axi_awburst,
  output [2:0]   m_axi_awprot,
  output         m_axi_awvalid,
  input          m_axi_awready,
  output         m_axi_awlock,
  output [3:0]   m_axi_awcache,
  output [511:0] m_axi_wdata,
  output [63:0]  m_axi_wuser,
  output [63:0]  m_axi_wstrb,
  output         m_axi_wlast,
  output         m_axi_wvalid,
  input          m_axi_wready,
  input  [3:0]   m_axi_bid,
  input  [1:0]   m_axi_bresp,
  input          m_axi_bvalid,
  output         m_axi_bready,
  output [3:0]   m_axi_arid,
  output [63:0]  m_axi_araddr,
  output [31:0]  m_axi_aruser,
  output [7:0]   m_axi_arlen,
  output [2:0]   m_axi_arsize,
  output [1:0]   m_axi_arburst,
  output [2:0]   m_axi_arprot,
  output         m_axi_arvalid,
  input          m_axi_arready,
  output         m_axi_arlock,
  output [3:0]   m_axi_arcache,
  input  [3:0]   m_axi_rid,
  input  [511:0] m_axi_rdata,
  input  [1:0]   m_axi_rresp,
  input          m_axi_rlast,
  input          m_axi_rvalid,
  output         m_axi_rready,
```

### 5.2 `QDMA_ID==0` generate arm — append to `qdma_no_sriov qdma_inst`

Per `tier1b_qdma_audit.md` §172, last IP port in the `QDMA_ID==0` arm is
at wrapper line 456 (`.phy_ready(phy_ready)`).  Append the `m_axi_*`
connections immediately before the closing `);` of that `qdma_no_sriov`
instantiation.

```verilog
      .m_axi_awid                           (m_axi_awid),
      .m_axi_awaddr                         (m_axi_awaddr),
      .m_axi_awuser                         (m_axi_awuser),
      .m_axi_awlen                          (m_axi_awlen),
      .m_axi_awsize                         (m_axi_awsize),
      .m_axi_awburst                        (m_axi_awburst),
      .m_axi_awprot                         (m_axi_awprot),
      .m_axi_awvalid                        (m_axi_awvalid),
      .m_axi_awready                        (m_axi_awready),
      .m_axi_awlock                         (m_axi_awlock),
      .m_axi_awcache                        (m_axi_awcache),
      .m_axi_wdata                          (m_axi_wdata),
      .m_axi_wuser                          (m_axi_wuser),
      .m_axi_wstrb                          (m_axi_wstrb),
      .m_axi_wlast                          (m_axi_wlast),
      .m_axi_wvalid                         (m_axi_wvalid),
      .m_axi_wready                         (m_axi_wready),
      .m_axi_bid                            (m_axi_bid),
      .m_axi_bresp                          (m_axi_bresp),
      .m_axi_bvalid                         (m_axi_bvalid),
      .m_axi_bready                         (m_axi_bready),
      .m_axi_arid                           (m_axi_arid),
      .m_axi_araddr                         (m_axi_araddr),
      .m_axi_aruser                         (m_axi_aruser),
      .m_axi_arlen                          (m_axi_arlen),
      .m_axi_arsize                         (m_axi_arsize),
      .m_axi_arburst                        (m_axi_arburst),
      .m_axi_arprot                         (m_axi_arprot),
      .m_axi_arvalid                        (m_axi_arvalid),
      .m_axi_arready                        (m_axi_arready),
      .m_axi_arlock                         (m_axi_arlock),
      .m_axi_arcache                        (m_axi_arcache),
      .m_axi_rid                            (m_axi_rid),
      .m_axi_rdata                          (m_axi_rdata),
      .m_axi_rresp                          (m_axi_rresp),
      .m_axi_rlast                          (m_axi_rlast),
      .m_axi_rvalid                         (m_axi_rvalid),
      .m_axi_rready                         (m_axi_rready),
```

### 5.3 `QDMA_ID==1` generate arm — append to `qdma_no_sriov_1 qdma_inst`

Same block as 5.2, inserted before the closing `);` at wrapper line
~628.  (The wrapper generates different IP instances for the two QDMA
IDs; both are parameterized and both expose `m_axi_*`.)

For v4 only **ONE** QDMA is instantiated (`NUM_QDMA=1` in the v3 build
settings — check `script/build_2cmac_rdma_v3.sh` / `build.tcl`).  The
dual-generate structure is there for forward-compat.  If `NUM_QDMA=1`,
the `QDMA_ID==1` arm isn't elaborated — but the ports in the module
header must still be driven somehow.  **VERIFY** the build-time generate
elides the unused arm cleanly (Vivado's generate-for with elided arms
leaves module ports as hanging wires; the `USE_PHYS_FUNC==0` stub or a
top-level tie-off covers this).

---

## 6. `qdma_subsystem.sv` edits

### 6.1 Module-header passthroughs

Insert the same 38-port `m_axi_*` block at line ~147 (right after
`output [63:0] s_axib_ruser,` which closes the Route Z block).

```systemverilog
  // Route X — QDMA AXI-MM DMA master; lands on axi_interconnect_to_dev_mem
  // in open_nic_shell.sv as the `s_axi_qdma_mm_*` crossbar slave.
  output                   [3:0] m_axi_awid,
  output                  [63:0] m_axi_awaddr,
  output                  [31:0] m_axi_awuser,
  output                   [7:0] m_axi_awlen,
  output                   [2:0] m_axi_awsize,
  output                   [1:0] m_axi_awburst,
  output                   [2:0] m_axi_awprot,
  output                         m_axi_awvalid,
  input                          m_axi_awready,
  output                         m_axi_awlock,
  output                   [3:0] m_axi_awcache,
  output                 [511:0] m_axi_wdata,
  output                  [63:0] m_axi_wuser,
  output                  [63:0] m_axi_wstrb,
  output                         m_axi_wlast,
  output                         m_axi_wvalid,
  input                          m_axi_wready,
  input                    [3:0] m_axi_bid,
  input                    [1:0] m_axi_bresp,
  input                          m_axi_bvalid,
  output                         m_axi_bready,
  output                   [3:0] m_axi_arid,
  output                  [63:0] m_axi_araddr,
  output                  [31:0] m_axi_aruser,
  output                   [7:0] m_axi_arlen,
  output                   [2:0] m_axi_arsize,
  output                   [1:0] m_axi_arburst,
  output                   [2:0] m_axi_arprot,
  output                         m_axi_arvalid,
  input                          m_axi_arready,
  output                         m_axi_arlock,
  output                   [3:0] m_axi_arcache,
  input                    [3:0] m_axi_rid,
  input                  [511:0] m_axi_rdata,
  input                    [1:0] m_axi_rresp,
  input                          m_axi_rlast,
  input                          m_axi_rvalid,
  output                         m_axi_rready,
```

### 6.2 Connect to wrapper instantiation

At `qdma_subsystem_qdma_wrapper qdma_wrapper_inst` (in our file around
line 321; audit says instantiation closes at line 460/461) append the
`m_axi_*` hookups after the Route Z `s_axib_*` block:

```systemverilog
    .m_axi_awid                      (m_axi_awid),
    .m_axi_awaddr                    (m_axi_awaddr),
    .m_axi_awuser                    (m_axi_awuser),
    .m_axi_awlen                     (m_axi_awlen),
    .m_axi_awsize                    (m_axi_awsize),
    .m_axi_awburst                   (m_axi_awburst),
    .m_axi_awprot                    (m_axi_awprot),
    .m_axi_awvalid                   (m_axi_awvalid),
    .m_axi_awready                   (m_axi_awready),
    .m_axi_awlock                    (m_axi_awlock),
    .m_axi_awcache                   (m_axi_awcache),
    .m_axi_wdata                     (m_axi_wdata),
    .m_axi_wuser                     (m_axi_wuser),
    .m_axi_wstrb                     (m_axi_wstrb),
    .m_axi_wlast                     (m_axi_wlast),
    .m_axi_wvalid                    (m_axi_wvalid),
    .m_axi_wready                    (m_axi_wready),
    .m_axi_bid                       (m_axi_bid),
    .m_axi_bresp                     (m_axi_bresp),
    .m_axi_bvalid                    (m_axi_bvalid),
    .m_axi_bready                    (m_axi_bready),
    .m_axi_arid                      (m_axi_arid),
    .m_axi_araddr                    (m_axi_araddr),
    .m_axi_aruser                    (m_axi_aruser),
    .m_axi_arlen                     (m_axi_arlen),
    .m_axi_arsize                    (m_axi_arsize),
    .m_axi_arburst                   (m_axi_arburst),
    .m_axi_arprot                    (m_axi_arprot),
    .m_axi_arvalid                   (m_axi_arvalid),
    .m_axi_arready                   (m_axi_arready),
    .m_axi_arlock                    (m_axi_arlock),
    .m_axi_arcache                   (m_axi_arcache),
    .m_axi_rid                       (m_axi_rid),
    .m_axi_rdata                     (m_axi_rdata),
    .m_axi_rresp                     (m_axi_rresp),
    .m_axi_rlast                     (m_axi_rlast),
    .m_axi_rvalid                    (m_axi_rvalid),
    .m_axi_rready                    (m_axi_rready),
```

### 6.3 `USE_PHYS_FUNC==0` stub block (lines 532-600)

The lab/sim path has no QDMA IP.  Output ports of the subsystem for the
Route X interface must be driven to sane defaults so the enclosing shell
can instantiate without X-propagation.  Add after the existing s_axib
tie-offs:

```systemverilog
    // Route X idle tie-offs (stub mode, no QDMA IP traffic).
    assign m_axi_awid    = 4'd0;
    assign m_axi_awaddr  = 64'd0;
    assign m_axi_awuser  = 32'd0;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'd0;
    assign m_axi_awburst = 2'd0;
    assign m_axi_awprot  = 3'd0;
    assign m_axi_awvalid = 1'b0;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'd0;
    assign m_axi_wdata   = 512'd0;
    assign m_axi_wuser   = 64'd0;
    assign m_axi_wstrb   = 64'd0;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_bready  = 1'b1;
    assign m_axi_arid    = 4'd0;
    assign m_axi_araddr  = 64'd0;
    assign m_axi_aruser  = 32'd0;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'd0;
    assign m_axi_arburst = 2'd0;
    assign m_axi_arprot  = 3'd0;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'd0;
    assign m_axi_rready  = 1'b1;
    // Inputs (m_axi_awready etc.) are consumed by the stubbed master — ignored.
```

27 tie-offs.  The `*ready` inputs need no stub action.

---

## 7. `open_nic_shell.sv` edits — the crux

Four sub-tasks.  The existing Route Z wiring (lines 1833-1885) is
untouched.  The existing `axi_interconnect_to_dev_mem` crossbar at lines
~3423+ already has a `s_axi_qdma_mm_*` slave input — stubbed all-zero in
v3.  Route X's job is to UN-stub it.

### 7.1 Declare per-instance `m_axi_*` wires above the `qdma_subsystem`
instantiation (near where `qdma_s_axib_*` wires are declared, ~line
1262).  Use the same `NUM_QDMA` indexing pattern:

```verilog
  // Route X — QDMA DMA master outputs (per QDMA instance).
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_awid;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_awaddr;
  wire  [32*NUM_QDMA-1:0] qdma_m_axi_awuser;   // unused downstream
  wire   [8*NUM_QDMA-1:0] qdma_m_axi_awlen;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_awsize;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_awburst;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_awprot;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awready;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awlock;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_awcache;
  wire [512*NUM_QDMA-1:0] qdma_m_axi_wdata;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_wuser;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_wstrb;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wlast;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wready;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_bid;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_bresp;
  wire     [NUM_QDMA-1:0] qdma_m_axi_bvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_bready;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_arid;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_araddr;
  wire  [32*NUM_QDMA-1:0] qdma_m_axi_aruser;
  wire   [8*NUM_QDMA-1:0] qdma_m_axi_arlen;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_arsize;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_arburst;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_arprot;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arready;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arlock;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_arcache;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_rid;
  wire [512*NUM_QDMA-1:0] qdma_m_axi_rdata;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_rresp;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rlast;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rready;
```

### 7.2 Connect inside the `generate for (i=0; i<NUM_QDMA; i++)` block at
lines 1744-1885 (our existing `qdma_subsystem` inst).  Append to the
instantiation's port list:

```verilog
      .m_axi_awid                           (qdma_m_axi_awid   [`getvec(4,   i)]),
      .m_axi_awaddr                         (qdma_m_axi_awaddr [`getvec(64,  i)]),
      .m_axi_awuser                         (qdma_m_axi_awuser [`getvec(32,  i)]),
      .m_axi_awlen                          (qdma_m_axi_awlen  [`getvec(8,   i)]),
      .m_axi_awsize                         (qdma_m_axi_awsize [`getvec(3,   i)]),
      .m_axi_awburst                        (qdma_m_axi_awburst[`getvec(2,   i)]),
      .m_axi_awprot                         (qdma_m_axi_awprot [`getvec(3,   i)]),
      .m_axi_awvalid                        (qdma_m_axi_awvalid[i]),
      .m_axi_awready                        (qdma_m_axi_awready[i]),
      .m_axi_awlock                         (qdma_m_axi_awlock [i]),
      .m_axi_awcache                        (qdma_m_axi_awcache[`getvec(4,   i)]),
      .m_axi_wdata                          (qdma_m_axi_wdata  [`getvec(512, i)]),
      .m_axi_wuser                          (qdma_m_axi_wuser  [`getvec(64,  i)]),
      .m_axi_wstrb                          (qdma_m_axi_wstrb  [`getvec(64,  i)]),
      .m_axi_wlast                          (qdma_m_axi_wlast  [i]),
      .m_axi_wvalid                         (qdma_m_axi_wvalid [i]),
      .m_axi_wready                         (qdma_m_axi_wready [i]),
      .m_axi_bid                            (qdma_m_axi_bid    [`getvec(4,   i)]),
      .m_axi_bresp                          (qdma_m_axi_bresp  [`getvec(2,   i)]),
      .m_axi_bvalid                         (qdma_m_axi_bvalid [i]),
      .m_axi_bready                         (qdma_m_axi_bready [i]),
      .m_axi_arid                           (qdma_m_axi_arid   [`getvec(4,   i)]),
      .m_axi_araddr                         (qdma_m_axi_araddr [`getvec(64,  i)]),
      .m_axi_aruser                         (qdma_m_axi_aruser [`getvec(32,  i)]),
      .m_axi_arlen                          (qdma_m_axi_arlen  [`getvec(8,   i)]),
      .m_axi_arsize                         (qdma_m_axi_arsize [`getvec(3,   i)]),
      .m_axi_arburst                        (qdma_m_axi_arburst[`getvec(2,   i)]),
      .m_axi_arprot                         (qdma_m_axi_arprot [`getvec(3,   i)]),
      .m_axi_arvalid                        (qdma_m_axi_arvalid[i]),
      .m_axi_arready                        (qdma_m_axi_arready[i]),
      .m_axi_arlock                         (qdma_m_axi_arlock [i]),
      .m_axi_arcache                        (qdma_m_axi_arcache[`getvec(4,   i)]),
      .m_axi_rid                            (qdma_m_axi_rid    [`getvec(4,   i)]),
      .m_axi_rdata                          (qdma_m_axi_rdata  [`getvec(512, i)]),
      .m_axi_rresp                          (qdma_m_axi_rresp  [`getvec(2,   i)]),
      .m_axi_rlast                          (qdma_m_axi_rlast  [i]),
      .m_axi_rvalid                         (qdma_m_axi_rvalid [i]),
      .m_axi_rready                         (qdma_m_axi_rready [i]),
```

### 7.3 Un-stub the dev_mem crossbar's `s_axi_qdma_mm_*` input

Replace the all-zero stub at lines 3425-... (inside the
`axi_interconnect_to_dev_mem axi_interconnect_to_dev_mem_inst` port map)
with live wires from `qdma_m_axi_*[0]` (the single-QDMA case).  For
`NUM_QDMA=1` this is a direct bitslice; for `NUM_QDMA>1` we need a
master-side 2:1 arbiter feeding `s_axi_qdma_mm_*` — **not in scope for
v4**; see §8 phased rollout.

```verilog
  // Route X — QDMA[0] m_axi_* drives the dev_mem crossbar's QDMA-MM slave.
  // Replaces the all-zero stub that v3 had at this same instantiation.
  axi_interconnect_to_dev_mem axi_interconnect_to_dev_mem_inst (
    .s_axi_qdma_mm_awid     ({1'd0, qdma_m_axi_awid  [`getvec(4,   0)]}),
    .s_axi_qdma_mm_awaddr   (       qdma_m_axi_awaddr[`getvec(64,  0)]),
    .s_axi_qdma_mm_awqos    (4'd0),                              // QDMA m_axi has no awqos — tie off
    .s_axi_qdma_mm_awlen    (       qdma_m_axi_awlen [`getvec(8,   0)]),
    .s_axi_qdma_mm_awsize   (       qdma_m_axi_awsize[`getvec(3,   0)]),
    .s_axi_qdma_mm_awburst  (       qdma_m_axi_awburst[`getvec(2,  0)]),
    .s_axi_qdma_mm_awcache  (       qdma_m_axi_awcache[`getvec(4,  0)]),
    .s_axi_qdma_mm_awprot   (       qdma_m_axi_awprot[`getvec(3,   0)]),
    .s_axi_qdma_mm_awvalid  (       qdma_m_axi_awvalid[0]),
    .s_axi_qdma_mm_awready  (       qdma_m_axi_awready[0]),
    .s_axi_qdma_mm_wdata    (       qdma_m_axi_wdata [`getvec(512, 0)]),
    .s_axi_qdma_mm_wstrb    (       qdma_m_axi_wstrb [`getvec(64,  0)]),
    .s_axi_qdma_mm_wlast    (       qdma_m_axi_wlast [0]),
    .s_axi_qdma_mm_wvalid   (       qdma_m_axi_wvalid[0]),
    .s_axi_qdma_mm_wready   (       qdma_m_axi_wready[0]),
    .s_axi_qdma_mm_awlock   (       qdma_m_axi_awlock[0]),
    .s_axi_qdma_mm_bid      (       qdma_m_axi_bid   [`getvec(4,   0)]),
    .s_axi_qdma_mm_bresp    (       qdma_m_axi_bresp [`getvec(2,   0)]),
    .s_axi_qdma_mm_bvalid   (       qdma_m_axi_bvalid[0]),
    .s_axi_qdma_mm_bready   (       qdma_m_axi_bready[0]),
    .s_axi_qdma_mm_arid     ({1'd0, qdma_m_axi_arid  [`getvec(4,   0)]}),
    .s_axi_qdma_mm_araddr   (       qdma_m_axi_araddr[`getvec(64,  0)]),
    .s_axi_qdma_mm_arlen    (       qdma_m_axi_arlen [`getvec(8,   0)]),
    .s_axi_qdma_mm_arsize   (       qdma_m_axi_arsize[`getvec(3,   0)]),
    .s_axi_qdma_mm_arburst  (       qdma_m_axi_arburst[`getvec(2,  0)]),
    .s_axi_qdma_mm_arcache  (       qdma_m_axi_arcache[`getvec(4,  0)]),
    .s_axi_qdma_mm_arprot   (       qdma_m_axi_arprot[`getvec(3,   0)]),
    .s_axi_qdma_mm_arvalid  (       qdma_m_axi_arvalid[0]),
    .s_axi_qdma_mm_arready  (       qdma_m_axi_arready[0]),
    .s_axi_qdma_mm_rid      (       qdma_m_axi_rid   [`getvec(4,   0)]),
    .s_axi_qdma_mm_rdata    (       qdma_m_axi_rdata [`getvec(512, 0)]),
    .s_axi_qdma_mm_rresp    (       qdma_m_axi_rresp [`getvec(2,   0)]),
    .s_axi_qdma_mm_rlast    (       qdma_m_axi_rlast [0]),
    .s_axi_qdma_mm_rvalid   (       qdma_m_axi_rvalid[0]),
    .s_axi_qdma_mm_rready   (       qdma_m_axi_rready[0]),
    .s_axi_qdma_mm_arlock   (       qdma_m_axi_arlock[0]),
    .s_axi_qdma_mm_arqos    (4'd0),
    // (rest of instantiation — compute_logic + other masters — unchanged)
    …
  );
```

**Tie-off notes** (mirror of Decision 2 from `tier1b_qdma_audit.md`):

- QDMA `m_axi_*` has **no** `awqos/arqos` ports; the crossbar slave
  requires them — tie to `4'd0`.
- QDMA `m_axi_*` has **no** `awregion/arregion` ports; if the crossbar
  exposes them, tie to `4'd0` (not shown above — the existing RecoNIC
  `axi_4to1_interconnect_to_dev_mem` port list at lines 2535-2569 does
  not include `*region` for the QDMA-MM slave, confirming this works).
- QDMA `m_axi_awid/arid[3:0]` must be zero-extended to the crossbar's
  `[4:0]` ID width (matching existing `{1'd0, axi_qdma_mm_awid}` pattern
  in v3's stub at line 3424).
- QDMA `m_axi_awuser/aruser[31:0]` carries internal function/queue tags
  — **leave unconnected** at the crossbar (not a port on the
  `axi_interconnect_to_dev_mem` IP).
- QDMA `m_axi_wuser[63:0]` is parity — also unconnected at the crossbar.

### 7.4 Remove stale stub comment at lines 3419-3422

Delete the pre-existing comment:

```verilog
  // v3 STUB: axi_sys_mem_mux output drives the QDMA bridge for
  // host-memory DMA from ERNIC.  This will be connected when the
  // QDMA s_axib port is wired.
```

Replace with:

```verilog
  // Route X — host BAR4 -> QDMA m_axi_* DMA master -> dev_mem crossbar
  // -> DDR4 slave.  QDMA[0] is the sole m_axi producer in v4 (NUM_QDMA=1).
  // Route Z — axi_sys_mem_mux_* -> qdma_subsystem[0].s_axib_* -> host
  // memory, wired above at line ~1833 (unchanged from v3).
```

---

## 8. Phased rollout recommendation

**Recommended**: ship Route X and Route Z together in v4.  Justification:

- Route Z is already committed in v3 RTL; the only v4 change on that
  path is `en_axi_mm_qdma=true` in the TCL, which doesn't touch Route Z
  logic.  No regression risk.
- Route X's patch surface is ~140 LoC across 4 files; all additive.  No
  existing signal semantics change.
- The alternative (split into v4a = Route X only, v4b = Route Z
  preserved) is effectively what v4 is — v3 already has Route Z.

**Fallback if BAR4 sizing or IP-gen `pf0_bar4_*` attributes don't
elaborate cleanly**:

- Option B (BAR0 enlargement): drop the BAR4 additions.  Enlarge BAR0
  (the DMA BAR) from the default 256 KB to 1 GiB, typed DMA.  Host
  descriptor-engine MM writes land on `m_axi_*` via the same dev_mem
  crossbar path.  Driver impact: `memcpy_toio` replaced with a
  descriptor submission; more driver work but bypasses all BAR4
  TCL-attribute guesswork.
- This fallback is mutually exclusive with BAR4 (only one BAR can be
  typed DMA per PG302 p166).  Decision point: if IP-gen with the BAR4
  attrs fails, flip to Option B in a v4.1.

---

## 9. Build process

```bash
source /opt/amd/Vivado/2024.2/settings64.sh

# Bump the tag (preserve v3 build tree).
cp /home/alex/mpi-shfs/fpga/open-nic-shell/script/build_2cmac_rdma_v3.sh \
   /home/alex/mpi-shfs/fpga/open-nic-shell/script/build_2cmac_rdma_v4.sh
sed -i 's/2cmac_rdma_v3/2cmac_rdma_v4/g' \
   /home/alex/mpi-shfs/fpga/open-nic-shell/script/build_2cmac_rdma_v4.sh

# 1) IP-gen dry-run to catch `pf0_bar4_*` attr-name mistakes cheaply.
cd /home/alex/mpi-shfs/fpga/open-nic-shell/script
./build_2cmac_rdma_v2_ipgen.sh            # reuses v2 ipgen infra; works on current TCL

# 2) Inspect generated IP's BAR table.
grep -E "BAR4|pf0_bar4|AXI_Bridge_Master" \
   /home/alex/mpi-shfs/fpga/open-nic-shell/build/au200_2cmac_rdma_v4/vivado_ip/qdma_no_sriov/synth/qdma_no_sriov.sv \
   | head -40

# 3) Full build (4-8 hours).
./build_2cmac_rdma_v4.sh 2>&1 | tee build_v4_full.log

# 4) Flash (after visual review of build log).
cd /home/alex/mpi-shfs/fpga/open-nic-shell/script
./program_fpga.sh build/au200_2cmac_rdma_v4/open_nic_shell.bit
```

Expected artifacts:

- `build/au200_2cmac_rdma_v4/open_nic_shell.bit`
- `build/au200_2cmac_rdma_v4/open_nic_shell.mcs`
- Timing summary in `build/au200_2cmac_rdma_v4/impl_1/open_nic_shell_utilization_placed.rpt`

---

## 10. File-by-file patch size estimate

| File | Adds (lines) | Modifies (lines) | Notes |
|---|---|---|---|
| `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` | 8 | 2 | +7 CONFIG.pf0_bar4_*; flip `dma_intf_sel`, `en_axi_mm_qdma` |
| `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v` | ~110 | 0 | 38 port decls + 38 connects × 2 generate arms (only arm 0 if NUM_QDMA=1) |
| `src/qdma_subsystem/qdma_subsystem.sv` | ~107 | 0 | 38 passthrough decls + 38 connects + 27-line stub tie-off |
| `src/open_nic_shell.sv` | ~120 | ~37 (un-stub crossbar slot) | 38 per-QDMA wires + 38 instance-port connects + un-stub `s_axi_qdma_mm_*` + delete stale comment + re-write |

**Total new RTL**: ~345 lines (single arm only; +37 if `NUM_QDMA=2`).
**Total modified RTL**: ~40 lines (all in `open_nic_shell.sv`).
**TCL**: ~10 lines.

---

## 11. VERIFY items — consolidated list

Ranked by flash-blocking risk.

### Must-verify-before-IP-gen (TCL attribute spellings)

1. **`pf0_bar4_type_qdma` attribute name and enum value**.  PG302 p166
   lists the UI label "Type" with enum "AXI Bridge Master" but the
   Vivado TCL attribute for BAR4 specifically may be named differently
   (e.g., `pf0_bar4_type`, `pf0_bar4_type_qdma`, or the enum may encode
   differently — `{AXI_BRIDGE_MASTER}` vs `{AXI Bridge Master}`).
   Validate with `report_property [get_ips qdma_no_sriov]` after a dry
   IP-gen.
2. **`pf0_bar4_enabled_qdma`** — PG302 refers to "deselect the checkbox
   to disable the BAR"; the corresponding TCL attr may be
   `pf0_bar4_enabled_qdma`, `pf0_bar4_qdma`, or implicit-on-size-set.
3. **`pf0_bar4_scale_qdma`, `pf0_bar4_size_qdma`**.  Follow the pattern
   already established by `pf0_bar2_scale_qdma {Megabytes}` +
   `pf0_bar2_size_qdma {16}` in our current TCL.  High-confidence
   extrapolation but should be confirmed.
4. **`pf0_bar4_prefetchable_qdma`, `pf0_bar4_64bit_qdma`**.  Required
   for a 1-GiB BAR (must be 64-bit).  Attribute names are pattern
   guesses.
5. **`pciebar2axibar_4` attribute suffix**.  Existing TCL uses
   `pf[0-3]_pciebar2axibar_2`.  The `_4` suffix maps to BAR4 per the
   index convention.  VERIFY the attribute is spelled as
   `pf0_pciebar2axibar_4` (per-PF prefix) or `pciebar2axibar_4` (no
   prefix).
6. **`axibar_highaddr_1` index**.  `axibar_highaddr_0` already used for
   BAR0's DMA translation.  PG302 Ch 6 describes the highaddr table
   indexed by translation window, not by BAR number.  VERIFY the index
   mapping for BAR4 — may be `_4`, not `_1`.

### Must-verify-before-RTL-compile (port list)

7. **PG302 v5.1 Ch 3 Table 13** — confirm the 38 `m_axi_*` ports listed
   in §4.1 are exhaustive and have the widths claimed.  RecoNIC's
   wrapper is the reference but may be one minor revision off from PG302
   v5.1.  Specifically `m_axi_awuser[31:0]` width (RecoNIC shows 32;
   some older QDMA variants use 28 or 16).

### Should-verify-before-flash (correctness)

8. **DDR4 AXI base address**.  §3 assumes DDR4 maps to
   `0x0000_0000_0000_0000` on the dev_mem crossbar.  Cross-check
   `src/utility/vivado_ip/dev_mem_4to1_axi_crossbar.tcl` (or whatever
   our crossbar config file is) for the slave-0 `axi_addr_offset` and
   match `pciebar2axibar_4` to it.
9. **Address window overlap**.  QDMA's `axibar_highaddr_0` is
   `0x000000FFFFFFFFFF` (high end of BAR0's translation).  BAR4's
   highaddr needs to not collide — VERIFY the IP's two translation
   windows don't share registers.
10. **BAR size vs DDR4 real estate**.  AU200 has 16 GiB DDR4; if ERNIC0
    +ERNIC1 plus the plugin use ~2 GiB, 1 GiB BAR4 is comfortable.
    Confirm by checking `f4_ddr4_allocator_design.md`.
11. **`NUM_QDMA=1` vs `=2` in v3**.  The `.sh` build script caps this
    parameter.  `tier1b_qdma_audit.md` references dual-QDMA
    infrastructure, but the acceptance Phase 1 runs with a single
    QDMA.  The §7.2 generate-for block is correct for either value;
    §7.3 assumes `NUM_QDMA=1`.  Confirm before build.
12. **Timing closure (WNS)**.  Extra 38-port crossbar slave adds
    250 MHz logic.  RecoNIC closes; v3 closed with the stubbed crossbar
    slot; un-stubbing should not add critical-path pressure — but
    budget one extra rebuild iteration for post-route timing fixes.

### Low-risk (nice-to-verify)

13. **`USE_PHYS_FUNC==0` stub consistency**.  Tier 1b audit's Session 2
    worked out the s_axib tie-offs here; mirror-apply to m_axi (§6.3).
14. **Route Z still wires through un-changed**.  Regression-check that
    the `axi_sys_mem_mux_*` → `s_axib_*` path at open_nic_shell.sv
    lines 1833-1885 is untouched in v4.

---

## 12. Verification plan (post-flash)

1. `lspci -vv -s <bdf>` → BAR4 present, size matches §3 choice,
   prefetchable bit set, 64-bit.
2. Driver boot: `pci_request_regions` + `pci_iomap(pdev, 4, 0)`
   succeeds; log the iomem cookie.
3. DDR4 round-trip probe (new tool, `tools/probe_bar4_ddr4.sh` — sketch
   below):
   ```bash
   #!/bin/bash
   # Writes MAGIC to BAR4 offsets covering a handful of DDR4 rows, then
   # reads them back.  Passes if all 64 reads match MAGIC.
   sudo insmod onic.ko probe_bar4=1
   dmesg | grep "bar4_probe: "
   # expected: "bar4_probe: 64/64 round-trips OK"
   ```
4. CSR regression: `tools/phase1_csr_bringup.sh` — expect 27/27 on both
   ERNICs (BAR2 path untouched).
5. Route Z regression: ERNIC-initiated host-memory DMA through
   `s_axib`.  If the B3/B5 QP lifecycle tests are already in shape,
   re-run `rdma_test_qp_create`.
6. B7 acceptance: load B7 driver, run `ibv_rc_pingpong`.  Expect
   progress past `post_recv × 16` + state transitions + one
   `post_send`, then `-EOPNOTSUPP` at `poll_cq` (B8 stub).

---

## 13. Risks summary

| Risk | Mitigation |
|---|---|
| BAR4 TCL attr names wrong | §11 items 1-6; IP-gen dry-run catches cheaply |
| BAR4 on PF0 conflicts with existing BAR0/BAR2 | v3 uses BAR0 (DMA) + BAR2 (AXI Lite Master); BAR4 free per PG302 default layout |
| m_axi path re-opens the Session 4 opt_design orphan-LUT bug | Session 5 fix (`axibar_notranslate=true`) retained in §3; orphan-LUT was on `s_axil_csr` path which remains untouched |
| Timing regression from un-stubbed crossbar slave | Budget one extra post-route iteration; RecoNIC closes with same crossbar |
| Driver regression from MSI-X vector-count change | MSIX kept at `01F` (unchanged); no driver impact |
| Stub-block (`USE_PHYS_FUNC==0`) left inconsistent | §6.3 mirrors Route Z stub pattern |
| `NUM_QDMA=2` path leaks the arm-1 m_axi as dangling | §5.3 note; verify single-arm elides cleanly or add explicit tie-off |

---

## 14. Cross-references

- `tier1b_qdma_audit.md` — Route Z history (Sessions 1-5), port list
  (§188), insertion points (§170+).
- `f4_ddr4_allocator_design.md` — DDR4 layout (to confirm BAR4 size fits
  without stomping ERNIC buffer regions).
- `b7_post_send_recv.md` — the user of this bitstream; driver path that
  exercises BAR4 + DDR4.
- `b7_blocker_enablement.md` — previous blocker analysis.
- `production_roadmap.md` — where v4 fits in the rebuild schedule.
- RecoNIC reference: `/home/alex/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/`:
  - `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` (IP config canon).
  - `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v:45-82` (m_axi port list canon).
  - `src/open_nic_shell.sv:2535-2569` (dev_mem 4:1 crossbar instantiation).
- PG302 v5.1: `/home/alex/Downloads/XilinxAmdDownloads/xilinx-general-docs/pcie/pg302-qdma.md`:
  - p162 Fig 27 (Basic Tab — independent Bridge/DMA toggles).
  - p166-167 (BAR Type enum: DMA / AXI Lite Master / AXI Bridge Master).
  - Ch 3 Table 13 (`m_axi_*` port list).
  - Ch 6 (BAR-to-AXI translation mechanism).
