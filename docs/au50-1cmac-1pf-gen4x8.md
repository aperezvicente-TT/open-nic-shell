# au50 / Alveo U50 — 1 CMAC + 1 PF @ Gen4 x8 — design

**Status:** bring-up target.

*Verified* (Vivado 2024.2, `xcu50-fsvh2104-2-e`, 2026-08-15): the QDMA IP
customizes to Gen4 x8 on the real device — the generated `.xci` resolves to
`pl_link_cap_max_link_width X8`, `pl_link_cap_max_link_speed 16.0_GT/s`,
`PCIE_BOARD_INTERFACE pci_express_x8`, `pcie_blk_locn PCIE4C_X1Y0`,
`pf0_device_id 9048` (the derived ID that only Gen4 x8 produces), with the user
interface still 512-bit at 250 MHz and 2048 queues on 1 PF — and the generated
core's serial ports are `[7:0]`, matching the 8-lane top level.

*Built and timing-clean* (2026-08-15): the full flow runs to `.bit` + `.mcs`
with **0 errors**, closing at **WNS +0.039 ns / TNS 0.000 / 0 failing
endpoints** under `Performance_ExplorePostRoutePhysOpt` (§6.2 — the tool
defaults do *not* close).
Synthesis reports 2 critical warnings, both the `system_management_wiz`
unconnected `vp`/`vn` black-box pins that the hardware-validated au200 build
reports identically. Utilization on the xcu50 is comfortable — see §6.1.

*Not verified*: the card has never been programmed, no link has been trained
and no packet has moved. Nothing has been simulated.

Companion documents: the shell itself is documented in Ch. 1–13 of this
directory; the analogous Gen4 x8 work on the Varium C1100 is in
[`au55n-2qdma-gen4x8-design.md`](au55n-2qdma-gen4x8-design.md), which this
target borrows its IP-ordering rules from.

---

## 1. Target

| | |
|---|---|
| Card | Alveo U50 (one QSFP28 cage, HBM, 75 W passive) |
| Part | `xcu50-fsvh2104-2-e` (VU35P, 2 SLRs) |
| Board part | `xilinx.com:au50:part0:1.3` (in-repo, `board_files/Xilinx/au50/1.3`) |
| PCIe | **1 QDMA endpoint, Gen4 x8**, edge lanes 0–7 |
| Ethernet | **1 CMAC**, 100 GbE, `CMACE4_X0Y4` on GTY quad `X0Y7` |
| Functions | 1 PF, 2048 queues, absolute-qid steering + per-port RSS |
| Plugin | `plugin/eth_2cmac_1pf` at `NUM_INTF = 1` |
| Build wrapper | [`script/build_au50_1cmac_1pf_gen4x8.sh`](../script/build_au50_1cmac_1pf_gen4x8.sh) |

This is the same shell as the hardware-validated au200/au250
`eth_1pf_2cmac_qid` target (Ch. 3 qid graft, Ch. 4 plugin, Ch. 11 RSS), with
`NUM_CMAC_PORT = 1` because the U50 has exactly one QSFP cage, and with the
endpoint retrained from the board-default Gen3 x16 to Gen4 x8.

## 2. Why Gen4 x8, and what it costs

A **PCIE4C** block does x16 only at Gen3; at Gen4 it caps at x8. The two are
therefore mutually exclusive — the same trade written out at length for the
C1100 in `au55n-2qdma-gen4x8-design.md` §3.

- **Bandwidth is a wash.** Gen4 x8 = 8 × 16 GT/s and Gen3 x16 = 16 × 8 GT/s:
  128 Gb/s raw either way. The QDMA user interface stays 512 bits at 250 MHz,
  and `qdma_subsystem_clk_div` still takes 250 MHz in and emits 125/100 MHz, so
  **nothing downstream of the endpoint resizes or reclocks**. The only IP-level
  difference is the internal core clock, 500 MHz instead of 250 MHz
  (`CONFIG.coreclk_freq {500}`).
- **What you gain** is a link in a slot that only wires 8 lanes, or one
  bifurcated x8x8.
- **What you lose** is nothing on a Gen4 host — but on a **Gen3-only** host,
  Gen4 x8 trains down to Gen3 x8 and you get *half* the bandwidth of the stock
  build. In a full Gen3 x16 slot, build the default instead: drop
  `-pcie_gen4x8 1` from the wrapper.

The endpoint width is the *only* thing this option changes. It is off by
default, and the stock `-board au50` build is byte-for-byte what it was.

## 3. Lane and clock budget

All of the following was read out of Vivado 2024.2 for `xcu50-fsvh2104-2-e`
rather than inferred from a datasheet:

| Resource | Site | Clock region | SLR |
|---|---|---|---|
| PCIe hard block (x8 board interface) | `PCIE4CE4_X1Y0` | X7Y0 | SLR0 |
| PCIe refclk `AF9/AF8` (= `PCIE_REFCLK1`) | quad `GTYE4_COMMON_X1Y1`, bank 225 | X7Y1 | SLR0 |
| Other PCIe refclk `AB9/AB8` | quad `GTYE4_COMMON_X1Y3`, bank 227 | X7Y3 | SLR0 |
| CMAC | `CMACE4_X0Y4` | — | SLR1 |
| QSFP refclk `N36/N37` (161.1328125 MHz) | quad `GTYE4_COMMON_X0Y7`, bank 131 | X0Y7 | SLR1 |

The 16 edge lanes land in quads `X1Y0..X1Y3`; lanes 0–7 are the `X1Y0`/`X1Y1`
pair. `AF9/AF8` sits in `X1Y1`, so it is within the "GT refclk within 2 quads
of every transceiver it feeds" rule (`[Place 30-739]`) for lanes 0–7 — and, at
distances 1/0/1/2, for all sixteen, which is exactly why upstream's
`constr/au50/pins.xdc` already pins the refclk there and warns that the `AB`
pair (3 quads from `X1Y0`) fails for x16.

**Consequence: the pin constraints do not change at all.** Unlike the C1100 —
where the two endpoints had to be detached from the board interface and pinned
by hand — the au50 board file already defines a `pci_express_x8` interface on
lanes 0–7 with `block_location PCIE4C_X1Y0` and the `PCIE_REFCLK1` refclk this
design already uses. So this target keeps `PCIE_BOARD_INTERFACE`, just switched
from `pci_express_x16` to `pci_express_x8`, and lets the board file place the
lanes.

## 4. Files changed

| File | Change |
|---|---|
| `script/build.tcl` | New build option `-pcie_gen4x8` (default 0), rejected on any board but au50; emits the ``__au50_gen4x8__`` macro |
| `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au50.tcl` | `pci_express_x8` board interface + Gen4 geometry written last; prints the resolved link parameters |
| `src/open_nic_shell.sv` | 8-lane `pcie_rxp/rxn/txp/txn`, 8-lane `qdma_pcie_*` wires, 8-lane slice into `qdma_subsystem` — all under ``__au50_gen4x8__`` |
| `src/qdma_subsystem/qdma_subsystem.sv` | 8-bit `pcie_*` ports under the same macro |
| `src/qdma_subsystem/qdma_subsystem_qdma_wrapper.v` | 8-bit `pcie_*` ports under the same macro |
| `constr/au50/timing.xdc` | Ported the device-independent PTP/QDMA-clock/flow-control CDC constraints from `constr/au250/timing.xdc`; pblocks left at their au50 values |
| `script/build_au50_1cmac_1pf_gen4x8.sh` | Build wrapper |

Nothing outside these files was touched: `constr/au50/pins.xdc` and
`general.xdc` are unchanged (§3), and every other board's flow is untouched
because both the macro and the IP branch are gated on `board eq "au50" &&
$pcie_gen4x8`.

### 4.1 The IP-ordering rules, inherited

`qdma_no_sriov_au50.tcl` writes the Gen4 geometry **after** everything else,
including `set_property CONFIG.num_queues`. This is not stylistic: anything
that re-derives link parameters (board interface, block placement, quad
selection) silently resets width and speed, with no error — the C1100 work
produced a clean run of Gen3 endpoints exactly that way
(`au55n-2qdma-gen4x8-design.md` §5.1 and the comments in
`qdma_no_sriov_au55n.tcl`). `CONFIG.xlnx_ref_board` is likewise left at `AU50`,
since with `BOARD_PART` set, any other value is rejected outright.

The device ID is deliberately **not** set: the IP derives it from gen × width
and overrides any explicit value, which makes it a free assertion — `9048`
proves Gen4 x8 took, `9038` means it fell back to Gen3 x8.

## 5. The 1-CMAC path

Two things are exercised for the first time by this target.

### 5.1 `plugin/eth_2cmac_1pf` at `NUM_INTF = 1`

The plugin is parameterized on `NUM_INTF = NUM_CMAC_PORT` and its own header
claims a supported range of 2..8, but the code is written for 1 as well:
`SEL_W` is guarded with `(NUM_INTF > 1) ? $clog2(NUM_INTF) : 1`
(`eth_2cmac_1pf_250mhz.sv:185`) precisely so `$clog2(1) = 0` never produces a
zero-width part-select, and the CMAC-select clamp compares against the
full-width `NUM_INTF` so the single CMAC always wins
(`eth_2cmac_1pf_250mhz.sv:351-357`). At `NUM_QDMA = 1` it elaborates in
**qid-STEERED** mode — a one-way demux and a one-way arbiter, degenerate but
structurally the same datapath au200/au250 run.

One thing is actually *better* at one CMAC: the plugin's AXI-Lite slots
(`NUM_INTF*2`) and the box address map's masters
(`box_250mhz_address_map` instantiated with `NUM_INTF = NUM_PHYS_FUNC`, giving
`NUM_PHYS_FUNC*2`) agree exactly at 1 PF / 1 CMAC, where in the 2-CMAC build
the upper two plugin slots are surplus and tied off.

### 5.2 The unused CMAC1 register window

With `NUM_CMAC_PORT = 1`, `system_config_address_map.sv:503` terminates the
CMAC1 (`0x0C000`) and ADAP1 (`0x0F000`) windows with `axi_lite_slave` stubs
carrying `REG_PREFIX = 16'hC100`, so a read returns `0xC100_xxxx`
(`axi_lite_slave.sv:95`). The driver detects the CMAC count by reading
`CMAC_OFFSET_CORE_VERSION(i)` until the value is not `0x00000301` (Ch. 5 §5.4),
so it should stop at **`num_cmacs = 1`** and bring up exactly one netdev. That
is the expected behaviour to confirm on first boot; it is not yet observed.

### 5.3 Queue map

Unchanged from Ch. 4: `PER_CMAC_QUEUES = 64`, CMAC 0 owns absolute qids
`[0, 64)`. With one CMAC only that first block is used, so of the 2048 queues
the endpoint is built with, 64 are live. The driver's
`ONIC_PER_CMAC_QUEUES = 64` still matches — the invariant is per-CMAC, not
per-card, so no driver change is needed for this target.

## 6. Build

```bash
cd script
./build_au50_1cmac_1pf_gen4x8.sh                          # full flow -> .bit + .mcs
./build_au50_1cmac_1pf_gen4x8.sh -impl_to_step route_design -post_impl 0
                                                          # stop before bitstream
./build_au50_1cmac_1pf_gen4x8.sh -tag ipcheck -synth_ip 0 -impl 0 -post_impl 0
                                                          # IP customization only (~10 min)
```

Build directory: `build/au50_eth_1pf_1cmac_gen4x8`.

### What to grep for in the log

| Grep | Expect | Meaning |
|---|---|---|
| `qdma_no_sriov_au50]` | `gen4x8=1 link=X8 16.0_GT/s intf=pci_express_x8 block=PCIE4C_X1Y0 device_id=9048` | The Gen4 geometry actually took. `9038`/`X16` means it was silently re-derived away — see §4.1 |
| `eth_2cmac_1pf_250mhz:` | `qid-STEERED mode ... (NUM_QDMA=1, NUM_INTF=1)` | The plugin elaborated for one CMAC |
| `Place 30-739` | absent | GT refclk / transceiver quad distance (§3) |
| `Vivado 12-4739` | absent | A `set_false_path` hit an empty object list — the guarded helpers in `constr/au50/timing.xdc` exist to prevent exactly this |

The `cmac_usplus` license caveat from Ch. 6 §6.1 applies unchanged: with only
the built-in `Design_Linking` entitlement, synthesis and implementation succeed
and `write_bitstream` fails at the very end.

### 6.1 Utilization (first build, 2026-08-15)

| Resource | Used | Available | % |
|---|---:|---:|---:|
| CLB LUTs | 100,405 | 871,680 | 11.5 |
| CLB Registers | 136,054 | 1,743,360 | 7.8 |
| Block RAM tiles | 211.5 | 1,344 | 15.7 |
| URAM | 20 | 640 | 3.1 |
| GTYE4_CHANNEL | 12 | 20 | 60.0 |
| CMACE4 | 1 | 5 | 20.0 |
| PCIE4CE4 | 1 | 4 | 25.0 |

The **12** transceivers are the clearest physical confirmation that the lane
narrowing took: 8 PCIe + 4 CMAC. A Gen3 x16 build would show 20.

### 6.2 Timing: use a strategy, not the defaults

The first au50 build used `Vivado Implementation Defaults` and **did not
close**: WNS −0.083 ns, TNS −7.959 ns, 206 failing endpoints (hold clean at
+0.010 ns). `write_bitstream` still succeeded — negative WNS is a warning, not
an error — so the resulting `.mcs` is *functional but not timing-clean*, and
`build.tcl` flags it with a `CRITICAL WARNING`.

Every one of the 206 violations is the same path:

```
Source:      box_322mhz_inst/p2p_322mhz_inst/reset_inst/.../arststages_ff_reg[1]/C
Destination: box_322mhz_inst/p2p_322mhz_inst/genblk1[0].tx_slice_1_inst/...axis_tdata_reg[0][*]/R
Path Group:  txoutclk_out[0]    Requirement: 3.103 ns    Logic Levels: 0
Data Path Delay: 2.730 ns  (logic 0.081 ns / route 2.649 ns = 97 %)
```

— a high-fanout **reset net** inside the 322 MHz box, zero logic levels, 97 %
routing. Not a congestion problem (§6.1) and nothing specific to this board:
Ch. 6 §6.6 documents the same regime on au200, where Defaults lands at
−0.095 ns / 82 endpoints.

A two-strategy sweep off the same synthesis settles it — both close, and the
ranking matches au200's:

| Strategy | WNS (ns) | TNS | WHS (ns) | Failing endpoints |
|---|---:|---:|---:|---:|
| Vivado Implementation Defaults | −0.083 | −7.959 | +0.010 | 206 |
| **Performance_ExplorePostRoutePhysOpt** | **+0.039** | **0.000** | **+0.007** | **0** |
| Congestion_SpreadLogic_high | +0.001 | 0.000 | — | 0 |

**Build this target with the documented production recipe:**

```bash
./build_au50_1cmac_1pf_gen4x8.sh -max_threads 32 -ultrathreads 0 \
    -impl_strategies 'Performance_ExplorePostRoutePhysOpt'
```

The shipped image is `impl_2` of build `au50_eth_1pf_1cmac_gen4x8`
(2026-08-15): WNS +0.039 ns, TNS 0.000, WHS +0.007 ns, 0 failing endpoints of
404,814, `write_bitstream` and `write_cfgmem` clean. `Congestion_SpreadLogic_high`
closes too but with a 27× smaller setup margin, so it is a control, not a
candidate.

## 7. Open items

1. **Timing needs the strategy** (§6.2). Defaults leave 206 endpoints at
   −0.083 ns, and `write_bitstream` succeeds anyway — `impl_1` of this build
   directory holds exactly that not-clean `.mcs`. Flash `impl_2`.
2. **The pblocks are upstream's, not tuned.** `constr/au50/timing.xdc` keeps
   `CLOCKREGION_X1Y2:X2Y3` (TX) and `X5Y2:X6Y3` (RX) — both in SLR0, i.e. on
   the opposite side of the SLR boundary from the CMAC in SLR1. They were the
   predicted risk and turned out **not** to be what failed: the packet-adapter
   CDC met timing and the violations were all in the 322 MHz box's reset tree.
   Left alone for that reason, but they remain untuned for this device.
3. **Never link-trained.** The Gen4 x8 endpoint has not been brought up in a
   host. Confirm with `lspci -vv` that the link reports `16GT/s, Width x8`, and
   remember a Gen3 host will train it down to Gen3 x8 (§2).
4. **Power.** `constr/au50/general.xdc` sets `-design_power_budget 63` on a
   75 W passively cooled card. This build adds the PTP subsystem and the
   500 MHz Gen4 core clock relative to upstream's au50 target; watch the power
   report rather than assuming the budget still holds.
5. **Flow control is off**, as everywhere else: `-flow_ctrl_en` /
   `-flow_ctrl_react_en` default to 0 (Ch. 13). The CDC constraints they need
   are now present in `constr/au50/timing.xdc`, so turning them on is a
   build-flag change, but the feature itself remains unbuilt on any board.
