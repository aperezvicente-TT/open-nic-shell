#!/usr/bin/env bash
# Build OpenNIC shell with tt_link_udp_bridge plugin.
# 2 CMACs (CMAC0=TT-facing, CMAC1=net-facing), 1 PF for PCIe BAR access.
# Override -board if your target is not au200 (e.g. au250, au45n).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

vivado -mode batch -source build.tcl -tclargs \
    -board          au200 \
    -tag            tt_link_bridge \
    -overwrite      0 \
    -synth_ip       1 \
    -impl           1 \
    -post_impl      1 \
    -num_cmac_port  2 \
    -num_phys_func  1 \
    -num_qdma       1 \
    -num_queue      512 \
    -max_pkt_len    9600 \
    -user_plugin    ../plugin/tt_link_udp_bridge
