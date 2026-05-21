# SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Plugin build script for tt_rdma_v1_endpoint (250 MHz box).
# Sourced by script/build.tcl after "cd $user_plugin".
# Adds all RTL sources to the active Vivado project.

read_verilog -quiet -sv cdc_sync.sv
read_verilog -quiet -sv rdma_regs.sv
read_verilog -quiet -sv rdma_rx_classifier.sv
read_verilog -quiet -sv rdma_hdr_parser.sv
read_verilog -quiet -sv rdma_rx_ring.sv
read_verilog -quiet -sv tt_rdma_v1_endpoint_250mhz.sv
