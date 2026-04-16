# *************************************************************************
#
# Copyright 2023 Xilinx, Inc.
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
# AXI clock converter for device memory path.
# Converts from the 250 MHz datapath clock to the MIG DDR4 controller clock.
# Matches the output of dev_mem_4to1_axi_crossbar (ID_WIDTH=7 = 5 + ceil(log2(4))).
# ADDR_WIDTH=34 matches the AU250 DDR4 address space.

set axi_clock_converter axi_clock_converter_for_mem
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name $axi_clock_converter -dir ${ip_build_dir}
set_property -dict {
    CONFIG.PROTOCOL {AXI4}
    CONFIG.READ_WRITE_MODE {READ_WRITE}
    CONFIG.ADDR_WIDTH {34}
    CONFIG.DATA_WIDTH {512}
    CONFIG.ID_WIDTH {7}
    CONFIG.AWUSER_WIDTH {0}
    CONFIG.ARUSER_WIDTH {0}
    CONFIG.RUSER_WIDTH {0}
    CONFIG.WUSER_WIDTH {0}
    CONFIG.BUSER_WIDTH {0}
    CONFIG.ACLK_ASYNC {1}
    CONFIG.SYNCHRONIZATION_STAGES {3}
    CONFIG.ACLK_RATIO {1:2}
} [get_ips $axi_clock_converter]
