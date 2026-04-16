# *************************************************************************
# CMAC 0 for BittWare XUP-VV8 (VU13P)
# Maps to QSFP-DD port 3 lower lane group.
#   GTY Bank 128 -> lanes X0Y32..X0Y35
#   Hard CMAC tile: CMACE4_X0Y6 (SLR=1, same SLR as PCIe Gen3 x16)
#   Reference clock from Si5346-A (322.265625 MHz) into refclk0 of bank 128.
# *************************************************************************
set cmac_usplus cmac_usplus_0
create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name $cmac_usplus -dir ${ip_build_dir}
set_property -dict {
    CONFIG.CMAC_CAUI4_MODE {1}
    CONFIG.NUM_LANES {4x25}
    CONFIG.USER_INTERFACE {AXIS}
    CONFIG.GT_REF_CLK_FREQ {322.265625}
    CONFIG.ENABLE_AXI_INTERFACE {1}
    CONFIG.INCLUDE_STATISTICS_COUNTERS {1}
    CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y6}
    CONFIG.GT_GROUP_SELECT {X0Y32~X0Y35}
    CONFIG.LANE1_GT_LOC {X0Y32}
    CONFIG.LANE2_GT_LOC {X0Y33}
    CONFIG.LANE3_GT_LOC {X0Y34}
    CONFIG.LANE4_GT_LOC {X0Y35}
    CONFIG.LANE5_GT_LOC {NA}
    CONFIG.LANE6_GT_LOC {NA}
    CONFIG.LANE7_GT_LOC {NA}
    CONFIG.LANE8_GT_LOC {NA}
    CONFIG.LANE9_GT_LOC {NA}
    CONFIG.LANE10_GT_LOC {NA}
    CONFIG.GT_DRP_CLK {125.00}
    CONFIG.RX_GT_BUFFER {1}
    CONFIG.GT_RX_BUFFER_BYPASS {0}
    CONFIG.INS_LOSS_NYQ {20}
    CONFIG.INCLUDE_RS_FEC {1}
    CONFIG.ENABLE_PIPELINE_REG {1}
    CONFIG.ENABLE_TIME_STAMPING {1}
} [get_ips $cmac_usplus]
set_property CONFIG.RX_MIN_PACKET_LEN $min_pkt_len [get_ips $cmac_usplus]
set_property CONFIG.RX_MAX_PACKET_LEN $max_pkt_len [get_ips $cmac_usplus]
