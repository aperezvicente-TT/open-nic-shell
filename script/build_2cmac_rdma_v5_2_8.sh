#!/usr/bin/env bash
# v5.2.8 — adds the rdma_onic plugin's diagnostic CSR (rdma_diag_csr) on
# top of v5.2.7.  Goal: bisect the post-v5.2.7 cross-CMAC RX symptom
# (dual-port simultaneous ping still drops 98-99 % despite the per-input
# arbiter FIFOs landed in v5.2.7; ARP tables on both hosts end up cross-
# tagged with peer's other-CMAC MAC).  See
# project_b7_dual_cmac_block_persists_2026_05_07.md for the validation
# evidence and the bisect rule.
#
# Datapath is unchanged versus v5.2.7 — this build replaces a 16-bit
# placeholder AXI-Lite slave at the plugin's reg endpoint with the new
# rdma_diag_csr (16 hop counters at offsets 0x00-0x3C plus two trip-wire
# counters at 0x40/0x44).  Counters are read-only via BAR2+0x401000 by
# the host using `tools/diag_dump.sh`.
#
# Build artifact tag: 2cmac_rdma_v5_2_8
# Runtime envelope: same as v5.2.7 (4-8 hours).  No additional BRAM
# beyond v5.2.7's two arbiter-input FIFOs; 18×32-bit counters live in
# distributed RAM.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_rdma_v5_2_8 \
    -overwrite   1 \
    -rebuild     1 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -jobs        16 \
    -num_queue       2048 \
    -max_pkt_len     9600 \
    -pkt_cap         16 \
    -num_cmac_port   2 \
    -num_phys_func   1 \
    -rdma            1 \
    -classifier      rtl \
    -user_plugin     ../plugin/rdma_onic \
    2>&1 | tee build_v5_2_8_full.log
