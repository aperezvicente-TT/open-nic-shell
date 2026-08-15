# Chapter 3 — QDMA Subsystem & the qid Graft

The QDMA subsystem is the PCIe endpoint and the DMA engine. This chapter explains what
it does normally, then details the **qid graft** — the set of changes that let a single
QDMA function carry a per-packet *destination-port* identity to and from the fabric.

## 3.1 What the QDMA subsystem does

Source: `src/qdma_subsystem/`.

- **PCIe endpoint + Xilinx QDMA hard IP.** `qdma_subsystem_qdma_wrapper.v` instantiates
  the QDMA IP (`qdma_no_sriov qdma_inst`, line 288). It presents:
  - **H2C** (host→card, **TX**): a 512-bit AXI-Stream *master* (`m_axis_h2c_*`).
  - **C2H** (card→host, **RX**): a 512-bit AXI-Stream *slave* (`s_axis_c2h_*`) plus a
    completion (`cpl`) stream.
  - A **BAR2 AXI-Lite master** for the whole control plane (Ch. 2 §2.7).
- **Descriptor / queue model.** The design runs QDMA in **internal (cached) descriptor
  mode** — the descriptor-bypass ports are tied off
  (`qdma_subsystem.sv:304–326`). Per-PF logic lives in
  `qdma_subsystem_function.sv`; a TX packet is admitted only if its qid is inside the
  function's queue window: `h2c_q_in_range = (qid >= q_base) && (qid < q_base + num_q)`
  (`qdma_subsystem_function.sv:216`). `q_base`/`num_q` come from the function register
  block, programmed by the driver (Ch. 5).
- **H2C engine** (`qdma_subsystem_h2c.sv`) and **C2H engine** (`qdma_subsystem_c2h.sv`,
  which round-robin-arbitrates among PFs and computes a CRC + 7-bit ECC over the C2H
  control word).

Normally (stock OpenNIC) the *receive* queue is chosen by **RSS**: a Toeplitz hash over
the packet → an indirection table → `+ q_base`
(`qdma_subsystem_function.sv:512`). That mechanism cannot express "which CMAC did this
packet arrive on" — which is exactly what a 1-PF/2-CMAC NIC needs. Enter `EXT_QID`.

## 3.2 `EXT_QID`: turning the queue-ID into the steering key

**Set at the top level:** `src/open_nic_shell.sv:745` instantiates the QDMA subsystem
with `.EXT_QID(1)`. It propagates to each `qdma_subsystem_function` (`qdma_subsystem.sv:833`).

**What it does:** with `EXT_QID=1`, the C2H path uses a **per-packet queue-ID carried in
the AXI-Stream sideband** (`s_axis_c2h_tuser_qid`) as the descriptor queue, *instead of*
the internal RSS hash. When `EXT_QID=1` the RSS side-FIFO (`qid_fifo`) is not even
instantiated (`qdma_subsystem_function.sv:524`); the output qid select becomes
`m_axis_c2h_tuser_qid = (EXT_QID==1) ? axis_c2h_buf_tuser_qid : qid_fifo_dout`
(`qdma_subsystem_function.sv:695`).

**Why it matters for 1-PF/N-CMAC:** the plugin encodes CMAC identity directly into the
absolute qid — CMAC *i* owns `[i·64, (i+1)·64)` — tags it into `tuser_qid` on RX, and
`EXT_QID=1` makes QDMA honor that qid verbatim for descriptor selection. **The qid
becomes the routing key in both directions:**

- **TX (H2C):** QDMA emits, on `m_axis_h2c_tuser_qid`, the absolute qid of the queue it
  DMA'd from. The plugin demuxes on `qid[6]` to pick the CMAC (Ch. 4 §4.2). Because the
  driver places CMAC1's queues at absolute qid ≥ 64 (`qid_base = cmac·64`), `qid[6]`
  *is* the CMAC index. (See Ch. 5 §5.3 for why this — not `port_id` — is the live
  mechanism.)
- **RX (C2H):** the plugin tags each received packet with `qid = cmac·64`; `EXT_QID=1`
  routes it to that CMAC's queue block, i.e. the right netdev.

## 3.3 The H2C qid "byte-lock"

**Problem it solves:** an earlier implementation carried the H2C qid in a *side-FIFO*
parallel to the data. At packet boundaries the FIFO could skew the qid by one packet,
misrouting CMAC0 traffic (qid < 64) to CMAC1. **Fix:** pack the qid *into the same
register-slice TUSER as the size field* so it moves in exact lockstep with the data beat.

In `qdma_subsystem_function.sv` (live path, `QDMA_ID==0`):

- Slice: `axi_stream_register_slice #(.TDATA_W(512), .TUSER_W(27), .MODE("full")) h2c_slice_inst` (lines 243–247).
- **TUSER packing (27 bits, widened from 16):**

  | Bits | Field |
  |------|-------|
  | `[26:16]` | `qid[10:0]` |
  | `[15:0]` | `size[15:0]` |

  Input pack: `.s_axis_tuser({s_axis_h2c_tuser_qid, axis_h2c_tuser_size})` (line 252).
  Output unpack: `m_axis_h2c_tuser_size = tuser_out[15:0]`,
  `m_axis_h2c_tuser_qid = tuser_out[26:16]` (lines 269–270).

> **Superseded.** The `QDMA_ID != 0` path used to carry the qid in a side-FIFO
> beside a 16-bit-TUSER `clk_converter`, which skewed the qid by one packet at
> packet boundaries. It now carries `{qid, size}` inside a 27-bit TUSER through
> `qdma_subsystem_clk_converter_h2c`, and the side-FIFO is deleted — the same
> byte-locked guarantee as `QDMA_ID == 0`, but across the clock domain crossing
> that a second QDMA instance requires. See
> `docs/au55n-2qdma-gen4x8-design.md` §5.2. Still unexercised by traffic.

## 3.4 The C2H qid width chain (96 → 107 bits)

On RX, the qid rides alongside the 80-bit PTP timestamp and the 16-bit size through the
function's C2H path. The graft **widened the C2H TUSER from 96 to 107 bits** to make room
for the 11-bit qid. Three IPs' widths must all agree or the qid is silently corrupted —
this was flagged as the single highest-risk part of the graft.

In `qdma_subsystem_function.sv` (`QDMA_ID==0`):

1. **c2h register slice — 107-bit TUSER** (`c2h_slice_inst`, lines 384–388):

   | Bits | Field |
   |------|-------|
   | `[106:96]` | `qid[10:0]` ← *added by graft* |
   | `[95:16]` | `ptp_ts[79:0]` |
   | `[15:0]` | `size[15:0]` |

   Pack at line 379, unpack at lines 411–413.
2. **buf_fifo re-narrows to 27 bits** (`xpm_fifo_axis buf_fifo_inst`,
   `.TUSER_WIDTH(27)` = `{qid[10:0], size[15:0]}`, lines 575–619). The 80-bit `ptp_ts`
   is split into a separate `ptp_ts_fifo_inst` written on `tlast`.
3. **The completion path** in `qdma_subsystem_c2h.sv` also carries qid: its slice uses
   `.TUSER_W(107)` and folds qid into `c2h_ecc_data[26:16]` (line 215).

> **If you build a `QDMA_ID != 0` target**, the `qdma_subsystem_clk_converter c2h_axis_inst`
> IP must be re-customized to `TUSER_WIDTH=107` (was 16) — warning at
> `qdma_subsystem_function.sv:416–420`.

## 3.5 Module-boundary ports

On `qdma_subsystem.sv`:

- `output [11*NUM_PHYS_FUNC-1:0] m_axis_h2c_tuser_qid` (line 58) — absolute qid per H2C
  packet, out to the plugin.
- `input [11*NUM_PHYS_FUNC-1:0] s_axis_c2h_tuser_qid` (line 69) — the plugin's tagged
  absolute qid, in (honored only under `EXT_QID=1`).

At the top level these are the buses `axis_qdma_h2c_tuser_qid` and
`axis_qdma_c2h_tuser_qid` (`open_nic_shell.sv:372, 383`) that connect QDMA to the plugin.

## 3.6 Dead code you will encounter: "Option B" (port_id-derived qid)

During debugging, an alternative steering scheme ("Option B") derived the qid from the
QDMA `port_id` field: `h2c_qid_corrected = {2'b0, port_id[2:0], qid[5:0]}`. **It was
reverted** in favor of the plugin-side clamp fix (Ch. 4 §4.3). The following are now
**harmless dead code** — present but with no downstream reader:

- `wire [10:0] h2c_qid_corrected` (`qdma_subsystem_function.sv:232`) — declared, never
  read.
- `input [2:0] s_axis_h2c_tuser_port_id` (line 60) — its only consumer was
  `h2c_qid_corrected`; the whole `port_id` chain (wired from the QDMA IP at
  `qdma_subsystem.sv:857`) now feeds nothing.

The live H2C slice packs the **raw** `s_axis_h2c_tuser_qid` (line 252), not
`h2c_qid_corrected`. The revert is commit `1781c4f`.

> **Cleanup opportunity (non-blocking):** the dead `h2c_qid_corrected` /
> `s_axis_h2c_tuser_port_id` can be removed. It is left in place because it is inert and
> removing it touches the module boundary. See Ch. 8 §8.6.

> **Watch-out — the driver still sets `port_id`.** The driver programs the QDMA SW-context
> `port_id = cmac_id` (Ch. 5 §5.3). That is *vestigial*: it matches the reverted Option B
> and happens to equal the CMAC index, but **no live RTL reads it**. The actual TX
> steering is `qid[6]` in the plugin. Do not "fix" one without understanding the other —
> both encode the same CMAC index, which is why the system works.

Continue to [Chapter 4 — The 1-PF/2-CMAC Plugin](04-plugin-qid-steering.md).
