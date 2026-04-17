#!/usr/bin/env bash
# Full Tier 1a rebuild: ERNIC v4.2 w/ 2 MB crossbar windows + 16 MB BAR2.
# Produces bitstream + MCS for program_fpga.sh.
# Runtime: 4-8 hours Vivado time.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_2pf_rdma_v2 \
    -overwrite   0 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -num_queue       2048 \
    -max_pkt_len     4096 \
    -pkt_cap         64 \
    -num_cmac_port   2 \
    -num_phys_func   2 \
    -rdma            1 \
    -classifier      rtl \
    -user_plugin     ../plugin/rdma_onic \
    2>&1 | tee build_v2_full.log
