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
set qdma qdma_no_sriov
create_ip -name qdma -vendor xilinx.com -library ip -module_name $qdma -dir ${ip_build_dir}

# ---------------------------------------------------------------------------
# Gen4 x8 (-pcie_gen4x8 1) vs. the stock Gen3 x16.
#
# The U50 edge connector brings all 16 lanes into GTY quads X1Y0..X1Y3, but a
# PCIE4C block does x16 only at Gen3: at Gen4 it caps at x8.  The two are
# therefore mutually exclusive, exactly as on the C1100 -- see
# docs/au55n-2qdma-gen4x8-design.md §3 for the same trade written out at length.
#
# Gen4 x8 = 128 Gb/s raw, the same as Gen3 x16, so the 512-bit 250 MHz user
# datapath and qdma_subsystem_clk_div (250 MHz in) are unchanged.  What changes
# is the lane budget: only edge lanes 0..7 are used, which is why the shell
# narrows pcie_rxp/txp to 8 under `__au50_gen4x8__`.
#
# Board interface rather than Custom, unlike the C1100: the au50 board file
# already defines pci_express_x8 on lanes 0..7 with block_location
# PCIE4C_X1Y0, and its pcie_refclk is PCIE_REFCLK1 = AF9/AF8, which sits in
# quad X1Y1 -- within the "refclk within 2 quads of every transceiver" rule
# ([Place 30-739]) for lanes 0..7 in quads X1Y0/X1Y1.  That is the same pin
# pair constr/au50/pins.xdc already constrains, so nothing moves.
# ---------------------------------------------------------------------------
set au50_gen4x8 [expr {[info exists pcie_gen4x8] && $pcie_gen4x8}]
if {$au50_gen4x8} {
    set au50_pcie_intf {CONFIG.PCIE_BOARD_INTERFACE {pci_express_x8}}
} else {
    set au50_pcie_intf {CONFIG.PCIE_BOARD_INTERFACE {pci_express_x16}}
}

set_property -dict "
    CONFIG.mode_selection {Advanced}
    CONFIG.pl_link_cap_max_link_width {X16}
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s}
    CONFIG.en_transceiver_status_ports {false}
    CONFIG.dsc_byp_mode {Descriptor_bypass_and_internal}
    CONFIG.testname {st}
    CONFIG.pf1_pciebar2axibar_2 {0x0000000000000000}
    CONFIG.pf2_pciebar2axibar_2 {0x0000000000000000}
    CONFIG.pf3_pciebar2axibar_2 {0x0000000000000000}
    CONFIG.dma_reset_source_sel {PCIe_User_Reset}
    CONFIG.pf0_bar2_scale_qdma {Megabytes}
    CONFIG.pf0_bar2_size_qdma {4}
    CONFIG.pf1_bar2_scale_qdma {Megabytes}
    CONFIG.pf1_bar2_size_qdma {4}
    CONFIG.pf2_bar2_scale_qdma {Megabytes}
    CONFIG.pf2_bar2_size_qdma {4}
    CONFIG.pf3_bar2_scale_qdma {Megabytes}
    CONFIG.pf3_bar2_size_qdma {4}
    CONFIG.PF0_MSIX_CAP_TABLE_SIZE_qdma {009}
    CONFIG.PF1_MSIX_CAP_TABLE_SIZE_qdma {008}
    CONFIG.PF2_MSIX_CAP_TABLE_SIZE_qdma {008}
    CONFIG.PF3_MSIX_CAP_TABLE_SIZE_qdma {008}
    CONFIG.dma_intf_sel_qdma {AXI_Stream_with_Completion}
    CONFIG.en_axi_mm_qdma {false}
    CONFIG.SYS_RST_N_BOARD_INTERFACE {pcie_perstn}
    $au50_pcie_intf
    CONFIG.xlnx_ref_board {AU50}
    CONFIG.pf0_base_class_menu_qdma {Network_controller}
    CONFIG.pf0_class_code_base_qdma {02}
    CONFIG.pf0_class_code_sub_qdma {80}
    CONFIG.pf0_sub_class_interface_menu_qdma {Other_network_controller}
    CONFIG.pf0_class_code_qdma {028000}
    CONFIG.pf1_base_class_menu_qdma {Network_controller}
    CONFIG.pf1_class_code_base_qdma {02}
    CONFIG.pf1_class_code_sub_qdma {80}
    CONFIG.pf1_sub_class_interface_menu_qdma {Other_network_controller}
    CONFIG.pf1_class_code_qdma {028000}
" [get_ips $qdma]

# ---------------------------------------------------------------------------
# Gen4 x8 geometry, written LAST.
#
# Ordering rule carried over from qdma_no_sriov_au55n.tcl, established
# empirically against this IP: anything that re-derives the link parameters
# (board interface, block placement, quad selection) silently resets the
# geometry, so a width/speed written earlier is lost without an error.  Write
# it after everything else and nothing downstream can undo it.
#
# Device IDs are deliberately not set: the IP derives them from gen+width
# (Gen3 x16 -> 903F, Gen4 x8 -> 9048) and overrides any explicit value, which
# makes the ID a free assertion -- 9048 in the .xci proves Gen4 x8 took, 9038
# means it silently fell back to Gen3 x8.  The check below reads it back.
# ---------------------------------------------------------------------------
if {$au50_gen4x8} {
    set_property -dict {
        CONFIG.pl_link_cap_max_link_width {X8}
        CONFIG.pl_link_cap_max_link_speed {16.0_GT/s}
        CONFIG.coreclk_freq {500}
        CONFIG.INS_LOSS_NYQ {5}
        CONFIG.ins_loss_profile {Add-in_Card}
        CONFIG.vsec_cap_addr {0xe00}
    } [get_ips $qdma]
}

set_property CONFIG.tl_pf_enable_reg $num_phys_func [get_ips $qdma]
set_property CONFIG.num_queues $num_queue [get_ips $qdma]

# Report what actually took.  Every parameter above can be silently dropped or
# re-derived by the IP, so print the resolved values instead of trusting the
# writes -- grep the build log for "qdma_no_sriov_au50:".
puts [format "INFO: \[qdma_no_sriov_au50\] gen4x8=%s link=%s %s intf=%s block=%s device_id=%s" \
    $au50_gen4x8 \
    [get_property CONFIG.pl_link_cap_max_link_width [get_ips $qdma]] \
    [get_property CONFIG.pl_link_cap_max_link_speed [get_ips $qdma]] \
    [get_property CONFIG.PCIE_BOARD_INTERFACE [get_ips $qdma]] \
    [get_property CONFIG.pcie_blk_locn [get_ips $qdma]] \
    [get_property CONFIG.pf0_device_id [get_ips $qdma]]]
