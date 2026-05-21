"""
test_opcode_dispatch — Phase B acceptance test.

Per PRODUCTION_PLAN.md Phase B: every TT-RDMA-v1 opcode dispatches to
the correct counter; unknown opcodes increment the unknown counter;
non-TT-RDMA-v1 ethertypes hit ethtype_drop or ethtype_legacy.

Counter map (from rdma_regs.sv):
  0x300  cnt_op_send
  0x304  cnt_op_send_imm
  0x308  cnt_op_write
  0x30C  cnt_op_write_imm
  0x310  cnt_op_read_req
  0x314  cnt_op_read_resp
  0x318  cnt_op_ack
  0x31C  cnt_op_control
  0x320  cnt_op_unknown
  0x334  cnt_ethtype_drop
  0x518  cnt_ethtype_legacy   (0x1AF4 / 0x1AF5)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CLK_NS = 4

# (ethertype, opcode) → expected counter offset
OPCODE_MAP = {
    0x01: 0x300,   # SEND
    0x02: 0x304,   # SEND_IMM
    0x10: 0x308,   # WRITE
    0x11: 0x30C,   # WRITE_IMM
    0x20: 0x310,   # READ_REQ
    0x21: 0x314,   # READ_RESP
    0x40: 0x318,   # ACK
    0xF0: 0x31C,   # CONTROL
}
OP_UNKNOWN_OFFSET     = 0x320
ETHTYPE_DROP_OFFSET   = 0x334
ETHTYPE_LEGACY_OFFSET = 0x518


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
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    # Wait for generic_reset (RESET_DURATION + S_FLUSH window) to settle.
    for _ in range(20):
        await RisingEdge(dut.clk)


async def _axil_read(dut, addr):
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            break
    else:
        raise AssertionError(f"ARREADY never asserted for addr 0x{addr:08X}")
    dut.s_axil_arvalid.value = 0
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            return int(dut.s_axil_rdata.value)
    raise AssertionError(f"RVALID never asserted for addr 0x{addr:08X}")


def _build_beat0(ethertype, opcode, payload_after_hdr=b""):
    """Compose 64 B beat-0 with given ethertype + RDMA opcode at byte 14.

    Wire layout, byte-positioned (LE bus):
      bytes 0-5    dst MAC      0x10 0x70 0xFD 0xD6 0x9D 0x58  (Mellanox)
      bytes 6-11   src MAC      0x02 0x00 0x00 0x00 0x01 0x00  (bridge LOCAL_MAC)
      bytes 12-13  ethertype    {hi, lo}
      byte  14     opcode
      byte  15     version_flags = 0x01
      bytes 16-17  tag           = 0x0000
      bytes 18-21  length        = 0x00000000
      bytes 22-25  seq           = 0x00000000
      bytes 26-29  rkey          = 0x00000000
      bytes 30-37  remote_offset = 0
      bytes 38-41  imm_data      = 0
      bytes 42-45  header_cksum  = 0
      bytes 46-63  start of payload (zero-filled)
    """
    frame = bytearray(64)
    frame[0:6]   = bytes.fromhex("1070FDD69D58")
    frame[6:12]  = bytes.fromhex("020000000100")
    frame[12]    = (ethertype >> 8) & 0xFF
    frame[13]    = ethertype & 0xFF
    frame[14]    = opcode
    frame[15]    = 0x01
    # 16..45 already 0
    # 46..63 already 0 (payload start)
    return bytes(frame)


async def _send_one_beat_frame(dut, ethertype, opcode):
    """Drive a single-beat frame with given ethertype+opcode."""
    beat = _build_beat0(ethertype, opcode)
    tdata = int.from_bytes(beat, "little")
    dut.s_axis_cmac0_rx_tvalid.value = 1
    dut.s_axis_cmac0_rx_tdata.value  = tdata
    dut.s_axis_cmac0_rx_tkeep.value  = (1 << 64) - 1  # all 64 bytes valid
    dut.s_axis_cmac0_rx_tlast.value  = 1
    dut.s_axis_cmac0_rx_tuser.value  = 64
    # Hold until tready accepts the beat
    await RisingEdge(dut.clk)
    while int(dut.s_axis_cmac0_rx_tready.value) == 0:
        await RisingEdge(dut.clk)
    dut.s_axis_cmac0_rx_tvalid.value = 0
    dut.s_axis_cmac0_rx_tlast.value  = 0
    # Allow time for: classifier (1) → parser (1) → cdc_pulse_sync axis→axil
    # (toggle + 2-FF sync + edge detect, ~4 cycles) → CSR increment (1).
    for _ in range(15):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_each_opcode_increments_its_counter(dut):
    """One frame per known opcode → corresponding counter goes from 0 to 1."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    for opcode, offset in OPCODE_MAP.items():
        # Confirm counter is 0 before
        before = await _axil_read(dut, offset)
        assert before == 0, \
            f"Counter 0x{offset:03X} pre-fire is {before}, expected 0"

        await _send_one_beat_frame(dut, 0x1AF6, opcode)

        after = await _axil_read(dut, offset)
        assert after == 1, \
            f"Counter 0x{offset:03X} for opcode 0x{opcode:02X} expected 1, got {after}"


@cocotb.test()
async def test_unknown_opcode_increments_unknown_counter(dut):
    """Opcodes 0x00, 0x55, 0xAA (not in the legal set) hit op_unknown."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    unknown_ops = [0x00, 0x55, 0xAA]
    for op in unknown_ops:
        await _send_one_beat_frame(dut, 0x1AF6, op)

    cnt = await _axil_read(dut, OP_UNKNOWN_OFFSET)
    assert cnt == len(unknown_ops), \
        f"Expected op_unknown counter == {len(unknown_ops)}, got {cnt}"

    # Also: any legal-opcode counter must remain 0
    for off in OPCODE_MAP.values():
        c = await _axil_read(dut, off)
        assert c == 0, \
            f"Legal-opcode counter 0x{off:03X} should be 0, got {c}"


@cocotb.test()
async def test_ethtype_drop_counts_non_matching(dut):
    """Frames with ethertype != 0x1AF6/0x1AF4/0x1AF5 hit ethtype_drop."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # IPv4, IPv6, ARP, plain TT-link (0x9999) — none match
    bogus = [0x0800, 0x86DD, 0x0806, 0x9999, 0x88B5]
    for et in bogus:
        await _send_one_beat_frame(dut, et, 0x01)

    cnt = await _axil_read(dut, ETHTYPE_DROP_OFFSET)
    assert cnt == len(bogus), \
        f"Expected ethtype_drop == {len(bogus)}, got {cnt}"

    # And no opcode counter should have moved
    cnt_send = await _axil_read(dut, 0x300)
    assert cnt_send == 0, f"op_send counter leaked: {cnt_send}"


@cocotb.test()
async def test_legacy_ethertypes_count_separately(dut):
    """0x1AF4 and 0x1AF5 hit ethtype_legacy, not ethtype_drop."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    await _send_one_beat_frame(dut, 0x1AF4, 0x01)
    await _send_one_beat_frame(dut, 0x1AF5, 0x01)

    legacy = await _axil_read(dut, ETHTYPE_LEGACY_OFFSET)
    drop   = await _axil_read(dut, ETHTYPE_DROP_OFFSET)
    assert legacy == 2, f"ethtype_legacy expected 2, got {legacy}"
    assert drop   == 0, f"ethtype_drop expected 0, got {drop}"


@cocotb.test()
async def test_clear_all_counters_snaps_back_to_zero(dut):
    """A write to 0x5FC snaps every per-opcode + ethertype counter to 0.
    Lets bring-up scripts snapshot-and-clear without bouncing PCIe."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Drive a few frames so the counters move
    for opcode in (0x01, 0x02, 0x10, 0xF0):
        await _send_one_beat_frame(dut, 0x1AF6, opcode)
    await _send_one_beat_frame(dut, 0x0800, 0x01)  # ethtype_drop
    await _send_one_beat_frame(dut, 0x1AF4, 0x01)  # ethtype_legacy

    # All four opcode counters and the drop/legacy counters should be > 0
    assert (await _axil_read(dut, 0x300)) == 1
    assert (await _axil_read(dut, 0x334)) == 1
    assert (await _axil_read(dut, 0x518)) == 1

    # Write any value to 0x5FC → clear
    dut.s_axil_awaddr.value  = 0x5FC
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = 0xDEAD
    dut.s_axil_wvalid.value  = 1
    for _ in range(30):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            break
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    for _ in range(5):
        await RisingEdge(dut.clk)

    # All counters now zero
    for offset in (0x300, 0x304, 0x308, 0x31C, 0x334, 0x518):
        c = await _axil_read(dut, offset)
        assert c == 0, f"Counter 0x{offset:03X} should be 0 after 0x5FC clear; got {c}"


@cocotb.test()
async def test_mixed_burst_8x(dut):
    """Burst all 8 opcodes back-to-back; every counter ends at 1."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    for opcode in OPCODE_MAP.keys():
        await _send_one_beat_frame(dut, 0x1AF6, opcode)

    for opcode, off in OPCODE_MAP.items():
        c = await _axil_read(dut, off)
        assert c == 1, \
            f"Opcode 0x{opcode:02X} counter 0x{off:03X} expected 1, got {c}"
