#!/usr/bin/env bash
# v5.2.10 — root-cause fix for the dual-CMAC qid-misroute bug
# (project_b7_dual_cmac_qid_misroute_2026_05_08_pm.md).
#
# v5.2.9 attempt (qid bound to plugin per-input FIFO TUSER) was insufficient
# because the bug is downstream of the plugin output mux: empirical evidence
# from `tools/diag_dump.sh` + driver-side rx_redirect counters showed:
#   * Plugin: RX*_arb_in == RX*_qdma_c2h, RX_MARK_MISMATCH=0 (byte-perfect)
#   * Driver: 8-14% of RX SKBs land at the wrong netdev (matched-by-dst-MAC)
# So the qid is being lost between m_axis_qdma_c2h_tuser_qid (plugin out)
# and the QDMA IP queue dispatch — i.e. inside qdma_subsystem_function.sv's
# qid_fifo capture-on-first-beat / read-on-output-tlast pipeline.
#
# RTL change (qdma_subsystem_function.sv):
#   * c2h_slice TUSER widened 96 → 107 bits; qid packed alongside ptp_ts/size.
#   * buf_fifo TUSER widened 16 → 27 bits; qid rides through with size.
#   * For EXT_QID=1 (RDMA path), qid_fifo is no longer instantiated; qid
#     emerges from buf_fifo TUSER, byte-locked to its data beat.
#   * For EXT_QID=0 (RSS path), qid_fifo logic preserved verbatim.
#
# Datapath unchanged otherwise.  buf_fifo BRAM read width grows by 11 bits;
# slice flop width grows by 11 bits.  Watch impl reports for 250 MHz timing.
#
# Build artifact tag: 2cmac_rdma_v5_2_11
# Runtime envelope: same as v5.2.9 (~3-5 hours on 16 jobs).
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_rdma_v5_2_11 \
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
    2>&1 | tee build_v5_2_11_full.log
