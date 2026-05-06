#!/usr/bin/env bash
# Dual-CMAC single-PF RDMA build — v5 (axibar_notranslate=true to test address-translation theory).
#
# Architecture:
#   - ONE PCIe PF visible to host (PF0).  QDMA IP forced into bridge-slave
#     mode (en_bridge_slv=true) with tl_pf_enable_reg=1 hiding PF1 from PCIe.
#   - ONE shell function slot (-num_phys_func 1).  The RDMA plugin
#     arbitrates CMAC0+CMAC1 non-RoCE RX into a single C2H stream and
#     encodes CMAC identity into the queue ID: CMAC0 → queues [0, N),
#     CMAC1 → queues [N, 2N).  Scales to N CMACs without hitting QDMA IP
#     function-context limits.  See agent/reconic_integration/dual_netdev_plan.md
#     for why shell slots ≠ CMAC count.
#   - TWO CMAC ports (-num_cmac_port 2) → two netdevs from a single
#     onic.ko probe (primary + secondary sharing MSI-X and QDMA).  Future
#     scaling to 4/8 ports needs no shell-side parameter change.
#   - ERNIC v4.2 dual instance, 2 MB crossbar windows, 16 MB BAR2.
#     ERNIC0 @ 0x800000, ERNIC1 @ 0xA00000.
#   - RDMA (RoCEv2) traffic is orthogonal — ERNIC has its own DMA to DDR4
#     + host, bypassing QDMA queues entirely.  Future ib_device in onic.ko
#     programs ERNIC via BAR2 registers and doesn't touch the queue split.
#
# Why v3 supersedes v2:
#   v2 was built with the wrong shell parameter (-num_phys_func 1) AND no
#   plugin arbiter, so CMAC1 packets routed to m_axis_qdma_c2h_*[1] were
#   silently dropped (nothing consumes that port with num_phys_func=1).
#   v3 keeps num_phys_func=1 but pairs it with the plugin RTL arbiter so
#   CMAC1 packets correctly reach slot 0 with a CMAC-encoded qid.
#
# Produces bitstream + MCS for program_fpga.sh.
# Runtime: 4-8 hours Vivado time.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source /opt/amd/Vivado/2024.2/settings64.sh

vivado -mode batch -source build.tcl -tclargs \
    -board       au200 \
    -tag         2cmac_rdma_v5_2_6 \
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
    2>&1 | tee build_v5_full.log
