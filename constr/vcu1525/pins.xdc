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

# This file should be read in as unmanaged Tcl constraints to enable the usage
# of if statement
set_property PACKAGE_PIN AM10 [get_ports pcie_refclk_n]
set_property PACKAGE_PIN AM11 [get_ports pcie_refclk_p]

set_property -dict {PACKAGE_PIN BD21 IOSTANDARD LVCMOS12 PULLUP TRUE} [get_ports pcie_rstn]

set num_ports [llength [get_ports qsfp_refclk_p]]
if {$num_ports >= 1} {
    set_property PACKAGE_PIN K10 [get_ports qsfp_refclk_n[0]]
    set_property PACKAGE_PIN K11 [get_ports qsfp_refclk_p[0]]

}
if {$num_ports >= 2} {
    set_property PACKAGE_PIN P10 [get_ports qsfp_refclk_n[1]]
    set_property PACKAGE_PIN P11 [get_ports qsfp_refclk_p[1]]

}

set_property -dict {PACKAGE_PIN BB19 IOSTANDARD LVCMOS12 DRIVE 8} [get_ports satellite_uart_0_txd]
set_property -dict {PACKAGE_PIN BA19 IOSTANDARD LVCMOS12}         [get_ports satellite_uart_0_rxd]
set_property -dict {PACKAGE_PIN AR20 IOSTANDARD LVCMOS12}         [get_ports satellite_gpio[0]]
set_property -dict {PACKAGE_PIN AM20 IOSTANDARD LVCMOS12}         [get_ports satellite_gpio[1]]
set_property -dict {PACKAGE_PIN AM21 IOSTANDARD LVCMOS12}         [get_ports satellite_gpio[2]]
set_property -dict {PACKAGE_PIN AN21 IOSTANDARD LVCMOS12}         [get_ports satellite_gpio[3]]

# Board LEDs
# LED[0] Red    - Heartbeat (bitstream alive)
# LED[1] Yellow - QSFP1 link/activity
# LED[2] Green  - QSFP0 link/activity
set_property PACKAGE_PIN BC21 [get_ports {gpio_led[0]}]
set_property PACKAGE_PIN BB21 [get_ports {gpio_led[1]}]
set_property PACKAGE_PIN BA20 [get_ports {gpio_led[2]}]
set_property IOSTANDARD LVCMOS12 [get_ports {gpio_led[0]}]
set_property IOSTANDARD LVCMOS12 [get_ports {gpio_led[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports {gpio_led[2]}]
set_property SLEW SLOW [get_ports {gpio_led[*]}]
set_property DRIVE 8   [get_ports {gpio_led[*]}]
set_false_path -to [get_ports {gpio_led[*]}]

# QSFP Control Signals
#       RESETL  - Active Low Reset output from FPGA to QSFP Module
#       MODPRSL - Active Low Module Present input from QSFP to FPGA
#       INTL    - Active Low Interrupt input from QSFP to FPGA
#       LPMODE  - Active High Control output from FPGA to QSFP Module to put the device in low power mode (Optics Off)
#       MODSEL  - Active Low Enable output from FPGA to QSFP Module to select device for I2C Sideband Communication
#
set_property -dict {PACKAGE_PIN BE17 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_resetl[0]  ]
set_property -dict {PACKAGE_PIN BE20 IOSTANDARD LVCMOS12 PULLUP TRUE       }  [get_ports qsfp_modprsl[0] ]
set_property -dict {PACKAGE_PIN BE21 IOSTANDARD LVCMOS12 PULLUP TRUE       }  [get_ports qsfp_intl[0]    ]
set_property -dict {PACKAGE_PIN BD18 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_lpmode[0]  ]
set_property -dict {PACKAGE_PIN BE16 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_modsell[0] ]
set_property -dict {PACKAGE_PIN BC18 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_resetl[1]  ]
set_property -dict {PACKAGE_PIN BC19 IOSTANDARD LVCMOS12 PULLUP TRUE       }  [get_ports qsfp_modprsl[1] ]
set_property -dict {PACKAGE_PIN AV21 IOSTANDARD LVCMOS12 PULLUP TRUE       }  [get_ports qsfp_intl[1]    ]
set_property -dict {PACKAGE_PIN AV22 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_lpmode[1]  ]
set_property -dict {PACKAGE_PIN AY20 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp_modsell[1] ]



# ---------------------------------------------------------------------------
# Added 2026-08-17 for the CMS-less VCU1525 build.  Pin locations cross-checked
# against corundum fpga_au200.xdc (same board design).
#
# Shared board I2C bus -- ONE bus reaches the FPGA, not one per cage; the cage is
# chosen with qsfp_modsell (driven from the AXI IIC's GPO).  Open-drain, so the
# shell drives these through IOBUFs and never drives them high.
set_property -dict {PACKAGE_PIN BF20 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c_scl]
set_property -dict {PACKAGE_PIN BF17 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports i2c_sda]

# SI5335A QSFP refclk frequency select + latch reset.  FS=0b10 -> 161.1328125 MHz.
set_property -dict {PACKAGE_PIN AT20 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {qsfp0_fs[0]}]
set_property -dict {PACKAGE_PIN AU22 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {qsfp0_fs[1]}]
set_property -dict {PACKAGE_PIN AT22 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp0_refclk_reset]
set_property -dict {PACKAGE_PIN AR22 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {qsfp1_fs[0]}]
set_property -dict {PACKAGE_PIN AU20 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports {qsfp1_fs[1]}]
set_property -dict {PACKAGE_PIN AR21 IOSTANDARD LVCMOS12 SLEW SLOW DRIVE 8} [get_ports qsfp1_refclk_reset]

# LEDs are functional on this board (build.tcl defines __gpio_led__):
#   gpio_led[0] heartbeat   [1] CMAC1 link+activity   [2] CMAC0 link+activity
