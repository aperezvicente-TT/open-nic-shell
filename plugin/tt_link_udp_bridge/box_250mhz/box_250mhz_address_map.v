// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// Stub — not instantiated by tt_link_udp_bridge.
// The AXI-Lite passthrough to tt_link_regs is done entirely via assign
// statements in box_250mhz_address_map_inst.vh (single slave, no crossbar).
// This file exists only because build.tcl unconditionally reads
// ${box_plugin}/box_250mhz_address_map.v for every plugin.
`timescale 1ns/1ps
module box_250mhz_address_map();
endmodule
