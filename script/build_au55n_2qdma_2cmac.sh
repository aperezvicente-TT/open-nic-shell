#!/usr/bin/env bash
# au55n / Varium C1100: 2 CMAC + 2 QDMA, each QDMA at Gen4 x8 (bifurcated x8x8 slot).
#
# Design document: docs/au55n-2qdma-gen4x8-design.md  -- READ IT FIRST.
#
# THIS IS A BRING-UP BUILD, NOT A PRODUCTION ONE. Two things are unfinished:
#
#   1. No top-level synthesis has ever been run on this configuration. The IP
#      customization is verified against the real device, and every RTL module
#      touched elaborates cleanly for both NUM_QDMA=1 and NUM_QDMA=2, but the
#      full design has not been synthesized, placed or routed.
#
#   2. Nothing here has been simulated. No traffic has ever moved through this
#      datapath -- in particular the repaired QDMA_ID!=0 qid path and the 1:1
#      pinned plugin mode are both unexercised.
#
# Plugin: plugin/eth_2cmac_1pf, which now supports NUM_QDMA=2 in 1:1 pinned
# mode (QDMA endpoint c <-> CMAC c, no qid demux, no C2H arbiter).  The plugin
# prints which mode it elaborated in -- grep the synthesis log for
# "eth_2cmac_1pf_250mhz: 1:1 PINNED mode" to confirm.
#
# Usage:
#   ./build_au55n_2qdma_2cmac.sh
#   ./build_au55n_2qdma_2cmac.sh -impl_to_step route_design -post_impl 0   # no bitstream
#
# Any arguments are appended to the build.tcl -tclargs list and override the
# defaults below.
#
# NOTE ON -impl_strategies "": build.tcl defaults it to the bare string
# "Vivado Implementation Defaults", and _do_impl does `llength` on it -- a single
# 3-word strategy name is indistinguishable from a 3-element list, so it takes
# the strategy-sweep branch and does `set_property STRATEGY [lindex $s 0]` =
# "Vivado", which Vivado 2024.2 rejects:
#   ERROR [Common 17-69] Strategy 'Vivado' is not supported by the flow
#                        'Vivado Implementation 2024'
# Passing an empty list selects the plain single-run path with the tool default.
# Fixed here rather than in build.tcl so the au200/au250 targets are untouched.
#
# NOTE ON LICENSING: write_bitstream needs a full cmac_usplus license. With only
# Design_Linking, synth and impl succeed and bitstream generation fails at the
# very end -- use "-impl_to_step route_design -post_impl 0".
#
# NOTE ON POWER: constr/au55n/general.xdc sets -design_power_budget 100, a value
# inherited from the 150 W U55C. The C1100 is a 75 W passively cooled card and
# this is its highest-power configuration. See ../../U55N/u55n_full.xdc §6.
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
    -board       au55n \
    -tag         2qdma_2cmac_gen4x8 \
    -overwrite   1 \
    -rebuild     1 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -jobs        "${JOBS}" \
    -num_queue       2048 \
    -max_pkt_len     9600 \
    -pkt_cap         16 \
    -num_cmac_port   2 \
    -num_qdma        2 \
    -num_phys_func   1 \
    -impl_strategies "" \
    -user_plugin     ../plugin/eth_2cmac_1pf \
    "$@" \
    2>&1 | tee build_au55n_2qdma_2cmac.log
