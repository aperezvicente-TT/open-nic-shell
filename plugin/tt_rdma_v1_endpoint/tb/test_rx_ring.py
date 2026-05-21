"""
test_rx_ring — Phase C acceptance test.

Per PRODUCTION_PLAN.md §3 Phase C:
  - SEND / SEND_IMM frames produce one ring slot each
  - prod_idx walks the ring
  - OWNED_BY_HOST byte set (bit 0 of slot byte 0x15)
  - mr_table_idx = 0xFF (ring-slot SEND marker per host-sdk.md §3)
  - status byte = 0 (kOk)
  - Frame fields (peer_seq, length, opcode, immediate) round-trip into
    the slot header at the correct byte offsets
  - On ring full (prod - cons >= 64), overflow_drops increments and
    prod_idx does NOT advance — the host must never see a skipped slot

CSRs touched:
  0x040  rx_ring_base_lo / _hi    (RW)
  0x048  rx_ring_log2n            (RW, default 6 = 64 slots)
  0x04C  rx_slot_stride           (RW, default 1536)
  0x050  rx_prod_idx              (RO, live)
  0x054  rx_cons_idx              (RW, host writes to free slots)
  0x058  rx_overflow_drops        (RO, counter)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CLK_NS = 4
RING_DEPTH = 64


async def _reset(dut, cycles=5):
    dut.rst_n.value = 0
    dut.s_axil_awvalid.value = 0
    dut.s_axil_awaddr.value  = 0
    dut.s_axil_wvalid.value  = 0
    dut.s_axil_wdata.value   = 0
    dut.s_axil_bready.value  = 1
    dut.s_axil_arvalid.value = 0
    dut.s_axil_araddr.value  = 0
    dut.s_axil_rready.value  = 1
    dut.s_axis_cmac0_rx_tvalid.value = 0
    dut.s_axis_cmac0_rx_tdata.value  = 0
    dut.s_axis_cmac0_rx_tkeep.value  = 0
    dut.s_axis_cmac0_rx_tlast.value  = 0
    dut.s_axis_cmac0_rx_tuser.value  = 0
    dut.m_axis_cmac0_tx_tready.value = 1
    dut.m_axis_ring_push_tready.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


async def _axil_read(dut, addr):
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            break
    else:
        raise AssertionError(f"ARREADY never asserted for 0x{addr:08X}")
    dut.s_axil_arvalid.value = 0
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            return int(dut.s_axil_rdata.value)
    raise AssertionError(f"RVALID never asserted for 0x{addr:08X}")


async def _axil_write(dut, addr, data):
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data
    dut.s_axil_wvalid.value  = 1
    aw_done = False
    w_done  = False
    b_seen  = False
    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_awvalid.value) == 1 and int(dut.s_axil_awready.value) == 1:
            aw_done = True
            dut.s_axil_awvalid.value = 0
        if int(dut.s_axil_wvalid.value) == 1 and int(dut.s_axil_wready.value) == 1:
            w_done = True
            dut.s_axil_wvalid.value = 0
        if int(dut.s_axil_bvalid.value) == 1:
            b_seen = True
        if aw_done and w_done and b_seen:
            return
    raise AssertionError(f"Write to 0x{addr:08X} didn't complete")


def _build_send_frame(opcode, peer_seq, length, immediate=0):
    """Beat-0 RDMA frame with given opcode + header fields."""
    frame = bytearray(64)
    frame[0:6]   = bytes.fromhex("1070FDD69D58")
    frame[6:12]  = bytes.fromhex("020000000100")
    frame[12]    = 0x1A
    frame[13]    = 0xF6
    frame[14]    = opcode
    frame[15]    = 0x01           # version_flags
    # tag at 16-17 (LE 0)
    # length BE at 18-21
    frame[18] = (length >> 24) & 0xFF
    frame[19] = (length >> 16) & 0xFF
    frame[20] = (length >>  8) & 0xFF
    frame[21] = (length      ) & 0xFF
    # seq BE at 22-25
    frame[22] = (peer_seq >> 24) & 0xFF
    frame[23] = (peer_seq >> 16) & 0xFF
    frame[24] = (peer_seq >>  8) & 0xFF
    frame[25] = (peer_seq      ) & 0xFF
    # imm_data BE at 38-41
    frame[38] = (immediate >> 24) & 0xFF
    frame[39] = (immediate >> 16) & 0xFF
    frame[40] = (immediate >>  8) & 0xFF
    frame[41] = (immediate      ) & 0xFF
    return bytes(frame)


async def _send_classified_frame(dut, opcode, peer_seq, length, immediate=0):
    """Drive a single-beat RDMA-v1 frame at the classifier input."""
    beat = _build_send_frame(opcode, peer_seq, length, immediate)
    dut.s_axis_cmac0_rx_tvalid.value = 1
    dut.s_axis_cmac0_rx_tdata.value  = int.from_bytes(beat, "little")
    dut.s_axis_cmac0_rx_tkeep.value  = (1 << 64) - 1
    dut.s_axis_cmac0_rx_tlast.value  = 1
    dut.s_axis_cmac0_rx_tuser.value  = 64
    await RisingEdge(dut.clk)
    while int(dut.s_axis_cmac0_rx_tready.value) == 0:
        await RisingEdge(dut.clk)
    dut.s_axis_cmac0_rx_tvalid.value = 0
    dut.s_axis_cmac0_rx_tlast.value  = 0
    # Allow 5 clocks for: classifier (1) → parser (1) → ring (1) → CSR settle
    for _ in range(5):
        await RisingEdge(dut.clk)


async def _capture_ring_push(dut, max_cycles=200):
    """Wait for a single ring_push beat and return (tdata_bytes, slot_idx)."""
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.m_axis_ring_push_tvalid.value) == 1 and \
           int(dut.m_axis_ring_push_tready.value) == 1:
            tdata = int(dut.m_axis_ring_push_tdata.value)
            slot  = int(dut.m_axis_ring_push_tuser_slot.value)
            tlast = int(dut.m_axis_ring_push_tlast.value)
            assert tlast == 1, "Phase C ring push must be 1-beat (tlast=1)"
            return tdata.to_bytes(64, "little"), slot
    raise AssertionError("ring_push beat never appeared")


@cocotb.test()
async def test_send_publishes_one_slot(dut):
    """A single SEND frame produces exactly one ring slot with the right format."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    peer_seq  = 0x12345678
    length    = 0x000003C0   # arbitrary 960 B
    immediate = 0  # not SEND_IMM

    pre_prod = await _axil_read(dut, 0x050)
    assert pre_prod == 0, f"pre prod_idx should be 0, got {pre_prod}"

    send_task    = cocotb.start_soon(_send_classified_frame(dut, 0x01, peer_seq, length))
    slot_bytes, slot_idx = await _capture_ring_push(dut)
    await send_task

    # Slot layout (host-sdk.md §3)
    sl_peer_seq      = int.from_bytes(slot_bytes[0:4], "little")
    sl_length        = int.from_bytes(slot_bytes[4:8], "little")
    sl_opcode        = slot_bytes[8]
    sl_status        = slot_bytes[9]
    sl_immediate     = int.from_bytes(slot_bytes[0x0C:0x10], "little")
    sl_mr_table_idx  = slot_bytes[0x14]
    sl_flags         = slot_bytes[0x15]

    assert sl_peer_seq     == peer_seq,    f"peer_seq mismatch: 0x{sl_peer_seq:08X}"
    assert sl_length       == length,      f"length mismatch:   0x{sl_length:08X}"
    assert sl_opcode       == 0x01,        f"opcode mismatch:   0x{sl_opcode:02X}"
    assert sl_status       == 0,           f"status should be 0 (kOk), got 0x{sl_status:02X}"
    assert sl_immediate    == immediate,   f"immediate mismatch: 0x{sl_immediate:08X}"
    assert sl_mr_table_idx == 0xFF,        f"mr_table_idx should be 0xFF for ring SEND, got 0x{sl_mr_table_idx:02X}"
    assert (sl_flags & 0x01) == 1, \
        f"OWNED_BY_HOST (flags bit 0) MUST be set, got flags=0x{sl_flags:02X}"

    assert slot_idx == 0, f"First slot index should be 0, got {slot_idx}"

    post_prod = await _axil_read(dut, 0x050)
    assert post_prod == 1, f"prod_idx should be 1 after one SEND, got {post_prod}"


@cocotb.test()
async def test_send_imm_carries_immediate(dut):
    """SEND_IMM frame propagates immediate into slot byte 0x0C."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    send_task    = cocotb.start_soon(
        _send_classified_frame(dut, 0x02, 0x55AA1234, 0x100, immediate=0xCAFEBABE)
    )
    slot_bytes, _ = await _capture_ring_push(dut)
    await send_task

    sl_opcode    = slot_bytes[8]
    sl_immediate = int.from_bytes(slot_bytes[0x0C:0x10], "little")

    assert sl_opcode    == 0x02
    assert sl_immediate == 0xCAFEBABE, f"immediate should be 0xCAFEBABE, got 0x{sl_immediate:08X}"


@cocotb.test()
async def test_prod_idx_walks_n_sends(dut):
    """Send 20 SENDs (well under ring size), prod_idx and slot_idx walk in lockstep."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    N = 20
    for i in range(N):
        send_task = cocotb.start_soon(
            _send_classified_frame(dut, 0x01, 0xA0000000 | i, 0x40)
        )
        slot_bytes, slot_idx = await _capture_ring_push(dut)
        await send_task

        assert slot_idx == i, f"slot {i} arrived as slot_idx={slot_idx}"
        sl_seq = int.from_bytes(slot_bytes[0:4], "little")
        assert sl_seq == 0xA0000000 | i, f"slot {i} peer_seq mismatch"

    prod = await _axil_read(dut, 0x050)
    assert prod == N, f"prod_idx should be {N}, got {prod}"
    drops = await _axil_read(dut, 0x058)
    assert drops == 0, f"No drops expected, got {drops}"


@cocotb.test()
async def test_overflow_drops_when_ring_full(dut):
    """With host-side cons_idx never advancing, 65th SEND drops + counter ticks."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Block downstream ring_push by holding tready low so the engine
    # has to honor backpressure.  Actually simpler: leave tready high
    # so prod_idx walks freely, but never let host (us) advance cons_idx.
    # First 64 sends will fill ring; 65th hits overflow.

    # Fill the ring (cons stays at 0).
    for i in range(RING_DEPTH):
        send_task = cocotb.start_soon(
            _send_classified_frame(dut, 0x01, i, 0x40)
        )
        await _capture_ring_push(dut)
        await send_task

    prod_full = await _axil_read(dut, 0x050)
    assert prod_full == RING_DEPTH, f"After full ring, prod={prod_full} expected {RING_DEPTH}"
    drops_before = await _axil_read(dut, 0x058)
    assert drops_before == 0

    # 65th SEND must drop + bump counter, prod_idx must NOT advance
    await _send_classified_frame(dut, 0x01, 0xDEAD0000, 0x40)

    prod_after = await _axil_read(dut, 0x050)
    drops_after = await _axil_read(dut, 0x058)
    assert prod_after == RING_DEPTH, \
        f"prod_idx must NOT advance on overflow; got {prod_after} (expected {RING_DEPTH})"
    assert drops_after == 1, \
        f"rx_overflow_drops should be 1, got {drops_after}"

    # Free one slot by advancing cons_idx → next SEND must succeed
    await _axil_write(dut, 0x054, 1)
    send_task = cocotb.start_soon(
        _send_classified_frame(dut, 0x01, 0xBEEF0000, 0x40)
    )
    slot_bytes, slot_idx = await _capture_ring_push(dut)
    await send_task

    assert slot_idx == (RING_DEPTH & 0x3F), \
        f"After cons advance, next slot should be 0 (wrap), got {slot_idx}"
    prod_recovered = await _axil_read(dut, 0x050)
    assert prod_recovered == RING_DEPTH + 1, \
        f"prod_idx after recovery should be {RING_DEPTH+1}, got {prod_recovered}"


@cocotb.test()
async def test_write_opcode_does_not_consume_slot(dut):
    """WRITE (not SEND) must bypass the ring per host-sdk.md §3."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Drive a WRITE frame.  prod_idx must remain 0; no ring_push beat.
    send_task = cocotb.start_soon(_send_classified_frame(dut, 0x10, 0x42, 0x100))
    # Race: give some cycles for any erroneous publish to land
    saw_publish = False
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.m_axis_ring_push_tvalid.value) == 1 and \
           int(dut.m_axis_ring_push_tready.value) == 1:
            saw_publish = True
            break
    await send_task

    assert not saw_publish, "WRITE incorrectly published a ring slot"
    prod = await _axil_read(dut, 0x050)
    assert prod == 0, f"prod_idx should stay 0 for WRITE; got {prod}"
