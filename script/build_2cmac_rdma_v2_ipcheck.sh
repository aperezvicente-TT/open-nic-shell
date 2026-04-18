#!/usr/bin/env bash
# Sanity-check IP-gen for Tier 1b TCL edits (en_bridge_slv=true, bridge-slave-only).
# Uses a distinct tag (_ipcheck) to preserve the proven Tier 1a v2 build dir.
# -overwrite 1 is scoped to this new tag only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_2pf_rdma_v2_ipcheck \
    -overwrite   1 \
    -synth_ip    1 \
    -impl        0 \
    -post_impl   0 \
    -num_queue       2048 \
    -max_pkt_len     4096 \
    -pkt_cap         64 \
    -num_cmac_port   2 \
    -num_phys_func   2 \
    -rdma            1 \
    -classifier      rtl \
    -user_plugin     ../plugin/rdma_onic \
    2>&1 | tee build_v2_ipcheck.log
