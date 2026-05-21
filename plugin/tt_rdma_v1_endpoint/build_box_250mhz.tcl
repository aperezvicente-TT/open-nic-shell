# SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Plugin build script for tt_link_udp_bridge (250 MHz box).
# Sourced by script/build.tcl after "cd $user_plugin".
# Adds all RTL sources to the active Vivado project.
#
# tt_link_framer_stub.sv is intentionally excluded — tt_link_framer.sv is used instead.

read_verilog -quiet -sv tt_link_udp_bridge_250mhz.sv
read_verilog -quiet -sv tt_link_regs.sv
read_verilog -quiet -sv tt_link_classifier.sv
read_verilog -quiet -sv tt_link_framer.sv
read_verilog -quiet -sv pkt_demux.sv
read_verilog -quiet -sv udp_encap_tx.sv
read_verilog -quiet -sv udp_decap_rx.sv
