# *************************************************************************
# QDMA for BittWare XUP-VV8 (VU13P)
# PCIe Gen3 x16, no Xilinx board interface (custom board).
# *************************************************************************
set qdma qdma_no_sriov
create_ip -name qdma -vendor xilinx.com -library ip -module_name $qdma -dir ${ip_build_dir}
set_property -dict {
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
} [get_ips $qdma]
set_property CONFIG.tl_pf_enable_reg $num_phys_func [get_ips $qdma]
set_property CONFIG.num_queues $num_queue [get_ips $qdma]
