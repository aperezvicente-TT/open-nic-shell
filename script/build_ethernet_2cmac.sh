#!/usr/bin/env bash
# Pure-Ethernet OpenNIC shell (NO RDMA): au200, 2 CMACs, 1 PF, 2048 queues,
# 9600-byte jumbo, on Vivado 2024.2.
# Stable baseline build off branch `main` — same 2cmac/1pf topology as the
# RDMA v5.2.x builds, but with RDMA/ERNIC entirely out of the picture.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         eth_2cmac_1pf \
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
    2>&1 | tee build_eth_2cmac_1pf_full.log
