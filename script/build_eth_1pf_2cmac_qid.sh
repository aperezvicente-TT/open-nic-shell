#!/usr/bin/env bash
# Pure-Ethernet OpenNIC, single PF / 2 CMAC via qid steering (NO RDMA).
# au200, Vivado 2024.2. Uses the eth_2cmac_1pf plugin + the EXT_QID qid graft.
# EXT_QID=1 is hardcoded on the qdma_subsystem instance in open_nic_shell.sv,
# so no extra build flag is needed.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         eth_1pf_2cmac_qid \
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
    -user_plugin     ../plugin/eth_2cmac_1pf \
    2>&1 | tee build_eth_1pf_2cmac_qid_full.log
