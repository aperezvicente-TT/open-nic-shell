# *************************************************************************
# BittWare XUP-VV8 (VU13P) pin constraints for OpenNIC shell.
# Pin assignments taken from xupvv8_vu13p_master_constraints.xdc.
#
# This file is loaded as unmanaged Tcl so that conditional blocks can gate
# signals based on NUM_CMAC_PORT (number of qsfp_refclk_p ports present).
#
# Initial port target: QSFP-DD port 3 (SLR=1), split into two 100GbE CMACs.
#   CMAC 0 refclk  -> Bank 128 refclk0 (pins AC36/AC37)
#   CMAC 1 refclk  -> Bank 129 refclk0 (pins AA36/AA37)
# *************************************************************************

# PCIe Gen3 x16 (banks 224-227).  Refclk pair AT10/AT11 on bank 225 clk1.
set_property PACKAGE_PIN AT10 [get_ports pcie_refclk_n]
set_property PACKAGE_PIN AT11 [get_ports pcie_refclk_p]

# PCIe PERST# on FPGA pin BB20 (LVCMOS18)
set_property -dict {PACKAGE_PIN BB20 IOSTANDARD LVCMOS18} [get_ports pcie_rstn]

# QSFP-DD GTY reference clocks (322.265625 MHz from the Si5346 jitter cleaners)
set num_ports [llength [get_ports qsfp_refclk_p]]
if {$num_ports >= 1} {
    set_property PACKAGE_PIN AC36 [get_ports qsfp_refclk_p[0]]
    set_property PACKAGE_PIN AC37 [get_ports qsfp_refclk_n[0]]
}
if {$num_ports >= 2} {
    set_property PACKAGE_PIN AA36 [get_ports qsfp_refclk_p[1]]
    set_property PACKAGE_PIN AA37 [get_ports qsfp_refclk_n[1]]
}

# BittWare BMC UART ("AVR" side) reused as OpenNIC satellite_uart.
# - avr_rxd (BMC receives)  = FPGA transmits = satellite_uart_0_txd  (AN22)
# - avr_txd (BMC transmits) = FPGA receives  = satellite_uart_0_rxd  (AN21)
set_property -dict {PACKAGE_PIN AN22 IOSTANDARD LVCMOS18} [get_ports satellite_uart_0_txd]
set_property -dict {PACKAGE_PIN AN21 IOSTANDARD LVCMOS18} [get_ports satellite_uart_0_rxd]
