#!/usr/bin/env bash
# v5.2.7 — adds per-input packet FIFOs ahead of the cross-CMAC arbiter at
# rdma_onic_250mhz.sv:760-918 to fix dual-CMAC head-of-line blocking.
#
# Background (see project_b7_dual_cmac_block_persists_2026_05_07.md):
#   v5.2.6 fixed the classifier pipe_valid AXI-S violation but the cross-
#   CMAC arbiter still had no input buffering.  Empirical 2026-05-07: dual-
#   port simultaneous ping = 98-99% loss on BOTH ports while single-port
#   ping = 2% (cold-start ARP only).  The arbiter's `arb_locked` latch held
#   grant on a CMAC whose upstream filter momentarily idled mid-packet,
#   starving the other CMAC.
#
# Fix: insert two `axi_stream_packet_fifo` (depth 512, 512b TDATA, 112b
# TUSER {ptp_ts, src, size}) — one per CMAC RX path before the arbiter.
# Arbiter sees `tvalid` only when a complete packet is buffered, so neither
# CMAC can starve the other on intra-packet upstream gaps.  Cost ~20
# BRAM36 = 0.5% of U200's 4320 → trivial.
#
# Build artifact tag: 2cmac_rdma_v5_2_7
# Runtime: 4-8 hours Vivado time, same envelope as v5/v5.2.6.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_rdma_v5_2_7 \
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
    2>&1 | tee build_v5_2_7_full.log
