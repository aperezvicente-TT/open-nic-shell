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
# 2:1 AXI crossbar (mux) for merging the sys_mem outputs from two
# Tier 1 (5:2) crossbars — one per ERNIC instance.
# The upstream 5:2 crossbar has ID_WIDTH=3, so the master-side IDs are
# 3 bits. This crossbar adds ceil(log2(2)) = 1 routing bit, giving a
# 4-bit output ID.

set system_memory_mux sys_mem_2to1_axi_crossbar

create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name $system_memory_mux -dir ${ip_build_dir}

set_property -dict {
    CONFIG.ADDR_RANGES {1}
    CONFIG.NUM_SI {2}
    CONFIG.NUM_MI {1}
    CONFIG.ADDR_WIDTH {64}
    CONFIG.DATA_WIDTH {512}
    CONFIG.ID_WIDTH {3}
    CONFIG.S00_WRITE_ACCEPTANCE {8}
    CONFIG.S01_WRITE_ACCEPTANCE {8}
    CONFIG.S00_READ_ACCEPTANCE {8}
    CONFIG.S01_READ_ACCEPTANCE {8}
    CONFIG.M00_WRITE_ISSUING {16}
    CONFIG.M00_READ_ISSUING {16}
    CONFIG.S00_SINGLE_THREAD {0}
    CONFIG.M00_A00_ADDR_WIDTH {64}
} [get_ips $system_memory_mux]
