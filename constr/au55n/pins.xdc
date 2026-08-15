# *************************************************************************
#
# Copyright 2021 Xilinx, Inc.
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

# One PERST pin for the whole connector. With -num_qdma 2 the top level declares
# pcie_rstn as a scalar (see open_nic_shell.sv) and fans it out to both
# endpoints; either way this get_ports matches.
set_property -dict {PACKAGE_PIN BF41 IOSTANDARD LVCMOS18} [get_ports pcie_rstn]

# ---------------------------------------------------------------------------
# PCIe reference clock(s)
#
# Resolved against xcu55n-fsvh2892-2L-e (Vivado 2024.2, link_design + get_sites):
#   AR15/AR14 = PCIE_REFCLK1 -> GT bank 225 = quad X1Y1
#   AL15/AL14 = PCIE_REFCLK0 -> GT bank 227 = quad X1Y3
# Edge lanes:  0..3 -> quad X1Y3 (bank 227)    8..11 -> quad X1Y1 (bank 225)
#              4..7 -> quad X1Y2 (bank 226)   12..15 -> quad X1Y0 (bank 224)
#
# A GT refclk must be within 2 quads of every transceiver on its link.
# ---------------------------------------------------------------------------
set num_pcie_refclk [llength [get_ports pcie_refclk_p]]
if {$num_pcie_refclk <= 1} {
    # Single endpoint, Gen3 x16 spanning all four quads X1Y0..X1Y3.
    # AR15 (quad X1Y1) is the ONLY legal pair: distances 1,0,1,2.
    # AL15 (quad X1Y3) would be 3 quads from the X1Y0 lanes and fail.
    set_property PACKAGE_PIN AR14 [get_ports pcie_refclk_n]
    set_property PACKAGE_PIN AR15 [get_ports pcie_refclk_p]
} else {
    # Bifurcated x8x8. The split is FORCED, not a preference:
    #   endpoint B (lanes 8..15 = quads X1Y1, X1Y0) can only use AR15
    #     (distances 0,1); AL15 would be 2,3 -> [Place 30-739].
    #   endpoint A (lanes 0..7  = quads X1Y3, X1Y2) therefore takes AL15
    #     (distances 0,1 -- in fact the tighter of the two).
    # Note this MOVES AR15 off endpoint 0, where the 1-QDMA build has it.
    set_property PACKAGE_PIN AL14 [get_ports {pcie_refclk_n[0]}]
    set_property PACKAGE_PIN AL15 [get_ports {pcie_refclk_p[0]}]
    set_property PACKAGE_PIN AR14 [get_ports {pcie_refclk_n[1]}]
    set_property PACKAGE_PIN AR15 [get_ports {pcie_refclk_p[1]}]

    # -----------------------------------------------------------------------
    # PCIe serial lanes, 8 per endpoint.
    #
    # Today's 1-QDMA au55n build constrains NONE of these: the QDMA IP's board
    # interface places its GTYE4_CHANNELs, and GT serial pads are reached by
    # channel placement rather than through the fabric (which is why au200
    # synthesis can warn "Net pcie_txp does not have driver" and still work).
    #
    # Here both endpoints are configured Custom, and an x8 link needs 8
    # channels = 2 quads. Left to itself the IP could pick bank 226 as endpoint
    # B's second quad, which is endpoint A's territory. Constraining the pins
    # pins each endpoint to disjoint quads instead of trusting that choice.
    #
    # Pin data: board_files/Xilinx/au55n/part0_pins.xml
    # -----------------------------------------------------------------------
    # ---- endpoint A: edge lanes 0..7 -> banks 227 (quad X1Y3) + 226 (X1Y2) --
    foreach {idx rxp rxn txp txn} {
        0  AL2  AL1  AL11 AL10
        1  AM4  AM3  AM9  AM8
        2  AN6  AN5  AN11 AN10
        3  AN2  AN1  AP9  AP8
        4  AP4  AP3  AR11 AR10
        5  AR2  AR1  AR7  AR6
        6  AT4  AT3  AT9  AT8
        7  AU2  AU1  AU11 AU10
    } {
        set_property PACKAGE_PIN $rxp [get_ports "pcie_rxp[$idx]"]
        set_property PACKAGE_PIN $rxn [get_ports "pcie_rxn[$idx]"]
        set_property PACKAGE_PIN $txp [get_ports "pcie_txp[$idx]"]
        set_property PACKAGE_PIN $txn [get_ports "pcie_txn[$idx]"]
    }
    # ---- endpoint B: edge lanes 8..15 -> banks 225 (quad X1Y1) + 224 (X1Y0) -
    foreach {idx rxp rxn txp txn} {
        8   AV4  AV3  AU7  AU6
        9   AW6  AW5  AV9  AV8
        10  AW2  AW1  AW11 AW10
        11  AY4  AY3  AY9  AY8
        12  BA6  BA5  BA11 BA10
        13  BA2  BA1  BB9  BB8
        14  BB4  BB3  BC11 BC10
        15  BC2  BC1  BC7  BC6
    } {
        set_property PACKAGE_PIN $rxp [get_ports "pcie_rxp[$idx]"]
        set_property PACKAGE_PIN $rxn [get_ports "pcie_rxn[$idx]"]
        set_property PACKAGE_PIN $txp [get_ports "pcie_txp[$idx]"]
        set_property PACKAGE_PIN $txn [get_ports "pcie_txn[$idx]"]
    }
}

set num_ports [llength [get_ports qsfp_refclk_p]]
if {$num_ports >= 1} {
#    IO pins AD42, AD43 are on IO Bank 130 for use with GTY X0Y24~27
    set_property PACKAGE_PIN AD43 [get_ports qsfp_refclk_n[0]]
    set_property PACKAGE_PIN AD42 [get_ports qsfp_refclk_p[0]]

    set_property -dict {PACKAGE_PIN BL13  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_activity_led[0]}]
    set_property -dict {PACKAGE_PIN BK11  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_link_stat_ledg[0]}]
    set_property -dict {PACKAGE_PIN BJ11  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_link_stat_ledy[0]}]
}
if {$num_ports >= 2} {
#    IO pins AB43, AB42 are on IO Bank 131 for use with GTY X0Y28~31 
    set_property PACKAGE_PIN AB43 [get_ports qsfp_refclk_n[1]]
    set_property PACKAGE_PIN AB42 [get_ports qsfp_refclk_p[1]]

    set_property -dict {PACKAGE_PIN BK14  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_activity_led[1]}]
    set_property -dict {PACKAGE_PIN BK15  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_link_stat_ledg[1]}]
    set_property -dict {PACKAGE_PIN BL12  IOSTANDARD LVCMOS18 DRIVE 8} [get_ports {qsfp_link_stat_ledy[1]}]
}

# Fix the CATTRIP issue for custom flow
# Read AR72926 for details.
set_property -dict {PACKAGE_PIN BE45 IOSTANDARD LVCMOS18 PULLDOWN TRUE} [get_ports hbm_cattrip]

set_property -dict {PACKAGE_PIN BH42 IOSTANDARD LVCMOS18} [get_ports satellite_uart_0_txd]
set_property -dict {PACKAGE_PIN BJ42 IOSTANDARD LVCMOS18} [get_ports satellite_uart_0_rxd]
set_property -dict {PACKAGE_PIN BE46 IOSTANDARD LVCMOS18} [get_ports satellite_gpio[0]]
set_property -dict {PACKAGE_PIN BH46 IOSTANDARD LVCMOS18} [get_ports satellite_gpio[1]]
set_property -dict {PACKAGE_PIN BF45 IOSTANDARD LVCMOS18} [get_ports satellite_gpio[2]]
set_property -dict {PACKAGE_PIN BF46 IOSTANDARD LVCMOS18} [get_ports satellite_gpio[3]]




