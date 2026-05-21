"""
test_mtu_default — regression for the cfg_mtu silent-oversize bug.

Bug history: tt_link_regs.sv had `cfg_mtu <= 16'd1500` at reset. WH FW
sent 1500 B payload + 14 B inner Eth = 1514 B inner frame. encap stripped
the inner Eth (14 B) and prepended Eth+IP+UDP (42 B), net +28 B, so the
wire frame was 1542 B. encap.sv checks `tuser_size > cfg_mtu` and
silently rejects, incrementing tx_oversize. At line rate we lost all
597 M frames as "oversize" before noticing.

This test verifies:
  - At reset, cfg_mtu (CSR 0x024) reads 4080 (0x0FF0) — the validated
    jumbo point per README:91.  Default-1500 is the regression we're
    guarding against; 9216 is known to hang CMAC TX (open question per
    README:180); 4080 is the proven safe point until P7 binary-sweeps.
  - cfg_mtu is writable to higher jumbo values (sanity for future P7).
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


@cocotb.test()
async def test_mtu_reset_is_4080(dut):
    """cfg_mtu @ 0x024 must read 4080 at reset.  NEVER lower this to 1500."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    mtu_raw = await _axil_read(dut, 0x024)
    mtu = mtu_raw & 0xFFFF
    assert mtu == 4080, (
        f"cfg_mtu default is {mtu}, expected 4080.  This is the regression "
        "from the UDP bridge session: a default of 1500 silently rejected "
        "every 1542 B encap'd frame as tx_oversize.  Do NOT lower this."
    )


@cocotb.test()
async def test_mtu_is_writable_above_1500(dut):
    """cfg_mtu must be writable to jumbo values (sanity)."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    # Write 4096 to cfg_mtu
    dut.s_axil_awaddr.value  = 0x024
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = 4096
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
            break

    assert aw_done and w_done and b_seen, "Write to cfg_mtu didn't complete"

    mtu_raw = await _axil_read(dut, 0x024)
    mtu = mtu_raw & 0xFFFF
    assert mtu == 4096, f"After write, cfg_mtu={mtu}, expected 4096"
