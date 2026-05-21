"""
test_aw_w_same_cycle — regression for the bug class that took down the
host kernel during the UDP-bridge bring-up.

Bug history (committed in d40be7b on the bridge): tt_link_regs.sv had
AWREADY, WREADY, ARREADY hardwired to 1. An AXI-Lite master that
issues AWVALID and WVALID on the same clock (legal per AXI4 §A3.3) had
its W beat consumed before wr_pending latched the address; BVALID
never asserted; QDMA timed out; escalated as a PCIe Completer Abort
which the host kernel logged as fatal AER and rebooted.
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


@cocotb.test()
async def test_aw_w_same_cycle_completes(dut):
    """Drive AWVALID + WVALID together — must not lock up; write must commit."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    addr_scratch = 0x004
    test_val     = 0xCAFEBABE

    dut.s_axil_awaddr.value  = addr_scratch
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = test_val
    dut.s_axil_wvalid.value  = 1
    dut.s_axil_bready.value  = 1

    aw_done = False
    w_done  = False
    bvalid_seen = False
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_awready.value) == 1 and int(dut.s_axil_awvalid.value) == 1:
            aw_done = True
            dut.s_axil_awvalid.value = 0
        if int(dut.s_axil_wready.value) == 1 and int(dut.s_axil_wvalid.value) == 1:
            w_done = True
            dut.s_axil_wvalid.value = 0
        if int(dut.s_axil_bvalid.value) == 1 and int(dut.s_axil_bready.value) == 1:
            bvalid_seen = True
        if aw_done and w_done and bvalid_seen:
            break

    assert aw_done,     "AWREADY never went high — slave wedged"
    assert w_done,      "WREADY never went high — slave wedged"
    assert bvalid_seen, ("BVALID never asserted within 100 cycles — this "
                        "is the bug class that triggered PCIe Completer "
                        "Abort on real hardware.")

    rdata = await _axil_read(dut, addr_scratch)
    assert rdata == test_val, \
        f"Wrote 0x{test_val:08X}, read back 0x{rdata:08X} — wr_addr_r race."


@cocotb.test()
async def test_pipelined_writes_no_kernel_oops(dut):
    """Hammer 16 writes back-to-back — must not drop or corrupt any."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    addr_scratch = 0x004
    values = [0x10000000 | i for i in range(16)]

    for v in values:
        dut.s_axil_awaddr.value  = addr_scratch
        dut.s_axil_awvalid.value = 1
        dut.s_axil_wdata.value   = v
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
        assert aw_done and w_done and b_seen, \
            f"Pipelined write of 0x{v:08X} stuck (aw={aw_done}, w={w_done}, b={b_seen})"

    rdata = await _axil_read(dut, addr_scratch)
    assert rdata == values[-1], \
        f"After 16 pipelined writes, SCRATCH should be {values[-1]:#x}, got {rdata:#x}"
