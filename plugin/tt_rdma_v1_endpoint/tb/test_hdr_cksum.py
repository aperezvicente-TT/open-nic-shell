"""
test_hdr_cksum — header CRC32C validate path.

Per [[tt-rdma-v1-header-cksum-keep-default-off]]: the FPGA endpoint
implements CRC32C compute+validate but ships with CTRL.cksum_check_en=0
so it interops with the current WH FW ecosystem (none of which compute
header_cksum on TX).

This test verifies:
  - default-off (CTRL bit 3 == 0): mismatching CRC is silently ignored,
    op_* counter still fires, hdr_cksum_fail counter stays at 0.
  - validate-on, matching CRC: frame dispatches, hdr_cksum_fail stays 0.
  - validate-on, mismatching CRC: op_* counter does NOT fire,
    hdr_cksum_fail counter increments by 1.

CRC32C parameters (must match rdma_hdr_parser.sv crc32c_28b and
main_cmac_rdma_inject.cc crc32c):
  reflected poly = 0x82F63B78, init = 0xFFFFFFFF, final XOR = 0xFFFFFFFF.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CLK_NS = 4

OFFSET_CTRL              = 0x008
OFFSET_OP_SEND           = 0x300
OFFSET_HDR_CKSUM_FAIL    = 0x330
CTRL_CKSUM_CHECK_EN_BIT  = (1 << 3)


def crc32c(data: bytes) -> int:
    """Reflected Castagnoli, init=0xFFFFFFFF, final XOR=0xFFFFFFFF."""
    c = 0xFFFFFFFF
    for b in data:
        c ^= b
        for _ in range(8):
            c = (0x82F63B78 ^ (c >> 1)) if (c & 1) else (c >> 1)
    return c ^ 0xFFFFFFFF


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


async def _axil_write(dut, addr, data):
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data
    dut.s_axil_wvalid.value  = 1
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            break
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    for _ in range(5):
        await RisingEdge(dut.clk)


def _build_beat0(opcode: int, cksum: int) -> bytes:
    """Compose 64 B beat-0 with ethertype 0x1AF6 + opcode + arbitrary cksum.

    Header bytes (post-L2 strip — RDMA header bytes [0..27]) are all-zero
    except for opcode at hdr[0] and version_flags=0x01 at hdr[1].  The
    32-bit CRC sits LE at frame bytes 42..45.
    """
    frame = bytearray(64)
    frame[0:6]   = bytes.fromhex("1070FDD69D58")
    frame[6:12]  = bytes.fromhex("020000000100")
    frame[12]    = 0x1A
    frame[13]    = 0xF6
    frame[14]    = opcode
    frame[15]    = 0x01      # version_flags.ver = 1
    # bytes 16..41 already zero
    frame[42]    =  cksum        & 0xFF
    frame[43]    = (cksum >>  8) & 0xFF
    frame[44]    = (cksum >> 16) & 0xFF
    frame[45]    = (cksum >> 24) & 0xFF
    # bytes 46..63 already zero (payload start)
    return bytes(frame)


def _good_cksum(opcode: int) -> int:
    """CRC32C over the 28-byte header for the all-zero-but-opcode frame."""
    hdr = bytearray(28)
    hdr[0] = opcode
    hdr[1] = 0x01
    return crc32c(bytes(hdr))


async def _send_frame(dut, frame: bytes):
    tdata = int.from_bytes(frame, "little")
    dut.s_axis_cmac0_rx_tvalid.value = 1
    dut.s_axis_cmac0_rx_tdata.value  = tdata
    dut.s_axis_cmac0_rx_tkeep.value  = (1 << 64) - 1
    dut.s_axis_cmac0_rx_tlast.value  = 1
    dut.s_axis_cmac0_rx_tuser.value  = 64
    await RisingEdge(dut.clk)
    while int(dut.s_axis_cmac0_rx_tready.value) == 0:
        await RisingEdge(dut.clk)
    dut.s_axis_cmac0_rx_tvalid.value = 0
    dut.s_axis_cmac0_rx_tlast.value  = 0
    # Classifier+parser+CDC settle (~15 cycles is enough per opcode_dispatch tb)
    for _ in range(15):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_default_off_ignores_bad_cksum(dut):
    """CTRL.cksum_check_en=0 at reset → mismatching CRC dispatches normally."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Verify default reset value of CTRL: bit 3 must be 0
    ctrl = await _axil_read(dut, OFFSET_CTRL)
    assert (ctrl & CTRL_CKSUM_CHECK_EN_BIT) == 0, \
        f"CTRL.cksum_check_en must default to 0; got CTRL=0x{ctrl:08X}"

    # Send SEND frame with deliberately wrong CRC
    await _send_frame(dut, _build_beat0(0x01, cksum=0xDEADBEEF))

    # Op counter must increment (CRC is being ignored)
    assert (await _axil_read(dut, OFFSET_OP_SEND)) == 1
    # Fail counter must stay 0
    assert (await _axil_read(dut, OFFSET_HDR_CKSUM_FAIL)) == 0


@cocotb.test()
async def test_validate_on_good_cksum_passes(dut):
    """With validate enabled and a matching CRC, frame dispatches."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Enable cksum_check_en
    await _axil_write(dut, OFFSET_CTRL, CTRL_CKSUM_CHECK_EN_BIT)

    # Send SEND frame with the correct CRC
    await _send_frame(dut, _build_beat0(0x01, cksum=_good_cksum(0x01)))

    assert (await _axil_read(dut, OFFSET_OP_SEND)) == 1
    assert (await _axil_read(dut, OFFSET_HDR_CKSUM_FAIL)) == 0


@cocotb.test()
async def test_validate_on_bad_cksum_drops(dut):
    """Validate enabled + bad CRC → op counter stays 0, fail counter ticks."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    await _axil_write(dut, OFFSET_CTRL, CTRL_CKSUM_CHECK_EN_BIT)

    # Send SEND frame with wrong CRC
    await _send_frame(dut, _build_beat0(0x01, cksum=0x00000000))

    assert (await _axil_read(dut, OFFSET_OP_SEND)) == 0, \
        "op_send must NOT increment when CRC fails and validate is on"
    assert (await _axil_read(dut, OFFSET_HDR_CKSUM_FAIL)) == 1, \
        "hdr_cksum_fail must increment by 1"


@cocotb.test()
async def test_validate_on_multiple_failures(dut):
    """N frames with bad CRC → fail counter == N, op counters all 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    await _axil_write(dut, OFFSET_CTRL, CTRL_CKSUM_CHECK_EN_BIT)

    N = 5
    for _ in range(N):
        await _send_frame(dut, _build_beat0(0x10, cksum=0xBADBADBA))  # WRITE

    assert (await _axil_read(dut, 0x308)) == 0, "WRITE counter must stay 0"
    assert (await _axil_read(dut, OFFSET_HDR_CKSUM_FAIL)) == N
