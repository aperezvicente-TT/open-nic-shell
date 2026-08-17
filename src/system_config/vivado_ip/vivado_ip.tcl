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
set ips {
    system_config_axi_crossbar
    system_management_wiz
    clk_wiz_50Mhz
    axi_quad_spi_0
}

# The Card Management Subsystem is an ALVEO-ONLY IP: xilinx.com:ip:cms_subsystem
# is not accessible for a bare Virtex part, only for xcu2xx/xcu5x.  The VCU1525
# targets the raw xcvu9p (Vivado 2024.2 ships no VCU1525 board file), so
# requesting it there fails with:
#   ERROR: [Coretcl 2-1132] No IP matching VLNV 'xilinx.com:ip:cms_subsystem:4.0'
#          is accessible for the current part 'xcvu9p-fsgd2104-2L-e'
# system_config.sv replaces what CMS provides on this board -- see the
# `ifdef __vcu1525__ branch there (static QSFP sidebands + an AXI-Lite stub).
if {$board ne "vcu1525"} {
    lappend ips "cms_subsystem_0"
} else {
    # No CMS here, so the shell drives the board I2C bus itself to read QSFP
    # module diagnostics.  Sits in the address window CMS would have occupied,
    # so no crossbar/address-map change is needed.
    lappend ips "axi_iic_0"
}

if {$num_qdma > 1} {
    lappend ips "system_config_axi_clock_converter"
}