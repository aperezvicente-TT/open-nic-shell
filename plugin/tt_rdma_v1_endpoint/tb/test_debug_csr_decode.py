"""
test_debug_csr_decode — Phase A: per-opcode + general debug counter
block address decode is in place ahead of the engines that will drive them.

The lesson behind this test: during the UDP bridge session we shipped
debug counters at 0x440-0x44C mid-debug, costing a full rebuild cycle.
Designing the address decode in up front means later engines plug into
existing CSR slots without re-touching this file or the host scripts.

For Phase A the counters are decoded but always 0.  When engines wire
in (Phase B/P1/...) they replace the constant-0 path.  The test here
distinguishes "address is mapped, counter is 0" (correct Phase A) from
"address returns 0xDEADBEEF" (decode missing — regression).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CLK_NS = 4


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
        raise AssertionError(f"ARREADY never asserted for addr 0x{addr:08X}")
    dut.s_axil_arvalid.value = 0
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            return int(dut.s_axil_rdata.value)
    raise AssertionError(f"RVALID never asserted for addr 0x{addr:08X}")


# Per-opcode counter slots, 32-bit each:
PER_OPCODE_OFFSETS = [
    0x300,  # OP_SEND
    0x304,  # OP_SEND_IMM
    0x308,  # OP_WRITE
    0x30C,  # OP_WRITE_IMM
    0x310,  # OP_READ_REQ
    0x314,  # OP_READ_RESP
    0x318,  # OP_ACK
    0x31C,  # OP_CONTROL
    0x320,  # OP_UNKNOWN
    0x324,  # RKEY_MISS
    0x328,  # RKEY_ACCESS
    0x32C,  # RKEY_BOUNDS
    0x330,  # HDR_CKSUM_FAIL
    0x334,  # ETHTYPE_DROP
    0x338,  # BAD_DST_DROP
    0x33C,  # QDMA_WR_ERR
]


@cocotb.test()
async def test_per_opcode_block_returns_zero(dut):
    """0x300-0x33C — counter slots present, value 0 until engines drive them."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    for off in PER_OPCODE_OFFSETS:
        val = await _axil_read(dut, off)
        assert val == 0, (
            f"CSR 0x{off:03X} returns 0x{val:08X}, expected 0.  "
            "0xDEADBEEF means the address slot was never decoded — "
            "regression: this block was designed in at Phase A."
        )


@cocotb.test()
async def test_debug_block_500_returns_zero(dut):
    """0x500-0x5FC — general debug counter block.  Sample 8 addresses."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    for off in (0x500, 0x504, 0x508, 0x50C, 0x540, 0x580, 0x5C0, 0x5FC):
        val = await _axil_read(dut, off)
        assert val == 0, \
            f"CSR 0x{off:03X} returns 0x{val:08X}, expected 0."


@cocotb.test()
async def test_unmapped_addr_returns_deadbeef(dut):
    """Addresses outside the mapped ranges return 0xDEADBEEF (the legacy default)."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    # 0x100 is unmapped (sits in the future MR-table region but not
    # decoded yet at Phase A).  This is the right behaviour: returning
    # 0xDEADBEEF makes "I forgot to add the decode" obvious in PIO traces.
    val = await _axil_read(dut, 0x100)
    assert val == 0xDEADBEEF, (
        f"Expected unmapped 0x100 to return 0xDEADBEEF, got 0x{val:08X}.  "
        "If you just added a feature that uses this address, also add it "
        "to test_per_opcode_block_returns_zero / test_debug_block_500_returns_zero."
    )
