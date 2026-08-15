# au55n / Varium C1100 — 2 CMAC + 2 QDMA @ Gen4 x8 — design

Status: **implemented, not yet synthesized or simulated.**

- Device facts (§3, §7) — resolved in Vivado against `xcu55n-fsvh2892-2L-e`.
- IP customization — verified by reading the generated `.xci` back.
- RTL (§5.2 qid path, §5.3 plugin) — written, and every touched module
  elaborates cleanly for both `NUM_QDMA=1` and `NUM_QDMA=2`.
- **Not done:** no top-level synthesis, no place & route, no simulation, no
  traffic. Do not treat a bitstream from this as trustworthy yet — see §8.

Scope rule for this whole change: **the au200 and au250 `eth_1pf_2cmac_qid`
targets must not change.** Everything below is either a new file, a
board-scoped file under `constr/au55n/` or `*_au55n.tcl`, or a change guarded by
`` `ifdef __au55n__ `` / `$num_qdma == 2`. No shared code path is altered for a
1-QDMA build. §8 lists how that is verified.

---

## 1. Target

| Parameter | Value | Note |
|---|---|---|
| Board | `au55n` | `xcu55n-fsvh2892-2L-e`, `xilinx.com:au55n:part0:1.0` |
| `num_cmac_port` | 2 | QSFP28 cage 0 → GTY bank 130, cage 1 → bank 131 |
| `num_qdma` | 2 | two independent PCIe endpoints |
| PCIe per endpoint | **Gen4 x8** | `PCIE4C` maximum; x16 is Gen3-only |
| `num_phys_func` | 1 per endpoint | matches the existing au200/au250 1PF style |
| `num_queue` | 2048 | same as au200/au250 |
| Host requirement | slot bifurcated **x8x8** in BIOS | else endpoint B never trains |

The card enumerates as **two PCI devices**, one per endpoint, each with 1 PF.

## 2. Why "2 QDMA" and not "one bifurcated QDMA"

A QDMA instance is one PCIe endpoint bound to one `PCIE4C` hard block. There is
no bifurcation switch in the IP. `PCIE4C` tops out at x16 Gen3 / **x8 Gen4**, so
two Gen4 x8 links require two hard blocks and therefore two IP instances.

DS1003 states the C1100 supports "Gen3 x16 **or** dual Gen4 x8", and the AMD
board file exposes two edge-connector reference-clock pairs (`AR15/AR14` =
`PCIE_REFCLK1`, `AL15/AL14` = `PCIE_REFCLK0`), which is exactly what two
endpoints need. The shell is already parameterized for this: `NUM_QDMA` is a
documented 1–2 build option and `qdma_subsystem_qdma_wrapper.v` already selects
`qdma_no_sriov` for `QDMA_ID==0` and `qdma_no_sriov_1` otherwise.

Precedent in this repo: `au45n` builds two QDMA subsystems, the second at
`X8` / `16.0_GT/s` with an explicit `CONFIG.pcie_blk_locn`. Note the difference —
au45n's second endpoint is a *separate physical link* to an on-board ARM, not a
bifurcated slot half. It proves the IP configuration works; it is not a
bifurcation reference.

## 3. Lane and clock budget

One x16 edge connector, split 8 + 8. Lane pins are from
`board_files/Xilinx/au55n/part0_pins.xml`.

All of the following is **resolved against the real device** (Vivado 2024.2,
`link_design` on an empty netlist for `xcu55n-fsvh2892-2L-e`, then `get_sites` /
`get_package_pins`). Nothing here is inferred from the board file.

PCIe hard-block inventory:

```
PCIE4CE4_X0Y0  clkrgn X0Y0      PCIE4CE4_X1Y0  clkrgn X7Y0
PCIE4CE4_X0Y1  clkrgn X0Y3      PCIE4CE4_X1Y1  clkrgn X7Y3
PCIE40E4_X0Y0  clkrgn X7Y4   <- PCIE40, Gen3 only, not usable for Gen4 x8
```

Edge-lane → quad map (X1 column, right side of the die):

| Edge lanes | GT bank | Quad | Channels | Clock region |
|---|---|---|---|---|
| 0–3 | 227 | `X1Y3` | `X1Y12..15` | X7Y3 |
| 4–7 | 226 | `X1Y2` | `X1Y8..11` | X7Y2 |
| 8–11 | 225 | `X1Y1` | `X1Y4..7` | X7Y1 |
| 12–15 | 224 | `X1Y0` | `X1Y0..3` | X7Y0 |

Reference clocks: `AR15/AR14` (`PCIE_REFCLK1`) → bank 225 = quad `X1Y1`;
`AL15/AL14` (`PCIE_REFCLK0`) → bank 227 = quad `X1Y3`.

**The refclk split is forced, and it is the opposite of the intuitive reading.**
A GT reference clock must be within 2 quads of every transceiver on its link:

| | endpoint A quads X1Y3, X1Y2 | endpoint B quads X1Y1, X1Y0 |
|---|---|---|
| `AR15` (X1Y1) | dist 2, 1 → legal | dist 0, 1 → **legal** |
| `AL15` (X1Y3) | dist 0, 1 → **legal** | dist 2, **3** → `[Place 30-739]` |

Only `AR15` can serve endpoint B, so **`AR15` moves to endpoint B** and endpoint
A takes `AL15`. Note `AR15` is the pin the current single-QDMA au55n build gives
endpoint 0 — and for a Gen3 x16 link spanning all four quads it is the *only*
legal pair (distances 1,0,1,2), which is exactly why AMD chose it. Same
reasoning as the U50 warning in `constr/au50/pins.xdc`.

| | Endpoint A (`QDMA_ID=0`) | Endpoint B (`QDMA_ID=1`) |
|---|---|---|
| Edge lanes | 0–7 | 8–15 |
| Quads | `X1Y3` + `X1Y2` (banks 227, 226) | `X1Y1` + `X1Y0` (banks 225, 224) |
| PCIe block | `PCIE4C_X1Y1` (clkrgn X7Y3) | `PCIE4C_X1Y0` (clkrgn X7Y0) |
| Refclk | `AL15/AL14` = `PCIE_REFCLK0` | `AR15/AR14` = `PCIE_REFCLK1` |
| `select_quad` | `GTY_Quad_227` | `GTY_Quad_225` |
| PERST | `BF41` — **shared, one pin for both** | same pin |
| TX pins | AL11/AL10, AM9/AM8, AN11/AN10, AP9/AP8, AR11/AR10, AR7/AR6, AT9/AT8, AU11/AU10 | AU7/AU6, AV9/AV8, AW11/AW10, AY9/AY8, BA11/BA10, BB9/BB8, BC11/BC10, BC7/BC6 |
| RX pins | AL2/AL1, AM4/AM3, AN6/AN5, AN2/AN1, AP4/AP3, AR2/AR1, AT4/AT3, AU2/AU1 | AV4/AV3, AW6/AW5, AW2/AW1, AY4/AY3, BA6/BA5, BA2/BA1, BB4/BB3, BC2/BC1 |

**Consequence: neither endpoint can use the board-flow automation.** The board
file's `pcie_refclk` interface maps to `PCIE_REFCLK1` (`AR15`), so
`PCIE_BOARD_INTERFACE pci_express_x8` would claim `AR15` for endpoint A — the one
pin endpoint B cannot do without. Two ports also cannot share a `PACKAGE_PIN`.
So **both** endpoints go `Custom` (`disable_gt_loc true`, `en_gt_selection
false`, explicit `pcie_blk_locn` + `select_quad`), following the au45n pattern,
and **all 32 lane pins plus both refclks are constrained by hand** in
`constr/au55n/pins.xdc`. Today's au55n build constrains none of them, inheriting
them from the board file; that automation is lost here and the pin table below
replaces it.

One board-level fact still worth confirming on the schematic: a standard PCIe
CEM x16 slot supplies a single REFCLK pair, so `PCIE_REFCLK0` and `PCIE_REFCLK1`
are almost certainly buffered copies of that one clock fanned out to two GT banks
— which is precisely what a bifurcated design needs, and is consistent with both
pairs belonging to the board file's `pcie_8lane_edge` component. If instead
`AL15` is unpopulated on this card revision, dual x8 would need SRIS with a local
clock, which is a materially bigger change. Worth a continuity check before
committing to the layout.

**Shared PERST is the one place the RTL shape has to change.** The top level
declares `input [NUM_QDMA-1:0] pcie_rstn`, i.e. one reset port per endpoint. The
C1100 has a single `PCIE_PERST_LS_65` pin, and two ports cannot share one
`PACKAGE_PIN`. Fix: an `` `ifdef __au55n__ `` port declaration with a scalar
`pcie_rstn`, fanned out to both wrapper instances. Both endpoints then reset
together, which is correct behaviour for a bifurcated slot anyway.

## 4. Files to add or change

New files (zero risk to other boards):

| File | Purpose |
|---|---|
| `src/qdma_subsystem/vivado_ip/qdma_no_sriov_1_au55n.tcl` | endpoint B IP: Gen4 x8, manual GT/block placement |
| `script/build_au55n_2qdma_2cmac.sh` | build wrapper, mirrors `build_eth_1pf_2cmac_qid.sh` |
| this document | |

Changed files, all board- or parameter-scoped:

| File | Change | Guard |
|---|---|---|
| `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au55n.tcl` | Gen4 x8 instead of Gen3 x16 | `if {$num_qdma == 2}` — the 1-QDMA au55n build keeps Gen3 x16 byte-for-byte |
| `constr/au55n/pins.xdc` | 2nd refclk + endpoint-B lane pins | `if {[llength [get_ports pcie_refclk_p]] >= 2}`, the idiom already used for `qsfp_refclk_p` |
| `constr/au55n/timing.xdc` | per-bit `create_clock`, 2nd QDMA pblock | same |
| `src/open_nic_shell.sv` | scalar `pcie_rstn`, 8-lane-per-endpoint port widths | `` `ifdef __au55n__ `` |
| `src/qdma_subsystem/qdma_subsystem_function.sv` | H2C carries qid in TUSER; side-FIFO deleted; C2H points at the 107-bit converter | `QDMA_ID != 0` branch only |
| `src/qdma_subsystem/vivado_ip/qdma_subsystem_clk_converter_{h2c,c2h}.tcl` | **new** — TUSER 27 / 107, replacing the single 16-bit converter | built only when `num_qdma > 1` |
| `src/qdma_subsystem/vivado_ip/vivado_ip.tcl` | build the two new converters | `if {$num_qdma > 1}` |
| `plugin/eth_2cmac_1pf/eth_2cmac_1pf_250mhz.sv` | 1:1 pinned mode; diag CSR no longer gated off at `NUM_QDMA>1` | `PIN_1TO1` localparam |

Driver: **no change required.** `onic_pci_tbl` in `open-nic-driver/onic_main.c`
already carries the Gen4 x8 IDs (`0x9048`/`0x9148`/`0x9248`/`0x9348`); the QDMA
IP derives its device ID from gen+width, so both endpoints come up as `0x9048`
and the kernel binds two independent `onic` instances, distinguished by BDF.

## 5. The three real work items

### 5.1 IP and constraints (mechanical)

Covered by the files in §4. The only judgement calls are the two TBDs in §7.

### 5.2 The `QDMA_ID != 0` qid path — FIXED

`docs/03-qdma-subsystem.md` §3.3 and the comment at
`src/qdma_subsystem/qdma_subsystem_function.sv:305–310` are explicit:

> The `QDMA_ID != 0` path (a second QDMA instance) still uses the old
> `clk_converter` + side-FIFO scheme and is **not** used on au200. If you ever
> build a `NUM_QDMA=2` target, that path must be re-verified.

and in the RTL:

> RACY legacy path … the empty-fallback skews qid by one packet at boundaries
> and misroutes CMAC0 traffic to CMAC1.

So endpoint B, as the code stands today, will mis-steer packets at packet
boundaries. This is a silent data-path corruption, not a build failure — a
`NUM_QDMA=2` bitstream will build and mostly work, which is the dangerous case.

**Done.** Note the two branches are *not* interchangeable: `QDMA_ID==0` uses a
same-clock `axi_stream_register_slice`, while `QDMA_ID!=0` needs a real CDC —
every QDMA instance derives its own 250 MHz `axis_aclk` from its own PCIe core,
so instance != 0 must cross into the master's domain. The fix was therefore to
*widen the clock converter's TUSER*, not to swap in the slice:

- `qdma_subsystem_clk_converter` (TUSER=16) is replaced by two correctly-sized
  IPs: `qdma_subsystem_clk_converter_h2c` (27) and `..._c2h` (107). One IP could
  not serve both directions.
- H2C now carries `{qid, size}` through the converter and the side-FIFO is
  deleted outright.
- C2H already drove all 107 bits through the converter; only the IP was still
  built at 16 bits, silently truncating qid and ptp_ts. No width error is
  possible there — the IP's port width is a parameter.

The packings, which must agree across the slice, the converters and the
buf_fifo:

- H2C: 27-bit TUSER — `[26:16]` = `qid[10:0]`, `[15:0]` = `size[15:0]`.
- C2H: 107-bit TUSER — `[106:96]` = `qid[10:0]`, `[95:16]` = `ptp_ts[79:0]`,
  `[15:0]` = `size[15:0]`.

The `QDMA_ID==0` branch is the reference implementation; this is a graft of
known-good code, not new design. All three IP widths (slice, and both
converters it replaces) must agree or the qid corrupts silently — flagged in
§3.4 of the subsystem doc as the highest-risk part of the original graft.

### 5.3 The qid-steering plugin — EXTENDED to `NUM_QDMA=2`

`plugin/eth_2cmac_1pf/INTEGRATION_CONTRACT.md:128`:

> `NUM_INTF` (= `NUM_CMAC_PORT`) supported 2..8. **`NUM_QDMA` expected 1.**

`box_250mhz.sv`'s ports are already scaled by `NUM_PHYS_FUNC*NUM_QDMA`, so the
shell side presents two full sets of H2C/C2H interfaces. The plugin's internals
are what assume one. Per the README, the p2p reference has one ingress and one
egress switch per QDMA PF (U45N has four switches total for its 2 QDMA × 2 PF).

**Chosen mapping: 1:1 pinned.**

```
QSFP0 ─ CMAC0 ──── QDMA A (edge lanes 0-7,  Gen4 x8) ─ BDF x ─ onic netdev 0
QSFP1 ─ CMAC1 ──── QDMA B (edge lanes 8-15, Gen4 x8) ─ BDF y ─ onic netdev 1
```

Two independent 100G NICs sharing one card. Consequences for the plugin, which
is why this is the cheapest of the options considered:

- **No AXI4-stream switches and no steering policy.** Each `(QDMA, CMAC)` pair
  is a private path, so the existing per-PF steering is instantiated twice
  rather than generalized. Compare option (b) below, which needs 4 switches.
- **The qid space stays independent per endpoint.** Each endpoint has its own
  2048 queues and its own qid numbering; nothing has to be partitioned or made
  globally unique. The absolute-qid steering already in `eth_2cmac_1pf` keeps
  working unchanged *within* a pair.
- **`NUM_INTF` per steering instance drops from 2 to 1.** The plugin's current
  job — deciding which of 2 CMACs a packet belongs to from its qid — disappears
  inside a pair, because a pair has exactly one CMAC. This is a simplification
  of the existing logic, not an extension of it. Re-check the qid→CMAC decode
  for the degenerate `NUM_INTF=1` case rather than assuming it collapses cleanly.
- **No cross-endpoint backpressure coupling.** `flow_ctrl_en` pause generation
  stays per-CMAC, as today, and now also per-endpoint.

Rejected alternatives, recorded so the choice is not silently revisited:

- **(b) full crossbar** — either endpoint reaches either CMAC. 4 switches, a
  steering policy, and a partitioned qid space; puts two hosts' traffic through
  one arbitration point.
- **(c) select / failover** — U45N model, AXI4-stream switch control registers
  pick which endpoint owns both MACs (PG085 control register). Cheap, but only
  one endpoint moves traffic at a time.

Nothing outside the plugin changes between (a), (b) and (c) — §§1–4 and 5.1–5.2
hold regardless.

## 6. Build

```bash
cd script
./build_au55n_2qdma_2cmac.sh
```

which is `build.tcl` with `-board au55n -num_qdma 2 -num_cmac_port 2
-num_phys_func 1 -num_queue 2048 -max_pkt_len 9600 -pkt_cap 16` and the plugin
argument. As with the au200 build, `write_bitstream` needs a full `cmac_usplus`
license; without it use `-impl_to_step route_design -post_impl 0`.

Note `constr/au55n/general.xdc` currently sets `-design_power_budget 100`. That
value is inherited from the 150 W U55C; the C1100 is a **75 W** card. Two Gen4
x8 endpoints plus two CMACs is the highest-power configuration this shell can
produce, so this is exactly the build where that matters — see
`fpga/U55N/u55n_full.xdc` §6.

## 7. Open items

### 7.1 / 7.2 Hard blocks and refclks — RESOLVED

Both are settled in §3 against the real device, and the values are committed in
`qdma_no_sriov_au55n.tcl` and `qdma_no_sriov_1_au55n.tcl`. The query used, for
reproducibility:

```tcl
create_project -in_memory -part xcu55n-fsvh2892-2L-e
link_design -part xcu55n-fsvh2892-2L-e          ;# get_sites needs a linked design
foreach s [lsort [get_sites -filter {SITE_TYPE =~ PCIE4*}]] {
    puts "$s [get_property SITE_TYPE $s] [get_property CLOCK_REGION $s]"
}
foreach pin {AL2 AM4 AN6 AN2 AP4 AR2 AT4 AU2 AV4 AW6 AW2 AY4 BA6 BA2 BB4 BC2 AR15 AL15} {
    set pp [get_package_pins $pin]
    puts "$pin bank=[get_property BANK $pp] [get_sites -of_objects $pp]"
}
```

The same run also independently confirmed the CMAC side: `AD42` → bank 130 →
quad `X0Y6` → channels `X0Y24..27`, and `AB42` → bank 131 → quad `X0Y7` →
channels `X0Y28..31`. That matches `GT_GROUP_SELECT` in
`cmac_usplus_0_au55n.tcl` / `cmac_usplus_1_au55n.tcl`, so the existing CMAC
configuration needs no change.

### 7.3 Host bifurcation

The slot must be set to x8x8 in BIOS. Unbifurcated, endpoint A trains x8 and
endpoint B is simply absent — one `onic` instance instead of two, which looks
like an RTL bug and is not one. Confirm with `lspci -d 10ee: -vv` before
debugging anything in the FPGA.

## 8. Verification plan

Do not trust a bitstream that has not cleared these.

1. **No-regression on au200/au250.** Rebuild `eth_1pf_2cmac_qid` for au200 and
   confirm `DESIGN_PARAMETERS` and the resulting utilization/timing are
   unchanged. Every edit in §4 is guarded; this proves the guards hold.
2. **1-QDMA au55n still builds** as Gen3 x16 (the `$num_qdma == 2` guard in the
   IP tcl, and the `llength` guards in the XDC).
3. **Enumeration**: `lspci -d 10ee: -nn` shows two `0x9048` devices at different
   BDFs; both bind `onic`; two netdevs appear.
4. **Link**: each endpoint reports Gen4 (16 GT/s) x8 — `lspci -vv | grep LnkSta`.
   A x8 link that negotiated Gen3 means the slot or the IP speed config is wrong.
5. **qid steering** (the §5.2 fix): line-rate bidirectional traffic on both
   CMACs simultaneously, checking that no frame arrives on the wrong CMAC at
   packet boundaries. This is the failure mode the side-FIFO produces, and it
   only shows up under sustained multi-packet load — a ping test will not find it.
6. **Power**: `xbutil examine` / CMS telemetry under that load, against the 75 W
   card limit, with the airflow the card will actually have.

## 9. Recommended order

1. ~~Resolve §7.1 and §7.2 in Vivado~~ — **done**, see §3.
2. Land the IP tcl + constraints + `open_nic_shell.sv` guards; build to
   `route_design` with the stock plugin to prove both endpoints place and route
   and that timing closes at Gen4. **Do not run traffic on this bitstream.**
3. Fix §5.2 (qid path). Re-verify per §8.5.
4. Rework the plugin per §5.3 for the 1:1 pinned mapping.

Steps 1–2 are unblocked and independent of steps 3–4. Step 3 (qid path) and
step 4 (plugin) are also independent of each other and can be done in parallel,
but §8.5 cannot pass until both are done — a traffic test exercises both.

## 10. Test topology for 1:1 pinned

Because each endpoint owns exactly one QSFP, the natural bring-up is a loopback
between the card's own two cages once §8.4 passes:

```
netdev 0 (BDF x) ── QSFP0 ══ DAC ══ QSFP1 ── netdev 1 (BDF y)
```

Both netdevs are on the same host, so put them in separate network namespaces
before running traffic or the kernel short-circuits the transfer through
loopback and you measure nothing. This topology also exercises the §5.2 qid path
on both endpoints at once, in opposite directions, which is exactly the
condition the side-FIFO race needs to show itself.
