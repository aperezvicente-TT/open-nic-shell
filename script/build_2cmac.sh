#!/usr/bin/env bash
# Build OpenNIC shell: 2 CMACs, 2 PFs (one PF per CMAC), 2048 queues, 4096-byte max packet
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_2pf \
    -overwrite   0 \
    -synth_ip    1 \
    -impl        1 \
    -post_impl   1 \
    -num_queue       2048 \
    -max_pkt_len     4096 \
    -pkt_cap         64 \
    -num_cmac_port   2 \
    -num_phys_func   2
