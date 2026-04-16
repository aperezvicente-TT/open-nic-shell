#!/usr/bin/env bash
# Build OpenNIC shell for BittWare XUP-VV8 (VU13P):
#   2 CMACs on QSFP-DD port 3 (SLR=1), 2 PFs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

vivado -mode batch -source build.tcl -tclargs \
    -board         xup_vv8 \
    -tag           2cmac_2pf \
    -num_cmac_port 2 \
    -num_phys_func 2 \
    -impl          1 \
    -post_impl     1
