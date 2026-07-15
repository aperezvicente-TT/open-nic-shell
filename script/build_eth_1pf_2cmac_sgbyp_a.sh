#!/usr/bin/env bash
# SG-TX Phase A: pure-Ethernet 1PF/2CMAC + H2C descriptor-bypass passthrough
# (qdma_subsystem_h2c_byp). Identical to build_eth_1pf_2cmac_qid.sh except for a
# distinct -tag so the known-good eth_1pf_2cmac_qid build dir is preserved.
# NETIF_F_SG stays OFF on the driver side; this build only proves the bypass
# datapath carries linear TX unchanged (Phase A gate). au200, Vivado 2024.2.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         eth_1pf_2cmac_sgbyp_a \
    -overwrite   0 \
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
    2>&1 | tee build_eth_1pf_2cmac_sgbyp_a_full.log
