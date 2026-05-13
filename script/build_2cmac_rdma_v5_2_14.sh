#!/usr/bin/env bash
# v5.2.14 — Tier-1 line-rate retransmit-buffer bump
# (project_b7_line_rate_research_2026_05_12.md).
#
# Identical to v5.2.11 (qid byte-locked in c2h slice — dual-CMAC qid-
# misroute fix) plus one IP-parameter change in
# `src/rdma_subsystem/vivado_ip/rdma_core.tcl` (commit 75ca7ad):
#
#   + CONFIG.C_S_AXI_LITE_ADDR_WIDTH      {32}
#   + CONFIG.C_MAX_WR_RETRY_DATA_BUF_DEPTH {2048}
#
# Both parameters are present in every RecoNIC base_nics/plug variant of
# this same ERNIC IP version (v4.2) but were left at Xilinx defaults
# (~512 retry-buffer depth) in our v5.2.x tcl.
#
# Steady-state perftest measurement on v5.2.11 (2026-05-12, 2.17 Gb/s
# average single-QP RDMA WRITE, -s 65536 -t 64 -D 5) decomposed the wire
# traffic via tools/perf_retx.py and found 64.7% of packets are Go-Back-N
# REWIND-style retransmits — engine moves STATCURSQPTR backward to
# replay an earlier WQE.  The retx rate climbs with pipeline depth
# (`-t 1`: 40.6%, `-t 64`: 64.7%), opposite of ACK-RTT-driven behavior
# and consistent with retry-data buffer overflow under load.
#
# Expected post-flash improvement:
#   retx 65% -> 10-20%
#   useful BW 2.2 Gb/s -> ~5-7 Gb/s
# Validation recipe: tools/ernic_diag_reset.sh both; then ib_write_bw
# -s 65536 -t 64 -D 5, with dmesg captured to /tmp/cad_client.log on
# client; then tools/perf_retx.py /tmp/cad_client.log.  retx_rate < 25%
# is the Tier-1 success bar.
#
# Build artifact tag: 2cmac_rdma_v5_2_14
# Runtime envelope: same as v5.2.11 (~3-5 hours on 16 jobs).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_rdma_v5_2_14 \
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
    2>&1 | tee build_v5_2_14_full.log
