#!/usr/bin/env bash
# Full Tier 1b rebuild: ERNIC v4.2, 2 MB crossbar windows, 16 MB BAR2, QDMA bridge slave.
# NOTE: en_bridge_slv=true in QDMA IP forces single-PF (PCIe PF0 only).
#       tl_pf_enable_reg=1 disables PF1 advertisement to match.
#       Both ERNICs are reachable via PF0 BAR2 (ERNIC0@0x800000, ERNIC1@0xA00000).
# Produces bitstream + MCS for program_fpga.sh.
# Runtime: 4-8 hours Vivado time.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_1pf_rdma_v2 \
    -overwrite   1 \
    -rebuild     1 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -num_queue       2048 \
    -max_pkt_len     4096 \
    -pkt_cap         64 \
    -num_cmac_port   2 \
    -num_phys_func   1 \
    -rdma            1 \
    -classifier      rtl \
    -user_plugin     ../plugin/rdma_onic \
    2>&1 | tee build_v2_full.log
