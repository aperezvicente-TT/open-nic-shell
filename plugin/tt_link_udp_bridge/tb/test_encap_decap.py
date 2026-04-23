"""
Cocotb testbench for udp_encap_tx + udp_decap_rx (F0 gate).

Round-trip path (tb_inject_mode=0):
  TT-link frame → encap → [UDP/IP frame] → decap → HMH+payload

Direct-inject path (tb_inject_mode=1):
  Manually crafted UDP/IP frame → decap → HMH+payload (or drop)

Test gate (F0):
  [ROUNDTRIP_1K]  1000 random-length frames, zero scoreboard mismatches
  [OVERSIZE_DROP] 1377B payload → stat_enc_oversize increments, no output
  [BAD_CKSUM]     Corrupted IP checksum → stat_dec_bad_cksum increments
  [BAD_PORT]      Wrong UDP dst port   → stat_dec_bad_port increments
  [MTU_BOUNDARY]  1376B payload (exactly at limit) passes end-to-end
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
import random
import struct

# ──────────────────────────────────────────────────────────────────────────────
# Constants — must match defaults in udp_encap_tx / decap and tb_top cfg
# ──────────────────────────────────────────────────────────────────────────────
LOCAL_MAC  = 0xAABBCCDDEE01
PEER_MAC   = 0x112233445566
LOCAL_IP   = (192 << 24) | (168 << 16) | (0 << 8) | 1     # 192.168.0.1
PEER_IP    = (192 << 24) | (168 << 16) | (0 << 8) | 2     # 192.168.0.2
UDP_PORT   = 0x1AF4
MTU        = 1500

HMH_SIZE   = 96    # HybridMeshPacketHeader bytes
ETH_HDR    = 14    # Ethernet header bytes
UDP_IP_HDR = 28    # IPv4(20) + UDP(8)
MAX_TT_PAYLOAD = MTU - UDP_IP_HDR - HMH_SIZE   # = 1376 bytes (MTU is IP payload; don't subtract ETH_HDR)

CLK_PERIOD_NS = 4   # 250 MHz


# ──────────────────────────────────────────────────────────────────────────────
# Frame builders
# ──────────────────────────────────────────────────────────────────────────────

def mac_bytes(mac_int):
    return mac_int.to_bytes(6, 'big')

def ip_bytes(ip_int):
    return ip_int.to_bytes(4, 'big')

def build_tt_frame(payload: bytes) -> bytes:
    """[Eth 14B | ethertype=0x1AF4][HMH 96B][payload]"""
    eth = mac_bytes(PEER_MAC) + mac_bytes(LOCAL_MAC) + b'\x1A\xF4'
    hmh = bytes(i & 0xFF for i in range(HMH_SIZE))   # deterministic dummy HMH
    return eth + hmh + payload

def ip_checksum(hdr20: bytes) -> int:
    """Standard one's-complement IPv4 header checksum."""
    assert len(hdr20) == 20
    s = 0
    for i in range(0, 20, 2):
        s += (hdr20[i] << 8) | hdr20[i+1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return ~s & 0xFFFF

def build_udp_frame(tt_payload: bytes, ip_id: int = 1) -> bytes:
    """Build the UDP/IP/Eth frame that encap_tx would produce for a given payload."""
    udp_payload = bytes(i & 0xFF for i in range(HMH_SIZE)) + tt_payload  # HMH + payload
    udp_len   = 8 + len(udp_payload)
    ip_len    = 20 + udp_len

    ip_hdr_no_cksum = struct.pack(
        '!BBHHHBBH4s4s',
        0x45, 0x00,                         # version/IHL, DSCP
        ip_len,                             # total length
        ip_id,                              # identification
        0x4000,                             # flags=DF, frag offset=0
        64, 17,                             # TTL, protocol=UDP
        0,                                  # checksum placeholder
        ip_bytes(LOCAL_IP),
        ip_bytes(PEER_IP),
    )
    cksum = ip_checksum(ip_hdr_no_cksum)
    ip_hdr = ip_hdr_no_cksum[:10] + struct.pack('!H', cksum) + ip_hdr_no_cksum[12:]

    udp_hdr = struct.pack('!HHHH', UDP_PORT, UDP_PORT, udp_len, 0)  # cksum=0
    eth_hdr = mac_bytes(PEER_MAC) + mac_bytes(LOCAL_MAC) + b'\x08\x00'
    return eth_hdr + ip_hdr + udp_hdr + udp_payload

def frame_to_bytes(frame: AxiStreamFrame) -> bytes:
    """Extract the data bytes from an AxiStreamFrame, respecting tkeep."""
    data = bytes(frame.tdata)
    keep = frame.tkeep
    if keep is None:
        return data
    result = bytearray()
    for i, (byte, k) in enumerate(zip(data, keep)):
        if k:
            result.append(byte)
    return bytes(result)


# ──────────────────────────────────────────────────────────────────────────────
# Test fixture
# ──────────────────────────────────────────────────────────────────────────────

async def init_dut(dut):
    """Start clock, apply reset, set config registers."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

    # Config
    dut.cfg_local_mac.value  = LOCAL_MAC
    dut.cfg_peer_mac.value   = PEER_MAC
    dut.cfg_local_ip.value   = LOCAL_IP
    dut.cfg_peer_ip.value    = PEER_IP
    dut.cfg_udp_port.value   = UDP_PORT
    dut.cfg_mtu.value        = MTU
    dut.tb_inject_mode.value = 0   # round-trip by default

    # Reset
    dut.rst_n.value = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def make_sources_sinks(dut):
    """Create cocotbext-axi BFMs."""
    enc_src = AxiStreamSource(
        AxiStreamBus.from_prefix(dut, "enc_s"),
        dut.clk, dut.rst_n, reset_active_level=False
    )
    dec_sink = AxiStreamSink(
        AxiStreamBus.from_prefix(dut, "dec_m"),
        dut.clk, dut.rst_n, reset_active_level=False
    )
    dec_src = AxiStreamSource(
        AxiStreamBus.from_prefix(dut, "dec_s"),
        dut.clk, dut.rst_n, reset_active_level=False
    )
    return enc_src, dec_sink, dec_src


async def send_tt_frame(enc_src, payload: bytes):
    """Send a TT-link frame through the encap source."""
    raw = build_tt_frame(payload)
    frame = AxiStreamFrame(raw, tuser=len(raw))
    await enc_src.send(frame)


async def recv_with_timeout(dec_sink, timeout_ns=50_000):
    """Receive one frame from decap sink, or raise on timeout."""
    return await with_timeout(dec_sink.recv(), timeout_ns, timeout_unit="ns")


# ──────────────────────────────────────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_frame17_debug(dut):
    """Send first 20 frames of the 1000-frame sequence; diagnose drop reason via stats."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    # Monitor: watch for oversize drop stat increment and dump DUT state
    async def oversize_monitor():
        prev = 0
        for _ in range(1_000_000):
            await RisingEdge(dut.clk)
            cur = dut.stat_dec_oversize.value.integer
            if cur != prev:
                # Dump the decap input bus and config at this exact cycle
                tdata = dut.stat_dec_oversize.value.integer  # already cur
                # Read key signals
                try:
                    b16 = (dut.dec_m_tdata.value.integer >> (8*16)) & 0xFFFF  # wrong - this is output
                    # Use the wires connected to decap input
                    pass
                except Exception:
                    pass
                dut._log.warning(
                    f"OVERSIZE DROP at sim {cocotb.utils.get_sim_time('ns')}ns: "
                    f"cfg_mtu={dut.cfg_mtu.value.integer} "
                    f"dec_in_tvalid={int(dut.enc_m_tvalid.value)} "
                    f"enc_m_tdata_b16_17=0x{(int(dut.enc_m_tdata.value) >> 128) & 0xFFFF:04X} "
                    f"enc_m_tuser={dut.enc_m_tuser.value.integer}"
                )
                prev = cur

    cocotb.start_soon(oversize_monitor())

    rng = random.Random(0xDEADBEEF)
    NUM = 20
    sent = []
    for _ in range(NUM):
        n = rng.randint(1, MAX_TT_PAYLOAD)
        payload = bytes(rng.getrandbits(8) for _ in range(n))
        sent.append(payload)
        await send_tt_frame(enc_src, payload)

    mismatches = 0
    drop_frame = None
    for i, payload in enumerate(sent):
        expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
        try:
            got = await recv_with_timeout(dec_sink, timeout_ns=200_000)
            got_bytes = frame_to_bytes(got)
            if got_bytes != expected:
                mismatches += 1
                if drop_frame is None:
                    drop_frame = i
                dut._log.warning(f"Frame {i}: got {len(got_bytes)}B expected {len(expected)}B")
        except Exception as e:
            dut._log.error(f"Frame {i}: timeout/error - {e}")
            mismatches += 1
            if drop_frame is None:
                drop_frame = i
            break

    # Read stat counters after all frames processed
    await Timer(10_000, "ns")
    enc_oversize  = dut.stat_enc_oversize.value.integer
    dec_bad_cksum = dut.stat_dec_bad_cksum.value.integer
    dec_bad_port  = dut.stat_dec_bad_port.value.integer
    dec_oversize  = dut.stat_dec_oversize.value.integer
    enc_out       = dut.stat_enc_frames_out.value.integer
    dec_out       = dut.stat_dec_frames_out.value.integer

    dut._log.warning(
        f"STATS: enc_out={enc_out} enc_oversize={enc_oversize} "
        f"dec_out={dec_out} dec_bad_cksum={dec_bad_cksum} "
        f"dec_bad_port={dec_bad_port} dec_oversize={dec_oversize}"
    )
    dut._log.warning(f"First bad frame: {drop_frame}, total mismatches: {mismatches}/{NUM}")

    assert mismatches == 0, f"{mismatches}/{NUM} frames bad (first: {drop_frame})"
    dut._log.info("test_frame17_debug PASS")


@cocotb.test()
async def test_basic_roundtrip(dut):
    """Single 64-byte payload frame, verify byte-exact output after round-trip."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    payload = bytes(range(64))
    await send_tt_frame(enc_src, payload)

    got = await recv_with_timeout(dec_sink)
    got_bytes = frame_to_bytes(got)

    expected = bytes(i & 0xFF for i in range(HMH_SIZE)) + payload
    assert got_bytes == expected, (
        f"Round-trip mismatch: got {len(got_bytes)} bytes, expected {len(expected)}\n"
        f"  first diff at byte {next(i for i,(a,b) in enumerate(zip(got_bytes,expected)) if a!=b)}"
        if got_bytes != expected else ""
    )
    dut._log.info("test_basic_roundtrip PASS")


@cocotb.test()
async def test_roundtrip_1000_random(dut):
    """1000 random-length frames [1..MAX_TT_PAYLOAD bytes], zero mismatches."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    rng = random.Random(0xDEADBEEF)
    NUM = 1000
    sent = []

    # Send all frames without waiting (pipeline fill)
    for _ in range(NUM):
        n = rng.randint(1, MAX_TT_PAYLOAD)
        payload = bytes(rng.getrandbits(8) for _ in range(n))
        sent.append(payload)
        await send_tt_frame(enc_src, payload)

    # Receive and verify in order
    mismatches = 0
    for i, payload in enumerate(sent):
        got = await recv_with_timeout(dec_sink)
        got_bytes = frame_to_bytes(got)
        expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
        if got_bytes != expected:
            mismatches += 1
            dut._log.error(
                f"Frame {i}: mismatch — got {len(got_bytes)}B expected {len(expected)}B"
            )

    assert mismatches == 0, f"{mismatches}/{NUM} frames mismatched"
    dut._log.info(f"test_roundtrip_1000_random PASS ({NUM} frames, 0 mismatches)")


@cocotb.test()
async def test_mtu_boundary_passes(dut):
    """1376-byte payload (exactly at MTU limit) must pass end-to-end."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    payload = bytes(i & 0xFF for i in range(MAX_TT_PAYLOAD))   # exactly 1376 bytes
    await send_tt_frame(enc_src, payload)

    got = await recv_with_timeout(dec_sink, timeout_ns=100_000)
    got_bytes = frame_to_bytes(got)
    expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
    assert got_bytes == expected, "MTU boundary frame was dropped or corrupted"

    stat = dut.stat_enc_oversize.value.integer
    assert stat == 0, f"stat_enc_oversize={stat}, expected 0"
    dut._log.info("test_mtu_boundary_passes PASS")


@cocotb.test()
async def test_oversize_drop(dut):
    """1377-byte payload (1 over MTU limit) must be dropped; no output frame."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    over_payload = bytes(MAX_TT_PAYLOAD + 1)   # 1377 bytes
    await send_tt_frame(enc_src, over_payload)

    # Then send a valid frame so we know the pipeline is flushed
    good_payload = b'\xAB' * 64
    await send_tt_frame(enc_src, good_payload)

    got = await recv_with_timeout(dec_sink, timeout_ns=100_000)
    got_bytes = frame_to_bytes(got)
    expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + good_payload
    assert got_bytes == expected, "Expected good frame after oversize drop"

    stat = dut.stat_enc_oversize.value.integer
    assert stat == 1, f"stat_enc_oversize={stat}, expected 1"
    dut._log.info("test_oversize_drop PASS")


@cocotb.test()
async def test_decap_bad_checksum(dut):
    """Inject UDP frame with one byte of IP header corrupted; decap must drop."""
    await init_dut(dut)
    _, dec_sink, dec_src = make_sources_sinks(dut)
    dut.tb_inject_mode.value = 1
    await RisingEdge(dut.clk)

    payload  = bytes(range(64))
    udp_frame = bytearray(build_udp_frame(payload))
    # Corrupt IP checksum field (bytes 24-25 of frame = IP header bytes 10-11)
    udp_frame[24] ^= 0xFF

    frame = AxiStreamFrame(bytes(udp_frame), tuser=len(udp_frame))
    await dec_src.send(frame)

    # Then inject a valid frame to confirm pipeline still works
    good_frame = AxiStreamFrame(build_udp_frame(payload), tuser=len(build_udp_frame(payload)))
    await dec_src.send(good_frame)

    got = await recv_with_timeout(dec_sink, timeout_ns=100_000)
    got_bytes = frame_to_bytes(got)
    expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
    assert got_bytes == expected, "Expected good frame after bad-checksum drop"

    stat = dut.stat_dec_bad_cksum.value.integer
    assert stat >= 1, f"stat_dec_bad_cksum={stat}, expected ≥1"
    dut._log.info("test_decap_bad_checksum PASS")


@cocotb.test()
async def test_decap_bad_port(dut):
    """Inject UDP frame with wrong dst port; decap must drop."""
    await init_dut(dut)
    _, dec_sink, dec_src = make_sources_sinks(dut)
    dut.tb_inject_mode.value = 1
    await RisingEdge(dut.clk)

    payload   = bytes(range(32))
    udp_frame = bytearray(build_udp_frame(payload))
    # UDP dst port is at frame bytes 36-37 (Eth14 + IP20 + UDP dst port at offset 2-3)
    struct.pack_into('!H', udp_frame, 36, 0xDEAD)   # wrong port

    # Recompute IP checksum (IP header bytes 14..33, checksum at bytes 24-25)
    ip_hdr_bad = bytearray(udp_frame[14:34])
    ip_hdr_bad[10] = 0; ip_hdr_bad[11] = 0
    ck = ip_checksum(bytes(ip_hdr_bad))
    struct.pack_into('!H', udp_frame, 24, ck)

    frame = AxiStreamFrame(bytes(udp_frame), tuser=len(udp_frame))
    await dec_src.send(frame)

    good_frame_data = build_udp_frame(payload)
    good = AxiStreamFrame(good_frame_data, tuser=len(good_frame_data))
    await dec_src.send(good)

    got = await recv_with_timeout(dec_sink, timeout_ns=100_000)
    got_bytes = frame_to_bytes(got)
    expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
    assert got_bytes == expected, "Expected good frame after bad-port drop"

    stat = dut.stat_dec_bad_port.value.integer
    assert stat >= 1, f"stat_dec_bad_port={stat}, expected ≥1"
    dut._log.info("test_decap_bad_port PASS")


@cocotb.test()
async def test_back_pressure(dut):
    """Downstream stalls (dec_m_tready=0) mid-burst; no frames lost or corrupted."""
    await init_dut(dut)
    enc_src, dec_sink, _ = make_sources_sinks(dut)

    # Pause the output sink before sending so frames queue up in enc_src.
    # cocotbext-axi 0.1.x: pause is a bool property, not a method
    dec_sink.pause = True

    NUM = 32
    rng = random.Random(0xCAFE)
    sent = []
    for _ in range(NUM):
        n = rng.randint(64, 512)
        payload = bytes(rng.getrandbits(8) for _ in range(n))
        sent.append(payload)
        await send_tt_frame(enc_src, payload)

    # Release the sink BEFORE waiting for the source to drain: with the output
    # stalled the DUT holds back input (enc_out_tready=0), so enc_src's queue
    # can only empty after the output path is unblocked.
    dec_sink.pause = False

    # Now wait for enc_src to finish pushing all beats into the DUT
    await enc_src.wait()

    mismatches = 0
    for i, payload in enumerate(sent):
        got = await recv_with_timeout(dec_sink, timeout_ns=500_000)
        got_bytes = frame_to_bytes(got)
        expected = bytes(j & 0xFF for j in range(HMH_SIZE)) + payload
        if got_bytes != expected:
            mismatches += 1

    assert mismatches == 0, f"{mismatches}/{NUM} frames corrupted under backpressure"
    dut._log.info("test_back_pressure PASS")
