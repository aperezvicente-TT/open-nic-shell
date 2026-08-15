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
# au55n / Varium C1100 -- SECOND QDMA endpoint (QDMA_ID == 1).
#
# Endpoint B of a bifurcated x8x8 slot: edge lanes 8..15, Gen4 x8.
# Only instantiated when -num_qdma 2 (see vivado_ip.tcl).
#
# Unlike endpoint A (qdma_no_sriov_au55n.tcl), there is NO board interface for
# lanes 8..15 in the AMD au55n board file -- every width preset there maps to
# PCIE4C_X1Y1 on lanes 0..7. So this instance places its own hard block and
# quad, and its lane pins are constrained by hand in constr/au55n/pins.xdc.
# This follows the au45n second-endpoint pattern.
#
# See docs/au55n-2qdma-gen4x8-design.md for the full design.  The hard block and
# quad below are resolved against the real device, not guessed.
# *************************************************************************
set qdma_1 qdma_no_sriov_1
create_ip -name qdma -vendor xilinx.com -library ip -module_name $qdma_1 -dir ${ip_build_dir}

# ---------------------------------------------------------------------------
# Hard block and quad -- RESOLVED against xcu55n-fsvh2892-2L-e in Vivado 2024.2
# (link_design on an empty netlist, then get_sites / get_package_pins).
#
# Device inventory:
#   PCIE4CE4_X0Y0  clkrgn X0Y0     PCIE4CE4_X1Y0  clkrgn X7Y0
#   PCIE4CE4_X0Y1  clkrgn X0Y3     PCIE4CE4_X1Y1  clkrgn X7Y3
#   PCIE40E4_X0Y0  clkrgn X7Y4  (PCIE40 = Gen3 only, not usable here)
#
# Edge-lane -> quad map (X1 column, right side of the die):
#   lanes  0..3   bank 227  quad X1Y3  ch X1Y12..15   clkrgn X7Y3
#   lanes  4..7   bank 226  quad X1Y2  ch X1Y8..11    clkrgn X7Y2
#   lanes  8..11  bank 225  quad X1Y1  ch X1Y4..7     clkrgn X7Y1
#   lanes 12..15  bank 224  quad X1Y0  ch X1Y0..3     clkrgn X7Y0
#
# This endpoint owns lanes 8..15 = quads X1Y1 and X1Y0, so it takes
# PCIE4CE4_X1Y0 (clkrgn X7Y0, adjacent to quad X1Y0). Endpoint A keeps
# PCIE4C_X1Y1 (clkrgn X7Y3, adjacent to quad X1Y3).
#
# Reference clock -- the choice is FORCED, not preferential:
#   AR15/AR14 (PCIE_REFCLK1) -> bank 225 = quad X1Y1
#   AL15/AL14 (PCIE_REFCLK0) -> bank 227 = quad X1Y3
# The GT refclk must be within 2 quads of every transceiver on its link.
# For this endpoint (quads X1Y0, X1Y1):
#   AR15 in X1Y1 -> distances 1 and 0   OK
#   AL15 in X1Y3 -> distances 3 and 2   FAILS [Place 30-739] on the X1Y0 lanes
# So THIS endpoint must take AR15/AR14, and endpoint A takes AL15/AL14 --
# i.e. the refclk that the single-QDMA au55n build assigns to endpoint 0 moves
# here. See constr/au55n/pins.xdc and docs/au55n-2qdma-gen4x8-design.md §3.
#
# select_quad: this endpoint's lane 0 (= edge lane 8, pin AV4/AU7) is in bank
# 225, and its refclk AR15 is also bank 225, so both readings of select_quad
# agree on GTY_Quad_225.
# ---------------------------------------------------------------------------
set au55n_ep1_pcie_blk  "PCIE4C_X1Y0"     ;# adjacent to quad X1Y0 (lanes 12..15)
set au55n_ep1_gty_quad  "GTY_Quad_225"    ;# refclk AR15 + this link's lane 0

# ORDER IS LOAD-BEARING -- see the long note in qdma_no_sriov_au55n.tcl.
# Changing PCIE_BOARD_INTERFACE re-derives every dependent parameter, so it has
# to come FIRST.  Link geometry set before it is silently reset to the IP
# defaults (X16 / 8.0_GT/s) with no error and no warning -- a clean run produced
# Gen3 endpoints that way.
set_property -dict {
    CONFIG.SYS_RST_N_BOARD_INTERFACE {Custom}
    CONFIG.PCIE_BOARD_INTERFACE {Custom}
} [get_ips $qdma_1]

set_property -dict "
    CONFIG.mode_selection {Advanced}
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

" [get_ips $qdma_1]

# Placement, before geometry.  pcie_blk_locn is only writable once the board interface is
# Custom; otherwise it is a disabled parameter and the write is dropped with
# only [IP_Flow 19-3374].  xlnx_ref_board must stay AU55N because BOARD_PART is
# set ([IP_Flow 19-3461]).
set_property -dict "
    CONFIG.en_gt_selection {true}
    CONFIG.pcie_blk_locn {$au55n_ep1_pcie_blk}
    CONFIG.select_quad {$au55n_ep1_gty_quad}
" [get_ips $qdma_1]

# Link geometry LAST -- after placement.
#
# Writing select_quad/pcie_blk_locn re-derives the link parameters, so geometry
# written before placement is silently reset to the IP defaults (X16/8.0_GT/s)
# with no error.  Verified against the IP in isolation: placement first, then
# geometry, and both stick.
#
# Device IDs are deliberately NOT set: the IP derives them from gen+width
# (Gen3 x16 -> 903F, Gen3 x8 -> 9038, Gen4 x8 -> 9048) and silently overrides an
# explicit value.  That makes the ID a useful assertion -- reading 9048 back out
# of the .xci is the proof that Gen4 x8 really took effect, and 9038 means the
# speed silently fell back to Gen3.
set_property -dict {
    CONFIG.pl_link_cap_max_link_width {X8}
    CONFIG.pl_link_cap_max_link_speed {16.0_GT/s}
    CONFIG.coreclk_freq {500}
    CONFIG.INS_LOSS_NYQ {5}
    CONFIG.ins_loss_profile {Add-in_Card}
    CONFIG.vsec_cap_addr {0xe00}
} [get_ips $qdma_1]


set_property CONFIG.tl_pf_enable_reg $num_phys_func [get_ips $qdma_1]
set_property CONFIG.num_queues $num_queue [get_ips $qdma_1]
