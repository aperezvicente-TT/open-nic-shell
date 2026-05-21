"""
test_passthrough — P0 acceptance test.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CLK_NS = 4  # 250 MHz


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
    # Wait for ARREADY
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            break
    else:
        raise AssertionError(f"ARREADY never asserted for addr 0x{addr:08X}")
    dut.s_axil_arvalid.value = 0
    # Wait for RVALID
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            return int(dut.s_axil_rdata.value)
    raise AssertionError(f"RVALID never asserted for addr 0x{addr:08X}")


@cocotb.test()
async def test_version_register_reads_correctly(dut):
    """0x000 must read 0x00010000 (TT-RDMA-v1.0 marker)."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    version = await _axil_read(dut, 0x000)
    assert version == 0x00010000, \
        f"VERSION reg expected 0x00010000, got 0x{version:08X}"


@cocotb.test()
async def test_mtu_default_is_4080(dut):
    """cfg_mtu reset must be 4080 — bridge session lesson, do not silently regress."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    mtu = await _axil_read(dut, 0x024)
    assert (mtu & 0xFFFF) == 4080, \
        (f"cfg_mtu expected 4080 (jumbo default), got {mtu & 0xFFFF}. "
         "Do NOT lower it to 1500 — bridge session lost a full rebuild "
         "cycle to every 1542 B encap'd frame being silently dropped.")


@cocotb.test()
async def test_ethertype_default_is_0x1AF6(dut):
    """cfg_ethertype reset must be 0x1AF6 — the production TT-RDMA-v1 wire."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)
    et = await _axil_read(dut, 0x020)
    assert (et & 0xFFFF) == 0x1AF6, \
        f"cfg_ethertype expected 0x1AF6, got 0x{et:04X}"


@cocotb.test()
async def test_ethertype_is_readonly_locked(dut):
    """0x020 is locked per README:111.  A write must NOT change the read
    value — a stale bring-up tool cannot retarget the classifier."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Try to corrupt the ethertype register
    dut.s_axil_awaddr.value  = 0x020
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = 0x1234
    dut.s_axil_wvalid.value  = 1
    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            break
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    for _ in range(5):
        await RisingEdge(dut.clk)

    et = await _axil_read(dut, 0x020)
    assert (et & 0xFFFF) == 0x1AF6, \
        f"ETHERTYPE must stay locked at 0x1AF6 after a hostile write; got 0x{et:04X}"


@cocotb.test()
async def test_rx_drained(dut):
    """CMAC0 RX tready must hold high so upstream never stalls."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    for _ in range(20):
        dut.s_axis_cmac0_rx_tvalid.value = 1
        dut.s_axis_cmac0_rx_tdata.value  = 0xDEADBEEF
        dut.s_axis_cmac0_rx_tkeep.value  = (1 << 64) - 1
        dut.s_axis_cmac0_rx_tlast.value  = 0
        await RisingEdge(dut.clk)
        assert int(dut.s_axis_cmac0_rx_tready.value) == 1, \
            "CMAC0 RX tready dropped — upstream would stall"
