# Chapter 2 — Shell Architecture

This chapter describes the OpenNIC shell as it exists in this fork: the top module,
the subsystems it wires together, the clock domains, and the end-to-end AXI-Stream
datapath. Everything here is upstream OpenNIC structure *except* the qid plumbing and
the `EXT_QID=1` setting, which are the graft points for the 1-PF/2-CMAC design
(detailed in Ch. 3–4).

## 2.1 Design-space context: why one PF in front of two ports

There are three ways to attach two 100G ports to a host over PCIe:

| Model | PFs | Pros | Cons |
|-------|-----|------|------|
| **Stock OpenNIC `p2p`** | 2 (one per CMAC) | Simple; upstream-supported (`NUM_PHYS_FUNC == NUM_CMAC_PORT`) | Two functions, two BAR/MSI-X/IRQ budgets, two driver instances, no shared queue pool |
| **This project (1-PF/N-CMAC)** | 1 | One function/driver, shared queue pool, a stepping-stone toward a representor/switch model | Requires a custom qid-steering datapath (this whole document) |
| **Full eswitch/representor** | 1 + VFs | Industry SmartNIC model, on-chip switching | Much larger; needs a MAC-learning/flow engine in fabric |

This project is the middle option: **one PCIe function, port identity carried in the
QDMA queue-ID.** It is the minimum mechanism that gets you two independent netdevs from
one function without building a full switch.

## 2.2 Repository layout

| Dir | Contents |
|-----|----------|
| `src/` | All shell RTL. `open_nic_shell.sv` (top) + one subdir per subsystem: `system_config/`, `qdma_subsystem/`, `cmac_subsystem/`, `packet_adapter/`, `box_250mhz/`, `box_322mhz/`, `ptp_subsystem/`, `utility/`, `zynq_usplus_ps/`. Macros in `open_nic_shell_macros.vh`. |
| `plugin/` | User "box" logic swapped into the datapath boxes. `eth_2cmac_1pf/` (this build), `p2p/` (stock), `rdma_onic/`. |
| `constr/` | Per-board XDC: `au200/`, `au250/`, `au280/`, `au50/`, `au55c/`, `au55n/`, `au45n/`, `soc250/`. |
| `script/` | Build automation: `build.tcl` (master), `build_*.sh` wrappers, `board_settings/`, `program_fpga.*`, `program_hw.tcl`. |
| `board_files/` | Vendor board-definition files (`Xilinx/`). |
| `agent/` | Non-RTL support (`docs/`, PTP timestamp reference material). |
| `docs/` | **This documentation set.** |

## 2.3 The top module

**`src/open_nic_shell.sv`** (module at line 20). Top-level parameters (lines 20–30) and
the values this build sets (via `script/build_eth_1pf_2cmac_qid.sh`):

| Parameter | Default | This build | Notes |
|-----------|---------|-----------|-------|
| `USE_PHYS_FUNC` | 1 | 1 | |
| `NUM_PHYS_FUNC` | 1 | **1** | one PCIe function |
| `NUM_QDMA` | 1 | 1 | one QDMA instance |
| `NUM_CMAC_PORT` | 1 | **2** | two 100G ports |
| `NUM_QUEUE` | 512 | **2048** | must be power-of-two |
| `MAX_PKT_LEN` | 1518 | **9600** | jumbo frames |
| `MIN_PKT_LEN` | 64 | 64 | |
| `PKT_CAP` | 64 | 16 | FIFO sizing factor |

There is **no `BOARD` parameter** — board selection is a compile-time `` `ifdef `` macro
(`__au200__`, …) that `build.tcl` sets via `verilog_define`.

The top module instantiates and wires the subsystems (line refs into `open_nic_shell.sv`):
`system_config_inst` (543), `qdma_subsystem_inst` (734, inside a `NUM_QDMA` generate),
`packet_adapter_inst` (882) + `cmac_subsystem_inst` (949) (inside a per-CMAC-port
generate), `box_250mhz_inst` (1035), `box_322mhz_inst` (1122), and `ptp_subsystem_inst`
(1225).

## 2.4 The subsystem block diagram

```
                    PCIe Gen3 x16 (BAR0 data / BAR2 control)
                              │
                    ┌─────────▼──────────┐
                    │   qdma_subsystem   │  Xilinx QDMA hard IP, 1 PF
                    │   (EXT_QID = 1)    │  H2C master / C2H slave  (512-bit AXIS)
                    └───┬────────────▲───┘
                 H2C    │            │  C2H
              (512b AXIS)│            │(512b AXIS + tuser_qid)
                    ┌────▼────────────┴────┐   ← 250 MHz axis_aclk domain
                    │      box_250mhz       │   BODY = eth_2cmac_1pf plugin
                    │  TX qid-demux / RX RR │   (Ch. 4)
                    └──┬──────────────▲─────┘
        per-CMAC 250MHz│              │per-CMAC 250MHz
                    ┌──▼──────────────┴───┐  ×NUM_CMAC_PORT
                    │   packet_adapter     │  250↔322 MHz CDC + packetization
                    └──┬──────────────▲───┘
        per-CMAC 322MHz│              │per-CMAC 322MHz
                    ┌──▼──────────────┴───┐
                    │      box_322mhz      │  BODY = p2p_322mhz (passthrough)
                    └──┬──────────────▲───┘
                    ┌──▼──────────────┴───┐  ×NUM_CMAC_PORT
                    │   cmac_subsystem     │  UltraScale+ 100G MAC + GT
                    └──────────┬───────────┘
                               │ QSFP (100 GbE)
                        ┌──────┴──────┐
                     CMAC0          CMAC1

   system_config ──(AXI-Lite BAR2)──▶ every subsystem's CSR
   ptp_subsystem ──(80-bit PTP time)─▶ each CMAC TX/RX domain
```

| Subsystem | Dir | Role |
|-----------|-----|------|
| **system_config** | `src/system_config/` | Terminates BAR2 AXI-Lite, decodes it into per-target CSR ports, owns resets, satellite UART/GPIO, CMS/QSFP/QSPI/Sysmon glue |
| **qdma_subsystem** | `src/qdma_subsystem/` | Wraps the Xilinx QDMA/PCIe hard IP; presents 512-bit H2C/C2H AXIS to `box_250mhz`; descriptor/queue mapping. **Built with `EXT_QID=1`** (Ch. 3) |
| **box_250mhz** | `src/box_250mhz/` | The user datapath box in the 250 MHz domain. Its *body* is `` `include``d from the selected plugin — here `eth_2cmac_1pf` |
| **packet_adapter** | `src/packet_adapter/` | The 250↔322 MHz CDC + packetization bridge, one per CMAC port |
| **box_322mhz** | `src/box_322mhz/` | User box in the CMAC domain; here a plain passthrough (`p2p_322mhz`) |
| **cmac_subsystem** | `src/cmac_subsystem/` | Wraps the CMAC 100G MAC + GT; generates `cmac_clk`; PTP time in / TX timestamp out; `link_up` |
| **ptp_subsystem** | `src/ptp_subsystem/` | 80-bit PTP clock, CDC to each CMAC TX/RX domain, timestamp extract, periodic out |
| **utility** | `src/utility/` | Shared primitives: `axi_stream_packet_fifo` (async CDC FIFO), `axi_stream_register_slice`, `rr_arbiter`, `axi_lite_register`, `generic_reset`, `crc32`, … |

> **Key idea:** `box_250mhz` and `box_322mhz` are *shells* whose logic is supplied by a
> **plugin**. The stock plugin is `p2p`; this project swaps in `eth_2cmac_1pf`. That is
> how the qid-steering datapath is injected without forking the whole shell. See
> `build.tcl:355–378` for the plugin-ingestion mechanism (Ch. 6 §6.3).

## 2.5 Clock domains

| Clock | ~Freq | Source | Drives |
|-------|-------|--------|--------|
| `axil_aclk` | ~125 MHz | QDMA IP | AXI-Lite control plane: system_config, both boxes, packet adapters, CMAC CSRs, PTP |
| `axis_aclk` | 250 MHz | QDMA IP | Datapath: `box_250mhz`, QDMA H2C/C2H streams, 250 MHz side of each packet_adapter |
| `cmac_clk[p]` | ~322.27 MHz | each `cmac_subsystem` | `box_322mhz`, 322 MHz side of packet_adapter, CMAC TX/RX AXIS. **One per port, phase-independent** |
| `rx_serdes_clk[p]` | ~322 MHz | each CMAC RX SerDes | RX-side PTP timestamp domain |
| PCIe refclk | 100 MHz | board | QDMA hard IP; internally derives `axil_aclk`/`axis_aclk` |

(Frequencies for the AXIS/AXIL clocks are inferred from simulation half-periods and code
comments; the authoritative synthesized values live in the QDMA/CMAC IP `.xci`/`.tcl`.)

### Where clock-domain crossings happen

1. **250 ↔ 322 MHz datapath**, inside `packet_adapter`:
   - TX (250→322): `axi_stream_packet_fifo` `tx_cdc_fifo_inst`, `independent_clock`,
     `CDC_SYNC_STAGES=2` (`packet_adapter_tx.sv:168`). A gated async PTP-tag sideband
     FIFO stays aligned with the packet FIFO.
   - RX (322→250): `axi_stream_packet_fifo` `independent_clock` (`packet_adapter_rx.sv:177`);
     status counters cross via `level_trigger_cdc`.
2. **CMAC link-up → `axil_aclk`**: `xpm_cdc_single` per port (`open_nic_shell.sv:1267`).
3. **PTP time → CMAC domains**: `ptp_clock_cdc.v` inside `ptp_subsystem`. **These are the
   synchronizers guarded by the `timing.xdc` false-path fix** (Ch. 6 §6.5).

## 2.6 The AXI-Stream datapath, end to end

The datapath is **512-bit `tdata` + 64-bit `tkeep`** everywhere. What changes across the
pipeline is the `tuser` sideband.

### TX / H2C (host → wire)

1. QDMA H2C master `m_axis_h2c_*` → top wire `axis_qdma_h2c_*`. `tuser` carries
   `size[16], src[16], dst[16], ptp_tag[16], qid[11]`.
2. → `box_250mhz` `s_axis_qdma_h2c_*`. **The plugin demuxes by `qid[6]`** to pick the
   CMAC (Ch. 4 §4.2) → `m_axis_adap_tx_250mhz_*` (per CMAC).
3. → `packet_adapter` (250 MHz side). CDC 250→322 → `m_axis_tx_*` (322 MHz).
   `tuser` shrinks to `err + ptp_tag[16]` (length now carried by `tkeep`).
4. → `box_322mhz` (passthrough) → `cmac_subsystem` `s_axis_cmac_tx_*` → CMAC → wire.

### RX / C2H (wire → host)

1. CMAC → `cmac_subsystem` `m_axis_cmac_rx_*`. `tuser` = `err + ptp_ts[80]` (80-bit RX
   timestamp).
2. → `box_322mhz` (passthrough) → `packet_adapter` (322 MHz side). CDC 322→250.
   250 MHz `tuser` = `size[16], src[16], dst[16], ptp_ts[80]`.
3. → `box_250mhz`. **The plugin arbitrates the per-CMAC RX streams and tags each packet
   with `qid = cmac·64`** (Ch. 4 §4.4) → QDMA C2H `m_axis_qdma_c2h_*`.
4. → `qdma_subsystem` `s_axis_c2h_*`. `tuser` = `size[16], src[16], dst[16], ptp_ts[80],
   qid[11]`. **Because `EXT_QID=1`, QDMA uses `s_axis_c2h_tuser_qid` as the descriptor
   queue** — this is what routes the packet to the correct netdev (Ch. 3 §3.2).

## 2.7 The control plane (AXI-Lite / BAR2 map)

BAR2 (4 MB) AXI-Lite enters at `qdma_subsystem` → `system_config` →
`system_config_address_map.sv`, which decodes 13 slaves. Base offsets
(`system_config_address_map.sv:255–281`):

| Base | Target |
|------|--------|
| `0x00000` | System configuration |
| `0x01000` | QDMA subsystem #0 |
| `0x08000` | **CMAC subsystem #0** |
| `0x0B000` | Packet adapter #0 |
| `0x0C000` | **CMAC subsystem #1** |
| `0x0F000` | Packet adapter #1 |
| `0x10000` | Sysmon |
| `0x12000` | QDMA subsystem #1 (dummy when `NUM_QDMA==1`) |
| `0x18000` | PTP subsystem |
| `0x100000` | **Box0 @ 250 MHz** ← plugin CSRs incl. the diag counters (Ch. 4 §4.5) |
| `0x200000` | Box1 @ 322 MHz |
| `0x300000` | Card Management System |
| `0x340000` | QSPI |

Note the CMAC stride: **CMAC0 at `0x08000`, CMAC1 at `0x0C000`** — a **`0x4000`** step.
The driver must reproduce this stride exactly; getting it wrong is the `num_cmacs` bug
in Ch. 5 §5.4. The plugin diagnostic counters live inside Box0, i.e. at absolute BAR2
`0x100000 + offset` (Ch. 4 §4.5, Ch. 9).

Continue to [Chapter 3 — QDMA Subsystem & the qid Graft](03-qdma-subsystem.md).
