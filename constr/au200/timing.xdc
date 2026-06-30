# *************************************************************************
#
# Copyright 2020 Xilinx, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# *************************************************************************
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_p]

set_false_path -through [get_ports pcie_rstn]

# ---------------------------------------------------------------------------
# CDC max-delay constraints: axis_aclk (250 MHz) <-> cmac_clk (322 MHz)
# ---------------------------------------------------------------------------
foreach axis_aclk [get_clocks -of_object [get_nets axis_aclk*]] {
    foreach cmac_clk [get_clocks -of_object [get_nets cmac_clk*]] {
        set_max_delay -datapath_only -from $axis_aclk -to $cmac_clk 4.000
        set_max_delay -datapath_only -from $cmac_clk -to $axis_aclk 3.103
    }
}

# ---------------------------------------------------------------------------
# CDC max-delay constraints: QDMA internal clock <-> datapath/CMAC clocks
#
# clk_out1_qdma_subsystem_clk_div (125 MHz) is the QDMA AXI-Lite management
# clock.  It crosses to axis_aclk (250 MHz) and cmac_clk (322 MHz) through
# axi_lite_register CDC modules and async FIFOs.
# ---------------------------------------------------------------------------
foreach qdma_clk [get_clocks -quiet clk_out1_qdma_subsystem_clk_div] {
    foreach axis_aclk [get_clocks -of_object [get_nets axis_aclk*]] {
        set_max_delay -datapath_only -from $qdma_clk -to $axis_aclk 4.000
        set_max_delay -datapath_only -from $axis_aclk -to $qdma_clk 4.000
    }
    foreach cmac_clk [get_clocks -of_object [get_nets cmac_clk*]] {
        set_max_delay -datapath_only -from $qdma_clk -to $cmac_clk 3.103
        set_max_delay -datapath_only -from $cmac_clk -to $qdma_clk 3.103
    }
}

# ---------------------------------------------------------------------------
# PTP subsystem CDC timing constraints
# ---------------------------------------------------------------------------
# ptp_clock_cdc has three clock domains:
#   input_clk  = axis_aclk  (250 MHz)
#   output_clk = cmac_clk   (322 MHz)
#   sample_clk = axil_aclk  (125/250 MHz)
#
# Without these constraints, Vivado treats the CDC synchronizer paths as normal
# synchronous paths, causing multi-ns WNS violations.

# ASYNC_REG: co-locate synchronizer stages to prevent metastability
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_phase_sync_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_phase_sync_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_phase_sync_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sample_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sample_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sample_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/dest_sync_sample_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/dest_sync_sample_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/dest_sync_sample_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/sample_update_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/sample_update_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/sample_update_sync3_reg_reg}]

# Helpers: apply a false-path exception ONLY if the target objects exist.
# PTP CDC synchronizer FFs can be optimized/renamed at synth time, so
# get_cells/get_pins may return empty; a bare set_false_path then errors
# ("No valid object(s) found", [Vivado 12-4739]) and fails the run. The
# synchronizer FF chains + ASYNC_REG (set above with -quiet) still protect
# the crossings, so skipping the exception when cells are absent is safe.
proc fp_to_if   {objs} { if {[llength $objs]} { set_false_path -to   $objs } }
proc fp_from_if {objs} { if {[llength $objs]} { set_false_path -from $objs } }

# False paths for CDC toggle synchronizer first stages
# input_clk (axis_aclk) -> output_clk (cmac_clk)
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sync1_reg_reg}]
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_phase_sync_sync1_reg_reg}]
# input_clk (axis_aclk) -> sample_clk (axil_aclk)
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_sync_sample_sync1_reg_reg}]
# output_clk (cmac_clk) -> sample_clk (axil_aclk)
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/dest_sync_sample_sync1_reg_reg}]
# sample_clk (axil_aclk) -> output_clk (cmac_clk)
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/sample_update_sync1_reg_reg}]

# Data capture registers (protected by toggle handshake, safe to false-path)
# NOTE: Use trailing * instead of [*] — Vivado glob treats [*] as a character
# class (matching literal '*'), not as matching bus indices like [0], [1], etc.
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_ts_s_capt_reg_reg*}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_ts_ns_capt_reg_reg*}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/src_ts_step_capt_reg_reg}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_inst/sample_acc_out_reg_reg*}]

# PTP reset synchronizer: async reset crossing to cmac_clk domain
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_subsystem_inst/gen_port[*].cmac_rst_sync1_reg}]

# ---------------------------------------------------------------------------
# PTP RX CDC timing constraints (axis_aclk -> rx_serdes_clk)
#
# A second ptp_clock_cdc per port crosses from axis_aclk (250 MHz) to
# rx_serdes_clk[0] (322 MHz recovered RX clock).  Same CDC structure as
# the TX path, so the same constraint pattern applies.
# ---------------------------------------------------------------------------

# CDC max-delay: axis_aclk <-> gt_rxusrclk2 (RX SerDes clock)
# gt_rxusrclk2 is the GT recovered RX clock (= rx_serdes_clk[0] internally).
# Try both the net name and the auto-generated clock name.
foreach axis_aclk [get_clocks -of_object [get_nets axis_aclk*]] {
    foreach rx_sclk [get_clocks -quiet -of_object [get_nets -quiet -hier gt_rxusrclk2*]] {
        set_max_delay -datapath_only -from $axis_aclk -to $rx_sclk 4.000
        set_max_delay -datapath_only -from $rx_sclk -to $axis_aclk 3.103
    }
}

# ASYNC_REG for RX CDC synchronizer stages
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_phase_sync_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_phase_sync_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_phase_sync_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sample_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sample_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sample_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/dest_sync_sample_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/dest_sync_sample_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/dest_sync_sample_sync3_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/sample_update_sync1_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/sample_update_sync2_reg_reg}]
set_property -quiet ASYNC_REG TRUE [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/sample_update_sync3_reg_reg}]

# False paths for RX CDC toggle synchronizer first stages (fp_to_if/fp_from_if
# helpers defined above with the TX-side block).
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sync1_reg_reg}]
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_phase_sync_sync1_reg_reg}]
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_sync_sample_sync1_reg_reg}]
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/dest_sync_sample_sync1_reg_reg}]
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/sample_update_sync1_reg_reg}]

# Data capture registers (protected by toggle handshake)
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_ts_s_capt_reg_reg*}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_ts_ns_capt_reg_reg*}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/src_ts_step_capt_reg_reg}]
fp_from_if [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc_rx_inst/sample_acc_out_reg_reg*}]

# PTP RX reset synchronizer: async reset crossing to rx_serdes_clk domain
fp_to_if [get_cells -quiet -hier -filter {NAME =~ *ptp_subsystem_inst/gen_port[*].rx_serdes_rst_sync1_reg}]

# False-path async reset (PRE) to rx_serdes_rst synchronizer stages
# The reset crosses from QDMA 125MHz -> rxoutclk 322MHz; the synchronizer
# handles metastability, so recovery/removal checks are not meaningful.
fp_to_if [get_pins -quiet -hier -filter {NAME =~ *ptp_subsystem_inst/gen_port[*].rx_serdes_rst_sync*_reg/PRE}]

# ---------------------------------------------------------------------------
# Placement constraints for packet adapter CDC FIFOs
# ---------------------------------------------------------------------------
create_pblock pblock_packet_adapter_tx
add_cells_to_pblock [get_pblocks pblock_packet_adapter_tx] [get_cells -quiet {cmac_port*.packet_adapter_inst/tx_inst}]
resize_pblock [get_pblocks pblock_packet_adapter_tx] -add {CLOCKREGION_X0Y9:CLOCKREGION_X2Y11}

create_pblock pblock_packet_adapter_rx
add_cells_to_pblock [get_pblocks pblock_packet_adapter_rx] [get_cells -quiet {cmac_port*.packet_adapter_inst/rx_inst}]
resize_pblock [get_pblocks pblock_packet_adapter_rx] -add {CLOCKREGION_X3Y9:CLOCKREGION_X5Y11}

# ---------------------------------------------------------------------------
# Prevent SRL conversion on CDC pipeline registers — keeps them as FFs
# for better timing and prevents phys_opt from wasting time on them
# ---------------------------------------------------------------------------
set_property SHREG_EXTRACT NO [get_cells -quiet -hier -filter {NAME =~ *packet_adapter_inst/*}]
set_property SHREG_EXTRACT NO [get_cells -quiet -hier -filter {NAME =~ *ptp_clock_cdc*}]

# ---------------------------------------------------------------------------
# Note: PTP RX CDC (ptp_clock_cdc_rx_inst) and lane skew pipeline registers
# are left unconstrained — Vivado will place them near their clock sources
# (gt_rxusrclk2 / cmac_clk) automatically.  If timing fails on these paths,
# add a pblock to colocate them with the CMAC region.
# ---------------------------------------------------------------------------
