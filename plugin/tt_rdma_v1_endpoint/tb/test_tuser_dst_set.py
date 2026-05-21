"""
test_tuser_dst_set — regression for the silent-drop bug class.

Bug history (committed in d40be7b on the bridge): the encap output
drove m_axis_adap_tx_250mhz_* but never set tuser_dst.  The shell's
packet_adapter_tx.sv:116 unconditionally drops any frame whose
tuser_dst is missing bit (CMAC_ID + 6), and provides zero error
indication — the frame just vanishes.  Bridge encap counters showed
80 frames "emitted" while CMAC1 TX wire count stayed at 0.

This test:
  - In the cocotb DUT (tb_top → tt_rdma_v1_endpoint_250mhz alone),
    the plugin doesn't drive tuser_dst (the box harness does — see
    user_plugin_250mhz_inst.vh).  We exercise the lesson in two ways:

  1. Confirm the box harness file contains the tuser_dst assignments.
     This is a *static* check: we read the source and assert the
     constants.  A future engineer who removes those lines will fail
     this test long before silicon.

  2. (For P0+) once we drive m_axis_cmac0_tx_tvalid from the endpoint,
     extend this test to check tuser_dst is observable at the box
     output.  Stubbed until the TX path is built.

The static check costs ~1 ms and catches removal of the lesson.
"""

import cocotb
from cocotb.triggers import Timer
import os, re


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
USER_PLUGIN_INC = os.path.join(
    REPO_ROOT, "plugin", "tt_rdma_v1_endpoint", "box_250mhz",
    "user_plugin_250mhz_inst.vh"
)
PACKET_ADAPTER_TX = os.path.join(
    REPO_ROOT, "src", "packet_adapter", "packet_adapter_tx.sv"
)


@cocotb.test()
async def test_tuser_dst_cmac0_bit_set_in_box_harness(dut):
    """user_plugin_250mhz_inst.vh must drive tuser_dst[15:0] = 0x0040 (CMAC0 bit 6)."""
    await Timer(1, units="ns")  # keep cocotb happy

    with open(USER_PLUGIN_INC, "r") as f:
        text = f.read()

    # Look for the explicit constant assignment.  The bridge bug was a
    # missing assignment; the regression is "did somebody remove this
    # line".  Be tolerant of whitespace/comment changes.
    cmac0_pat = re.compile(
        r"m_axis_adap_tx_250mhz_tuser_dst\s*\[\s*15\s*:\s*0\s*\]\s*=\s*16'h0040"
    )
    assert cmac0_pat.search(text), (
        "user_plugin_250mhz_inst.vh no longer hard-sets "
        "m_axis_adap_tx_250mhz_tuser_dst[15:0] = 16'h0040 for CMAC0.  "
        "packet_adapter_tx.sv:116 will silently drop every endpoint TX "
        "frame.  See d40be7b (bridge fix).  Re-add the line."
    )


@cocotb.test()
async def test_tuser_dst_cmac1_bit_set_in_box_harness(dut):
    """user_plugin_250mhz_inst.vh must drive tuser_dst[31:16] = 0x0080 (CMAC1 bit 7)."""
    await Timer(1, units="ns")

    with open(USER_PLUGIN_INC, "r") as f:
        text = f.read()

    cmac1_pat = re.compile(
        r"m_axis_adap_tx_250mhz_tuser_dst\s*\[\s*31\s*:\s*16\s*\]\s*=\s*16'h0080"
    )
    assert cmac1_pat.search(text), (
        "user_plugin_250mhz_inst.vh no longer hard-sets "
        "m_axis_adap_tx_250mhz_tuser_dst[31:16] = 16'h0080 for CMAC1.  "
        "Even though CMAC1 is unused in v1, keep the bit set so a "
        "future expansion can't accidentally regress."
    )


@cocotb.test()
async def test_packet_adapter_tx_filter_unchanged(dut):
    """packet_adapter_tx.sv:116 hasn't been refactored from under us."""
    await Timer(1, units="ns")

    with open(PACKET_ADAPTER_TX, "r") as f:
        text = f.read()

    # If this assertion changes shape, the lesson's wording needs revising —
    # but more importantly: anything that removes or weakens the filter is a
    # cross-cutting change that should ping the plugin authors.
    pat = re.compile(
        r"assign\s+bad_dst\s*=\s*\(\(axis_tx_tuser_dst\s*&\s*\(16'h1\s*<<\s*\(CMAC_ID\s*\+\s*6\)\)\)\s*==\s*0\)"
    )
    assert pat.search(text), (
        "packet_adapter_tx.sv no longer matches the documented bad_dst "
        "filter at line 116.  The lesson behind this test, and the "
        "tuser_dst constants in user_plugin_250mhz_inst.vh, may need "
        "to change in step with the shell.  Re-verify before bypassing."
    )
