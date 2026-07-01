# Chapter 4 — The 1-PF/2-CMAC Plugin (`eth_2cmac_1pf`)

This is the heart of the design: the plugin that replaces the stock `box_250mhz` user
logic with a **qid-steered, pure-L2** datapath. It demuxes one H2C stream to N CMAC
ports on TX, and merges + tags N CMAC RX streams into one C2H stream on RX.

Source: `plugin/eth_2cmac_1pf/`. Main datapath file:
`plugin/eth_2cmac_1pf/eth_2cmac_1pf_250mhz.sv` (579 lines). CSR:
`rdma_diag_csr.sv`. The 322 MHz box (`p2p_322mhz.sv`) is a plain passthrough.

## 4.1 Role and parameters

The plugin is derived from `rdma_onic_250mhz.sv` with **all RDMA / ERNIC / classifier /
filter / compute-AXI-MM logic stripped** (header comment, lines 20–52). It is *N-ready*:
the RTL supports 2–8 CMACs.

| Name | Value | Meaning |
|------|-------|---------|
| `NUM_QDMA` | 1 | QDMA interfaces (single PF) |
| `NUM_INTF` | = `NUM_CMAC_PORT` (2) | Number of CMAC ports |
| `PER_CMAC_QUEUES` | 64 | Per-CMAC queue stride — **must equal driver `ONIC_PER_CMAC_QUEUES`** |
| `QID_LO_W` | `$clog2(64)` = 6 | Intra-CMAC queue field width (qid low bits) |
| `SEL_W` | `max(1, $clog2(NUM_INTF))` = 1 for 2 CMACs | CMAC-select field width |
| `ARB_FIFO_DEPTH` | 512 | Per-CMAC RX packet-FIFO depth |
| `ARB_TUSER_W` | 123 | Packed RX FIFO TUSER: `{qid[10:0], ptp_ts[79:0], src[15:0], size[15:0]}` |

**The steering arithmetic:** an absolute qid splits into `{ CMAC-select | intra-CMAC index }`
at bit `QID_LO_W = 6`. For 2 CMACs that is a single select bit, `qid[6]`:

```
 abs qid (11 bits):   [10 .. 7] [ 6 ] [ 5 .. 0 ]
                        unused   sel   intra-CMAC index (0..63)
   qid   0..63  -> sel=0 -> CMAC0
   qid  64..127 -> sel=1 -> CMAC1
```

## 4.2 TX path — H2C demux by qid

Only H2C slot 0 is driven (`NUM_PHYS_FUNC=1`). The CMAC select is decoded from the
first beat's qid and **locked for the whole packet** so a multi-beat frame cannot split
across ports.

- Decode: `h2c_first_beat_sel_raw = h2c_tuser_qid[QID_LO_W +: SEL_W]` = `qid[6]` (line 244).
- Packet-atomic lock FSM (lines 254–288): on the first beat it captures the select into
  `h2c_dmux_sel` and the qid into `h2c_captured_qid`, sets `h2c_dmux_locked = ~tlast`
  (stays unlocked for single-beat frames), and holds the select until `tlast`.
- Backpressure: `s_axis_qdma_h2c_tready[0] = m_axis_adap_tx_250mhz_tready[sel]` — ready
  comes only from the *currently selected* CMAC adapter (lines 261–263).
- Per-CMAC drive is pure routing (no arbiter): `tvalid[c] = h2c_tvalid && (sel==c)`
  (lines 301–313); it also sets `tuser_dst = 1 << (6+c)`.
- **Trip-wire:** `tx_qid_changed_pulse` fires if the qid changes mid-packet vs the
  captured first-beat qid (diag counter idx 17).

## 4.3 The root-cause bug: the demux clamp underflow

> This is the bug that presented as **"CMAC0 TX is completely dead"** and took three
> wrong fixes before the real one. It is documented here in full so it is never
> re-introduced.

The demux clamps an out-of-range select to the last CMAC. The **original** clamp compared
against a *truncated* `NUM_INTF`:

```verilog
// BUGGY (original):
h2c_first_beat_sel = (h2c_first_beat_sel_raw < NUM_INTF[SEL_W-1:0])
                     ? h2c_first_beat_sel_raw : (NUM_INTF[SEL_W-1:0] - 1'b1);
```

For `NUM_INTF = 2` (`0b10`) and `SEL_W = 1`, `NUM_INTF[SEL_W-1:0] = NUM_INTF[0] = 0`. So
the predicate became `(sel_raw < 0)` — **always false for an unsigned value**. The
ternary therefore *always* took the else branch `(0 - 1)` → select hardwired to **CMAC1**.
The demux **ignored the qid entirely** and sent *all* H2C traffic to CMAC1; CMAC0's
`stat_tx` stayed at 0.

This is also **why two earlier qid-value fixes failed identically** — the byte-lock
(Ch. 3 §3.3) and the port_id-derived qid (Ch. 3 §3.6) both changed the qid *value*, but
the demux never read the qid, so neither could have any effect.

**The fix** (current code, `eth_2cmac_1pf_250mhz.sv:250–252`) compares against the
full-width `NUM_INTF`:

```verilog
wire [SEL_W-1:0] h2c_first_beat_sel =
      (h2c_first_beat_sel_raw < NUM_INTF) ?
      h2c_first_beat_sel_raw : (NUM_INTF - 1);
```

For any power-of-two `NUM_INTF`, `sel_raw` is always in range and passes through; the
clamp only engages for non-power-of-two CMAC counts. Commit `1781c4f`.

**Lesson encoded in the docs:** when a Verilog part-select width (`SEL_W`) is narrower
than the value you compare it to (`NUM_INTF`), indexing the value with `[SEL_W-1:0]`
silently truncates it. Compare against the full-width constant.

## 4.4 RX path — per-CMAC FIFOs + round-robin arbiter + qid tag

- **Per-CMAC packet FIFO** (one per CMAC, lines 351–405): `axi_stream_packet_fifo`,
  common-clock, BRAM, depth 512, TDATA=512, TUSER=123. **Packet-mode** so a whole frame
  is buffered before the arbiter sees `tvalid` (avoids mid-packet head-of-line blocking).
  - **qid tag applied at FIFO ingress:** `cmac_qid = c * PER_CMAC_QUEUES` (line 353),
    packed into TUSER: `{cmac_qid, ptp_ts, src, size}`.
  - A CMAC marker `tid = c & 1` rides with the packet for the RX trip-wire.
- **N-way packet-atomic round-robin arbiter** (lines 407–449): rotate-priority search;
  `arb_grant = arb_locked ? arb_last : grant_rr`; locks on the granted packet until its
  `tlast`. This is fair between the two CMACs and never interleaves frames.
- **qid tagging on output** (lines 451–469): the granted FIFO's fields drive C2H slot 0.
  Critically, `m_axis_qdma_c2h_tuser_qid = g_tuser[122:112]` — the qid is pulled from
  **the FIFO's TUSER**, i.e. it rides the same BRAM cells as the data, *not* a
  grant-keyed constant. This is the fix for a real dual-CMAC RX qid-misroute.
- **Trip-wire:** `rx_marker_mismatch_pulse` fires if the emitted TID marker ≠ the grant
  index at the C2H output (diag counter idx 16).

The tagged qid (`c·64`) is what `EXT_QID=1` (Ch. 3 §3.2) uses to route the packet to the
correct netdev.

## 4.5 The diagnostic CSR (`rdma_diag_csr`)

An AXI-Lite CSR block of **18 free-running 32-bit counters**, incremented by one-bit
pulses tapped at each datapath hop (`rdma_diag_csr.sv`; wiring in
`eth_2cmac_1pf_250mhz.sv:508–577`). Counters run on the 250 MHz datapath clock and are
CDC'd to the AXI-Lite clock; they clear only on datapath reset; writes are no-ops.

**Location:** the plugin sits in **Box0 @ 250 MHz**, whose BAR2 base is `0x100000`
(Ch. 2 §2.7); the plugin's slave base inside the box is `0x0`, so **counter *n* is at
absolute BAR2 `0x100000 + offset`**.

| Offset | Abs (BAR2) | Counter | Counts |
|--------|-----------|---------|--------|
| `0x00` | `0x100000` | **RX0_adap_in** | CMAC0 frames received into the 250 MHz adapter (tlast) |
| `0x10` | `0x100010` | RX0_arb_in | CMAC0 FIFO → arbiter |
| `0x14` | `0x100014` | RX0_qdma_c2h | C2H out, granted source = CMAC0 |
| `0x18` | `0x100018` | **RX1_adap_in** | CMAC1 frames received into the adapter |
| `0x28` | `0x100028` | RX1_arb_in | CMAC1 FIFO → arbiter |
| `0x2C` | `0x10002C` | RX1_qdma_c2h | C2H out, granted = CMAC1 |
| `0x30` | `0x100030` | **TX0_h2c_demux** | H2C demuxed → CMAC0 (tlast, sel==0) |
| `0x34` | `0x100034` | **TX1_h2c_demux** | H2C demuxed → CMAC1 (tlast, sel==1) |
| `0x38` | `0x100038` | TX0_adap_out | out to CMAC0 TX adapter (tlast) |
| `0x3C` | `0x10003C` | TX1_adap_out | out to CMAC1 TX adapter (tlast) |
| `0x40` | `0x100040` | RX_MARK_MISMATCH | trip-wire: FIFO TID marker ≠ grant at C2H out |
| `0x44` | `0x100044` | TX_QID_CHANGED | trip-wire: H2C qid changed mid-packet |

(Offsets `0x04/0x08/0x0C/0x1C/0x20/0x24` are tied to 0 — they were classifier/filter
counters in the RDMA ancestor, kept at their original byte positions so existing tooling
still reads the map.)

These counters are the primary bring-up instrument — see Ch. 8 §8.3 (how to read them,
and how they were used to prove the CMAC↔peer topology and the clamp bug).

## 4.6 How the plugin is selected and what it contributes

- **Selection:** pass `-user_plugin ../plugin/eth_2cmac_1pf` to `build.tcl` (default is
  `plugin/p2p`). The build's plugin-ingestion loop (`build.tcl:355–378`) sources the
  box's crossbar/switch tcl, reads its address map, and sources `build_box_250mhz.tcl` /
  `build_box_322mhz.tcl` from the plugin.
- **Files contributed:**
  - `build_box_250mhz.tcl` — reads `eth_2cmac_1pf_250mhz.sv` + `rdma_diag_csr.sv`.
  - `build_box_322mhz.tcl` — reads `p2p_322mhz.sv` (passthrough).
  - `box_250mhz/` and `box_322mhz/` — address maps, `axi_crossbar.tcl`,
    `axis_switch.tcl`, and the `user_plugin_*_inst.vh` that instantiates the module.
- **Dependencies pulled from the shell** (not plugin-local): `src/utility/generic_reset.sv`,
  `src/utility/axi_stream_packet_fifo.sv`, and `axi_lite_register` (used by the CSR).

> **The plugin alone is not enough.** The absolute qid must be plumbed through the shell
> on both H2C and C2H, and `EXT_QID=1` must be set — these are edits in
> `src/box_250mhz/box_250mhz.sv`, `src/open_nic_shell.sv`, and `src/qdma_subsystem/*`
> (Ch. 3). Those are the "graft" and are already applied on this branch. See the plugin's
> `INTEGRATION_CONTRACT.md` for the exact contract.

Continue to [Chapter 5 — The Linux Driver](05-driver.md).
