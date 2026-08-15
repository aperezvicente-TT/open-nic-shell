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

# Bifurcated x8x8 (-num_qdma 2): detach from the board interfaces HERE, before
# the main dict below, exactly as qdma_no_sriov_1_au55n.tcl does.
#
# Order is load-bearing and was established empirically: detaching *after* the
# main dict leaves pcie_blk_locn a disabled parameter, so the placement write is
# dropped with only [IP_Flow 19-3374] and the endpoint silently keeps the
# default PCIE4C_X1Y0 -- which collides with endpoint B.
#
# $au55n_board_intf below keeps the board-interface entries in the main dict for
# the 1-QDMA build, so that path stays byte-for-byte unchanged.
if {$num_qdma == 2} {
    set au55n_board_intf ""
    set_property -dict {
        CONFIG.SYS_RST_N_BOARD_INTERFACE {Custom}
        CONFIG.PCIE_BOARD_INTERFACE {Custom}
    } [get_ips $qdma]
} else {
    set au55n_board_intf {CONFIG.SYS_RST_N_BOARD_INTERFACE {pcie_perstn}
    CONFIG.PCIE_BOARD_INTERFACE {pci_express_x16}}
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
    $au55n_board_intf
    CONFIG.xlnx_ref_board {AU55N}
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
# Bifurcated x8x8 build (-num_qdma 2): this instance becomes endpoint A and
# takes edge lanes 0..7 at Gen4 x8 instead of all 16 at Gen3.
#
# PCIE4C supports x16 at Gen3 but only x8 at Gen4, so the two are mutually
# exclusive -- see docs/au55n-2qdma-gen4x8-design.md.
#
# Guarded so the single-QDMA au55n target is bit-for-bit unchanged: with
# -num_qdma 1 the dict above stands as-is (Gen3 x16, pci_express_x16).
# Endpoint B is qdma_no_sriov_1_au55n.tcl.
# ---------------------------------------------------------------------------
if {$num_qdma == 2} {
    # Endpoint A cannot use the board-interface automation here.
    #
    # The au55n board file's pcie_refclk interface maps to PCIE_REFCLK1
    # (AR15/AR14), so PCIE_BOARD_INTERFACE {pci_express_x8} would claim AR15 for
    # THIS endpoint. But AR15 is in bank 225 = quad X1Y1, and endpoint B (edge
    # lanes 8..15 = quads X1Y1, X1Y0) is the only one that can legally use it:
    # the other pair, AL15 (bank 227 = quad X1Y3), is 3 quads from endpoint B's
    # X1Y0 lanes and fails the "refclk within 2 quads of all txvrs" rule
    # ([Place 30-739]).  Two ports also cannot share one PACKAGE_PIN.
    #
    # So the split is forced: endpoint B takes AR15/AR14, endpoint A takes
    # AL15/AL14 (quad X1Y3, distances 0 and 1 to its own X1Y3/X1Y2 lanes).
    # Going Custom is the price of that, and it means all of this endpoint's
    # lane pins are constrained by hand in constr/au55n/pins.xdc rather than
    # inherited from the board file.
    #
    # Resolved against the real device -- see qdma_no_sriov_1_au55n.tcl for the
    # full quad map and docs/au55n-2qdma-gen4x8-design.md §3.
    #
    # ORDERING RULES, all established empirically against this IP.  Getting any
    # of them wrong produces a clean, error-free build with the WRONG config:
    #
    #  a) The board-interface detach must happen before the main dict above --
    #     done at the top of this file.  After it, pcie_blk_locn is a disabled
    #     parameter and the write is dropped with only [IP_Flow 19-3374],
    #     leaving the default PCIE4C_X1Y0 (a collision with endpoint B).
    #  b) Placement must be written BEFORE the link geometry: writing
    #     select_quad / pcie_blk_locn re-derives the link parameters, so
    #     geometry written first is silently reset to X16 / 8.0_GT/s.  A clean
    #     run produced Gen3 endpoints exactly that way.
    #  c) Never touch CONFIG.xlnx_ref_board -- with BOARD_PART set to au55n its
    #     only legal value is AU55N:
    #       ERROR [IP_Flow 19-3461] Value 'None' is out of the range for
    #       parameter 'Xlnx Ref Board(xlnx_ref_board)'
    #
    # 1. placement (before geometry, per rule b)
    set_property -dict {
        CONFIG.en_gt_selection {true}
        CONFIG.pcie_blk_locn {PCIE4C_X1Y1}
        CONFIG.select_quad {GTY_Quad_227}
    } [get_ips $qdma]

    # 3. geometry LAST, so nothing downstream can re-derive it away.
    #
    #    Device IDs are deliberately not set: the IP derives them from gen+width
    #    (Gen3 x16 -> 903F, Gen3 x8 -> 9038, Gen4 x8 -> 9048) and overrides any
    #    explicit value.  That makes the ID a free assertion -- 9048 in the .xci
    #    proves Gen4 x8 took, 9038 means it silently fell back to Gen3.
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
