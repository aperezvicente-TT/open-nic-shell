#!/usr/bin/env bash
# Pure-Ethernet OpenNIC shell (NO RDMA), au200: 2 CMACs behind 1 PF, absolute-qid
# steering + per-port RSS combine mode, 2048 queues, 9600-byte jumbo, Vivado 2024.2.
#
# This is the canonical wrapper for the `eth_1pf_2cmac_qid` build documented in
# docs/06-build-and-flash.md §6.2.  The plugin argument is mandatory: without
# `-user_plugin ../plugin/eth_2cmac_1pf`, build.tcl falls back to plugin/p2p and you
# get a bitstream with no qid steering at all.
#
# Usage:
#   ./build_eth_1pf_2cmac_qid.sh                    # full flow through .bit + .mcs
#   ./build_eth_1pf_2cmac_qid.sh -impl_to_step route_design -post_impl 0
#                                                   # stop after routing (no bitstream)
#
# Any arguments given are appended to the build.tcl -tclargs list and therefore
# override the defaults below.
#
# NOTE ON LICENSING: write_bitstream needs a full `cmac_usplus` license.  With only
# the built-in Design_Linking entitlement, synthesis and implementation succeed but
# bitstream generation fails at the very end of a multi-hour run — use
# `-impl_to_step route_design -post_impl 0` in that case.  See docs §6.1.
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
    -board       au200 \
    -tag         eth_1pf_2cmac_qid \
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
    -num_phys_func   1 \
    -user_plugin     ../plugin/eth_2cmac_1pf \
    "$@" \
    2>&1 | tee build_eth_1pf_2cmac_qid_full.log
