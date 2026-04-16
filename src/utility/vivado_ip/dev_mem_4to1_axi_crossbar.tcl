# *************************************************************************
#
# Copyright 2022 Xilinx, Inc.
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
# 4:1 AXI crossbar for device memory (DDR4).
# 4 slave ports: QDMA_MM, Compute, sys_xbar_0_dev, sys_xbar_1_dev
# 1 master port: to DDR4 (via clock converter)
#
# ID_WIDTH = 5 to accommodate upstream crossbar IDs (3-bit from 5:2 xbar)
# plus 2-bit routing bits appended by this crossbar (ceil(log2(4)) = 2).

set device_memory_axi_crossbar dev_mem_4to1_axi_crossbar

create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name $device_memory_axi_crossbar -dir ${ip_build_dir}

set_property -dict {
    CONFIG.ADDR_RANGES {1}
    CONFIG.NUM_SI {4}
    CONFIG.NUM_MI {1}
    CONFIG.ADDR_WIDTH {64}
    CONFIG.DATA_WIDTH {512}
    CONFIG.ID_WIDTH {5}
    CONFIG.S00_THREAD_ID_WIDTH {3}
    CONFIG.S01_THREAD_ID_WIDTH {3}
    CONFIG.S02_THREAD_ID_WIDTH {3}
    CONFIG.S03_THREAD_ID_WIDTH {3}
    CONFIG.S00_WRITE_ACCEPTANCE {8}
    CONFIG.S01_WRITE_ACCEPTANCE {8}
    CONFIG.S02_WRITE_ACCEPTANCE {8}
    CONFIG.S03_WRITE_ACCEPTANCE {8}
    CONFIG.S00_READ_ACCEPTANCE {8}
    CONFIG.S01_READ_ACCEPTANCE {8}
    CONFIG.S02_READ_ACCEPTANCE {8}
    CONFIG.S03_READ_ACCEPTANCE {8}
    CONFIG.M00_WRITE_ISSUING {16}
    CONFIG.M00_READ_ISSUING {16}
    CONFIG.S00_SINGLE_THREAD {0}
    CONFIG.M00_A00_ADDR_WIDTH {64}
} [get_ips $device_memory_axi_crossbar]
