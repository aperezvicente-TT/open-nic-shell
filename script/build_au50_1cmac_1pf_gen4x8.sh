#!/usr/bin/env bash
# au50 / Alveo U50: 1 CMAC (the card's only QSFP28 cage) behind 1 PF, with the
# QDMA endpoint trained as Gen4 x8 instead of the stock Gen3 x16.
#
# Design document: docs/au50-1cmac-1pf-gen4x8.md -- READ IT FIRST.
#
# Same shell as the au200/au250 `eth_1pf_2cmac_qid` target (absolute-qid
# steering + per-port RSS combine mode, docs Ch. 4 and Ch. 11), with
# NUM_CMAC_PORT=1.  The plugin argument is mandatory: without
# `-user_plugin ../plugin/eth_2cmac_1pf`, build.tcl falls back to plugin/p2p and
# you get a bitstream with no qid steering at all.
#
# THIS IS A BRING-UP BUILD.  Nothing on this configuration has been run on
# hardware:
#   * the U50 Gen4 x8 endpoint has never been link-trained,
#   * the 1-CMAC elaboration of plugin/eth_2cmac_1pf has never carried traffic
#     (au200/au250 run it at NUM_INTF=2, au55n at NUM_INTF=2 pinned).
# Both are checked at build time -- see the design doc §5 for what to grep.
#
# WHY Gen4 x8 AND WHAT IT COSTS
#   A PCIE4C block does x16 only at Gen3; at Gen4 it caps at x8.  Gen4 x8 and
#   Gen3 x16 are the same 128 Gb/s raw, so the 512-bit 250 MHz datapath is
#   unchanged either way.  The trade is host-side: Gen4 x8 trains in a slot
#   that only wires 8 lanes (or is bifurcated x8x8), Gen3 x16 does not; in a
#   full x16 Gen3 slot the stock build is the better default.  Drop
#   `-pcie_gen4x8 1` below for that.
#
# Usage:
#   ./build_au50_1cmac_1pf_gen4x8.sh                    # full flow through .bit + .mcs
#   ./build_au50_1cmac_1pf_gen4x8.sh -impl_to_step route_design -post_impl 0
#                                                       # stop after routing (no bitstream)
#   ./build_au50_1cmac_1pf_gen4x8.sh -synth_ip 0 -impl 0 # IP customization + project only
#
# Any arguments given are appended to the build.tcl -tclargs list and therefore
# override the defaults below.
#
# NOTE ON -impl_strategies "": build.tcl defaults it to the bare string
# "Vivado Implementation Defaults", and _do_impl does `llength` on it -- a single
# 3-word strategy name is indistinguishable from a 3-element list, so it takes
# the strategy-sweep branch and does `set_property STRATEGY [lindex $s 0]` =
# "Vivado", which Vivado 2024.2 rejects:
#   ERROR [Common 17-69] Strategy 'Vivado' is not supported by the flow
#                        'Vivado Implementation 2024'
# Passing an empty list selects the plain single-run path with the tool default.
#
# NOTE ON LICENSING: write_bitstream needs a full cmac_usplus license.  With only
# the built-in Design_Linking entitlement, synth and impl succeed and bitstream
# generation fails at the very end of a multi-hour run -- use
# "-impl_to_step route_design -post_impl 0" in that case.  See docs §6.1.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vivado 2024.2 lives in different prefixes on different benches.
VIVADO_SETTINGS=""
for p in /opt/amd/fpga/Vivado/2024.2 /opt/amd/Vivado/2024.2 \
         /tools/Xilinx/Vivado/2024.2 /opt/Xilinx/Vivado/2024.2; do
    if [[ -f "${p}/settings64.sh" ]]; then
        VIVADO_SETTINGS="${p}/settings64.sh"
        break
    fi
done
if [[ -z "$VIVADO_SETTINGS" ]]; then
    echo "ERROR: could not find Vivado 2024.2 settings64.sh; set VIVADO_SETTINGS by hand." >&2
    exit 1
fi
echo "Sourcing ${VIVADO_SETTINGS}"
# shellcheck disable=SC1090
source "$VIVADO_SETTINGS"

JOBS="${JOBS:-16}"

vivado -mode batch -source build.tcl -tclargs \
    -board       au50 \
    -tag         eth_1pf_1cmac_gen4x8 \
    -overwrite   1 \
    -rebuild     1 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -jobs        "${JOBS}" \
    -num_queue       2048 \
    -max_pkt_len     9600 \
    -pkt_cap         16 \
    -num_cmac_port   1 \
    -num_phys_func   1 \
    -num_qdma        1 \
    -pcie_gen4x8     1 \
    -impl_strategies "" \
    -user_plugin     ../plugin/eth_2cmac_1pf \
    "$@" \
    2>&1 | tee build_au50_1cmac_1pf_gen4x8.log
