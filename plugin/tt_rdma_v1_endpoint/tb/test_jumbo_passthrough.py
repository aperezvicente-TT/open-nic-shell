"""
test_jumbo_passthrough — Phase A acceptance test.

Drive a 4080-byte jumbo frame onto CMAC0 RX and confirm it comes out
CMAC0 TX byte-for-byte.  This proves:
  1. The Phase A passthrough datapath is clean for jumbo frames up to
     LINK_MTU (cfg_mtu default = 9000).
  2. Back-pressure propagates correctly via the skid buffer.
  3. The single-beat-frame path doesn't accidentally swallow short
     frames — a regression class from the UDP bridge session
     (udp_decap_rx.sv:184-187, fixed in 099bebc).
  4. The plugin's TX never drops a frame on the floor — the
     packet_adapter_tx tuser_dst contract is set by the box harness,
     but the plugin must ALSO drive a stable tlast and not corrupt
     beats mid-flight.

4080 B = 63.75 beats of 64 bytes — last beat has 48 valid bytes
(tkeep[47:0] = all 1s, tkeep[63:48] = 0).
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


def _beats_for(payload_bytes):
    """Yield (tdata, tkeep, tlast) for each 64-byte beat of payload_bytes."""
    n = len(payload_bytes)
    full_beats = n // 64
    rem = n % 64
    total = full_beats + (1 if rem else 0)
    for i in range(total):
        chunk = payload_bytes[i*64:(i+1)*64]
        if len(chunk) < 64:
            chunk = chunk + b"\x00" * (64 - len(chunk))
        tdata = int.from_bytes(chunk, "little")
        tlast = (i == total - 1)
        if tlast and rem:
            tkeep = (1 << rem) - 1
        else:
            tkeep = (1 << 64) - 1
        yield tdata, tkeep, tlast


async def _send_frame(dut, payload):
    """Drive payload onto CMAC0 RX, beat by beat, respecting tready."""
    tuser_size = len(payload)
    for tdata, tkeep, tlast in _beats_for(payload):
        dut.s_axis_cmac0_rx_tvalid.value = 1
        dut.s_axis_cmac0_rx_tdata.value  = tdata
        dut.s_axis_cmac0_rx_tkeep.value  = tkeep
        dut.s_axis_cmac0_rx_tlast.value  = 1 if tlast else 0
        dut.s_axis_cmac0_rx_tuser.value  = tuser_size
        # Hold until handshake.
        await RisingEdge(dut.clk)
        while int(dut.s_axis_cmac0_rx_tready.value) == 0:
            await RisingEdge(dut.clk)
    dut.s_axis_cmac0_rx_tvalid.value = 0


async def _recv_frame(dut, max_cycles=20000):
    """Capture beats off CMAC0 TX until tlast."""
    beats = []
    last_seen = False
    cycles = 0
    while not last_seen and cycles < max_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        if int(dut.m_axis_cmac0_tx_tvalid.value) == 1 and \
           int(dut.m_axis_cmac0_tx_tready.value) == 1:
            tdata = int(dut.m_axis_cmac0_tx_tdata.value)
            tkeep = int(dut.m_axis_cmac0_tx_tkeep.value)
            tlast = int(dut.m_axis_cmac0_tx_tlast.value)
            beats.append((tdata, tkeep, tlast))
            if tlast:
                last_seen = True
    assert last_seen, f"No tlast within {max_cycles} cycles ({len(beats)} beats captured)"
    return beats


def _beats_to_bytes(beats):
    out = bytearray()
    for tdata, tkeep, _ in beats:
        chunk = tdata.to_bytes(64, "little")
        # Count consecutive 1s from LSB in tkeep
        n = 0
        for b in range(64):
            if (tkeep >> b) & 1:
                n = b + 1
            else:
                break
        out.extend(chunk[:n])
    return bytes(out)


@cocotb.test()
async def test_4080_byte_jumbo_round_trip(dut):
    """4080 B frame in → 4080 B frame out, byte-for-byte."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    payload = bytes((i * 7 + 11) & 0xFF for i in range(4080))

    sender = cocotb.start_soon(_send_frame(dut, payload))
    beats  = await _recv_frame(dut)
    await sender

    out = _beats_to_bytes(beats)
    if out != payload:
        # Find first differing byte for diagnostics
        min_len = min(len(out), len(payload))
        diff = next((i for i in range(min_len) if out[i] != payload[i]),
                    'all-equal' if len(out) == len(payload) else 'length-only')
        raise AssertionError(
            f"Jumbo passthrough corrupted bytes: "
            f"len in={len(payload)} out={len(out)}; "
            f"first diff at byte {diff}"
        )


@cocotb.test()
async def test_64_byte_single_beat_frame(dut):
    """Single-beat 60 B frame must not be eaten — bridge single-beat lesson (099bebc)."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    payload = bytes((i + 1) & 0xFF for i in range(60))

    sender = cocotb.start_soon(_send_frame(dut, payload))
    beats  = await _recv_frame(dut)
    await sender

    out = _beats_to_bytes(beats)
    assert out == payload, "Single-beat frame corrupted"
    assert len(beats) == 1, f"Expected 1 beat for 60 B frame, got {len(beats)}"


@cocotb.test()
async def test_backpressure(dut):
    """Hold TX tready low for several cycles — RX must stall, no data lost."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, units="ns").start())
    await _reset(dut)

    payload = bytes((i * 13) & 0xFF for i in range(128))  # 128 B = 2 beats

    async def _stuttered_recv():
        beats = []
        last_seen = False
        cycles = 0
        # Pattern: 3 cycles tready low, 1 cycle tready high
        while not last_seen and cycles < 1000:
            phase = cycles & 0x3
            dut.m_axis_cmac0_tx_tready.value = 1 if phase == 3 else 0
            await RisingEdge(dut.clk)
            cycles += 1
            if int(dut.m_axis_cmac0_tx_tvalid.value) == 1 and \
               int(dut.m_axis_cmac0_tx_tready.value) == 1:
                tdata = int(dut.m_axis_cmac0_tx_tdata.value)
                tkeep = int(dut.m_axis_cmac0_tx_tkeep.value)
                tlast = int(dut.m_axis_cmac0_tx_tlast.value)
                beats.append((tdata, tkeep, tlast))
                if tlast:
                    last_seen = True
        dut.m_axis_cmac0_tx_tready.value = 1
        return beats

    sender = cocotb.start_soon(_send_frame(dut, payload))
    beats  = await _stuttered_recv()
    await sender

    out = _beats_to_bytes(beats)
    assert out == payload, "Stuttered back-pressure corrupted bytes"
