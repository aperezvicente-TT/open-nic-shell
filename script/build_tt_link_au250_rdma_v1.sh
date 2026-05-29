#!/usr/bin/env bash
# Build OpenNIC shell with the tt_rdma_v1_endpoint plugin for Alveo U250.
# 2 CMACs (CMAC0=TT-facing partner; CMAC1 unused — endpoint is single-port).
# 1 PF for PCIe BAR access.  QDMA C2H ST queue carries SEND/SEND_IMM ring
# slots into host RAM; -ext_qid 1 makes the QDMA subsystem consume the
# plugin-driven m_axis_qdma_c2h_tuser_qid (lands every slot at qid 0)
# instead of computing qid internally via RSS.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board          au250 \
    -tag            tt_rdma_v1_endpoint \
    -overwrite      1 \
    -rebuild        1 \
    -synth_ip       1 \
    -impl           1 \
    -post_impl      1 \
    -num_cmac_port  2 \
    -num_phys_func  1 \
    -num_qdma       1 \
    -num_queue      2048 \
    -max_pkt_len    4096 \
    -pkt_cap        4 \
    -user_plugin    ../plugin/tt_rdma_v1_endpoint \
    -ext_qid        1 \
    2>&1 | tee build_tt_link_au250_rdma_v1.log
