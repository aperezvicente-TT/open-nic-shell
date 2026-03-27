# QDMA PTP Timestamp Integration Plan

Last updated: 2026-03-27

---

## Overview

This plan covers the two remaining QDMA datapath modifications needed to enable hardware timestamping (`ptp4l -H`):

1. **RX timestamps**: Thread 80-bit PTP timestamps from `box_250mhz` through QDMA C2H into 16-byte completion descriptors
2. **TX tag injection**: Thread 16-bit PTP tags from H2C descriptor metadata through QDMA to CMAC, then poll TX TS FIFO for completed timestamps

Software-timestamped PTP synchronization is already verified working (see status.md).

---

## Design Principle: Sideband FIFOs (No TUSER Widening)

**Decision**: Use separate sideband FIFOs for PTP data throughout the QDMA subsystem, NOT widened TUSER buses. This keeps PTP metadata completely independent of the packet data path.

**Rationale**:
- **Isolation**: A bug in timestamp logic cannot stall or corrupt packet delivery
- **No existing IP modification**: Register slices, buffer FIFOs, and arbiters keep their current TUSER widths
- **Proven pattern**: `packet_adapter_rx.sv` already uses this approach successfully for the 322→250 MHz crossing
- **Safe alignment**: The C2H path has NO drop logic -- all packets that enter are delivered. This guarantees 1:1 correspondence between timestamp FIFO entries and packet completions.

**Rejected alternative**: Widening TUSER from 16 to 96 bits (16 size + 80 ptp_ts) through the register slice and buffer FIFO in `qdma_subsystem_function.sv`. This couples timestamp data to the packet pipeline and risks timing degradation on the wider bus.

---

## Part 1: RX Timestamps (C2H Completion)

### Design

Upgrade C2H completion entries from 8B to 16B. Thread PTP timestamps through the C2H path via **separate sideband signals and FIFOs**, completely independent of the packet data bus.

**16-byte completion layout:**
```
DW0 [15:0]    = seconds_hi[47:32]    (currently zero, reused)
DW0 [31:16]   = reserved/zero
DW0 [47:32]   = pkt_len              (unchanged)
DW0 [63:48]   = pkt_id               (unchanged)
DW1 [95:64]   = nanoseconds          (32 bits)
DW1 [127:96]  = seconds_lo[31:0]     (32 bits)
```

Bits [1:2] (color/err) are set by the QDMA IP hardware, unchanged.

### Data Path (Sideband)

```
packet_adapter_rx: m_axis_rx_tuser_ptp_ts [80-bit, per packet, valid on tlast]
        |
        v
box_250mhz / p2p_250mhz: passthrough wire
        |
        v
open_nic_shell.sv: axis_qdma_c2h_tuser_ptp_ts (wire already declared at line 381)
        |
        v
qdma_subsystem.sv: new s_axis_c2h_tuser_ptp_ts input port
        |
        v  (wire passthrough per function, no FIFO needed)
qdma_subsystem_function.sv: s_axis_c2h_tuser_ptp_ts → m_axis_c2h_tuser_ptp_ts
        |
        v
qdma_subsystem_c2h.sv: arbiter muxes per-function timestamp
        |   writes to NEW 80-bit x 512-depth xpm_fifo_sync
        |   (write enable = cpl_fifo_wr_en, same as existing completion FIFO)
        v
Completion generation: reads timestamp FIFO alongside cpl_fifo
        packs into cpl_tdata[127:64] + cpl_tdata[15:0]
        sets cpl_size = 2'b01 (16 bytes)
```

**Key properties:**
- Timestamp sideband is a simple wire from function input to c2h arbiter -- no buffering, no FIFO in the function module
- The ONLY new FIFO is in `qdma_subsystem_c2h.sv`: a synchronous 80-bit FIFO (single clock domain `axis_aclk`)
- Write aligned to `cpl_fifo_wr_en` guarantees 1:1 correspondence with completion entries
- Existing `c2h_slice_inst`, `buf_fifo_inst`, arbiter, and `cpl_fifo` are completely untouched

### Why Wire Passthrough Is Safe in qdma_subsystem_function.sv

The timestamp sideband does NOT need its own buffering in the function module because:
1. The timestamp is metadata associated with the packet stream -- it holds constant during each packet
2. `packet_adapter_rx.sv` outputs timestamps via FWFT FIFO and pops on `m_axis_rx_tlast` -- the value is stable until the packet completes
3. The function module's buffer FIFO (`buf_fifo_inst`) and QID FIFO can stall the packet, but the timestamp wire just follows the packet timing
4. The timestamp is only sampled in `qdma_subsystem_c2h.sv` on the `cpl_fifo_wr_en` beat (post-arbiter tlast), at which point the correct function is selected and its timestamp is valid

**However**: If the buffer FIFO in qdma_subsystem_function holds multiple packets, the timestamp wire reflects the CURRENT input packet, not the packet being output. This is a problem.

**Correction**: We need a small sideband FIFO in `qdma_subsystem_function.sv` to hold timestamps for buffered packets. Use a synchronous `xpm_fifo_sync` (80-bit, depth = C_PKT_FIFO_DEPTH = 32):
- Write when: `s_axis_c2h_tvalid && s_axis_c2h_tlast && s_axis_c2h_tready` (input packet completes)
- Read when: `m_axis_c2h_tvalid && m_axis_c2h_tlast && m_axis_c2h_tready` (output packet completes)
- Output: `m_axis_c2h_tuser_ptp_ts = ptp_ts_fifo_dout`

This is still fully independent of the data path TUSER -- it's a separate FIFO with separate read/write enables.

### FPGA Changes

| # | File | Change |
|---|------|--------|
| 1 | `qdma_subsystem.sv` | Add `s_axis_c2h_tuser_ptp_ts` input port (80\*NUM_PHYS_FUNC bits). Thread to each `qdma_subsystem_function` instance. Collect outputs and pass to `qdma_subsystem_c2h`. |
| 2 | `qdma_subsystem_function.sv` | Add ptp_ts input/output ports. Add 80-bit x 32-depth `xpm_fifo_sync` sideband FIFO. Write on input tlast, read on output tlast. Output `m_axis_c2h_tuser_ptp_ts` from FIFO FWFT output. No changes to existing `c2h_slice_inst`, `buf_fifo_inst`, or QID FIFO. |
| 3 | `qdma_subsystem_c2h.sv` | Add ptp_ts input port (80\*NUM_PHYS_FUNC bits). Add arbiter mux for timestamp. Add 80-bit x 512-depth `xpm_fifo_sync` sideband FIFO (write on `cpl_fifo_wr_en`). Read alongside `cpl_fifo` during completion generation. Pack timestamp into `cpl_tdata[127:64]` + `cpl_tdata[15:0]`. Change `cpl_size` from `2'b00` to `2'b01`. |
| 4 | `open_nic_shell.sv` | Connect existing `axis_qdma_c2h_tuser_ptp_ts` wire to `qdma_subsystem_inst` new port. Wire already declared at line 381. |

### Driver Changes

| # | File | Change |
|---|------|--------|
| 5 | `qdma_access/qdma_export.h` | `QDMA_C2H_CMPL_SIZE = 16`. Add `ts_sec_hi`, `ts_ns`, `ts_sec_lo` fields to `struct qdma_c2h_cmpl`. Add DW1 bit masks. |
| 6 | `qdma_access/qdma_export.c` | Update `qdma_unpack_c2h_cmpl()` to read DW1 and extract timestamp fields. |
| 7 | `onic_netdev.c` | Change `cmpl_desc_sz` from 0 to 1 (16B). In `onic_rx_poll()`, after building skb: if `tstamp_config.rx_filter != HWTSTAMP_FILTER_NONE`, reconstruct 48-bit seconds + 32-bit ns from completion, call `skb_hwtstamps(skb)->hwtstamp = ktime_set(sec, nsec)`. |

---

## Part 2: TX Tag Injection (H2C Metadata)

### Design

Encode the 16-bit PTP tag in the upper 16 bits of the H2C descriptor's existing 32-bit metadata field. The FPGA extracts it and passes it through the existing sideband FIFO to the CMAC. After transmission, the CMAC returns the tag + timestamp via the TX TS FIFO, which the driver polls.

**Metadata encoding:** `desc.metadata = (ptp_tag << 16) | pkt_len`

**Tag flow:**
```
Driver: SKBTX_HW_TSTAMP → alloc tag N → desc.metadata[31:16] = N
  → QDMA H2C → qdma_subsystem_h2c extracts mdata[31:16]
  → qdma_subsystem_function → open_nic_shell → box_250mhz
  → packet_adapter_tx sideband FIFO (250→322 MHz)
  → CMAC tx_ptp_tag_field_in
  → CMAC stamps packet → tx_ptp_tstamp_tag_out = N
  → ptp_subsystem TX TS FIFO (322→250 MHz)
  → ptp_subsystem_register TX_TS_VALID/LO/HI/TAG registers
  → Driver poll → match tag N → skb_tstamp_tx(clone, &hwts)
```

### FPGA Changes

| # | File | Change |
|---|------|--------|
| 8 | `qdma_subsystem_h2c.sv` | Widen register slice TUSER_W from 33 to 49 bits. Extract `mdata[31:16]` as 16-bit ptp_tag. Add `m_axis_h2c_tuser_ptp_tag` output port. |
| 9 | `qdma_subsystem_function.sv` | Add H2C ptp_tag input/output ports. Passthrough wiring. |
| 10 | `qdma_subsystem.sv` | Wire ptp_tag from h2c instance through function instance. Add top-level output port. |
| 11 | `open_nic_shell.sv` | Remove ptp_tag tie-off (line ~444). Connect from QDMA subsystem output to existing `axis_qdma_h2c_tuser_ptp_tag` wire. |

**Note on H2C TUSER widening (item 8):** The H2C register slice TUSER widening from 33 to 49 bits is acceptable here because:
- It's only adding 16 bits (not 80) -- minimal timing impact
- The H2C path is simpler (no arbiter, no completion FIFO)
- The metadata is already in TUSER -- we're just extracting more of it
- Alternative: extract the tag from the data bus before the register slice, but this adds combinational logic in the critical path

### Driver Changes

| # | File | Change |
|---|------|--------|
| 12 | `onic_ptp.h` | Add `ONIC_PTP_TX_PENDING_MAX = 64`. Add `struct onic_ptp_tx_pending { struct sk_buff *skb_clone; ktime_t start; u16 tag; bool active; }`. Declare alloc/poll/work functions. |
| 13 | `onic.h` | Add to `onic_private`: `struct onic_ptp_tx_pending tx_pending[64]`, `u16 next_ptp_tag`, `spinlock_t ptp_tx_lock`, `struct delayed_work ptp_tx_work`. |
| 14 | `onic_ptp.c` | Implement `onic_ptp_alloc_tx_tag()` -- find free slot, store skb clone, assign monotonic tag (skip 0, wrap at 65535). Implement `onic_ptp_tx_ts_poll()` -- read TX_TS_VALID, if valid read LO/HI/TAG registers, match tag to pending array, call `skb_tstamp_tx()`. Implement delayed work function (poll every 1ms while HW TS enabled). Init/cleanup: initialize pending array, schedule/cancel work. |
| 15 | `onic_netdev.c` | In `onic_xmit_frame()`: if `skb_shinfo(skb)->tx_flags & SKBTX_HW_TSTAMP` and `priv->tstamp_config.tx_type == HWTSTAMP_TX_ON`, call `onic_ptp_alloc_tx_tag()` to get tag and store clone, set `desc.metadata = (tag << 16) | skb->len`. Else keep `desc.metadata = skb->len` and call `skb_tx_timestamp(skb)` for SW fallback. |

### TX_TS_TAG Register Layout

The register at per-port offset 0x008 packs two fields:
```
TX_TS_TAG[31:16] = PTP tag (16 bits)
TX_TS_TAG[15:0]  = timestamp bits [79:64] (upper 16 bits of seconds)
```

Driver extraction:
```c
u32 reg = onic_read_reg(hw, ONIC_PTP_TX_TS_TAG(port));
u16 tag = reg >> 16;
u16 ts_upper = reg & 0xFFFF;
// Full timestamp: ts = (ts_upper << 64) | (ts_hi << 32) | ts_lo
```

---

## Implementation Order

1. **RX path first** (items 1-7) -- enables `ptp4l -H` in slave mode (slave only needs RX timestamps on incoming Sync messages)
2. **TX path second** (items 8-15) -- enables TX timestamps for master mode and full 2-step operation
3. **Vivado synthesis** after each phase
4. **Test with existing two-host setup** (desktop <-> desktop-2, already verified with SW timestamps)

### Verification Steps

**After RX integration:**
```bash
# Enable HW timestamping
hwstamp_ctl -i enp1s0f0 -r 1
# Verify RX timestamps appear
tcpdump -i enp1s0f0 --time-stamp-precision=nano -c 10
# Try ptp4l slave with HW timestamps
ptp4l -i enp1s0f0 -H -2 --slaveOnly=1 -m
```

**After TX integration:**
```bash
# Try ptp4l master with HW timestamps
ptp4l -i enp1s0f0 -H -2 --masterOnly=1 -m
# Full bidirectional test
# Master: ptp4l -i enp1s0f0 -H -2 --masterOnly=1 -m
# Slave:  ptp4l -i enp1s0f0 -H -2 --slaveOnly=1 -m
# Expected: sub-microsecond offset
```

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Timestamp sideband FIFO in function module adds resource usage | Low | 80-bit x 32-depth sync FIFO = ~320 bytes distributed RAM, negligible |
| Timestamp sideband FIFO in c2h module (80x512) | Low | ~5 KB distributed RAM, well within capacity |
| Completion ring memory doubles (16KB->32KB/ring) | Low | Negligible on modern systems |
| QDMA IP color/err bit handling at 16B size | Low | Same behavior as 8B -- IP overwrites bits [1:2] |
| H2C register slice TUSER widening (33->49 bits) | Low | Only 16 extra bits; H2C path is simpler than C2H |
| TX tag FIFO overflow (>64 in-flight) | Low | Bounded by ONIC_PTP_TX_PENDING_MAX=64; PTP traffic is low rate |
| TX_TS_TAG register packing non-obvious | Medium | Document clearly; add debug prints during bring-up |
| Sideband FIFO sync (packet_adapter_tx depth=64) | Low | One tag per packet; data FIFO holds ~36 packets max |

---

## Files Summary

**FPGA (12 changes across 5 files):**
- `qdma_subsystem.sv` -- C2H ptp_ts threading + H2C ptp_tag output
- `qdma_subsystem_function.sv` -- C2H ptp_ts sideband FIFO (80x32, sync) + H2C tag passthrough
- `qdma_subsystem_c2h.sv` -- ptp_ts sideband FIFO (80x512, sync) + 16B completion packing
- `qdma_subsystem_h2c.sv` -- tag extraction from mdata[31:16]
- `open_nic_shell.sv` -- wire connections, remove tie-off

**Driver (7 changes across 6 files):**
- `qdma_export.h` -- 16B completion struct
- `qdma_export.c` -- unpack function
- `onic_netdev.c` -- cmpl_desc_sz, rx_poll hwtstamp, xmit_frame tag injection
- `onic_ptp.h` -- tag management types
- `onic_ptp.c` -- tag alloc, TX TS poll, delayed work
- `onic.h` -- private struct fields
