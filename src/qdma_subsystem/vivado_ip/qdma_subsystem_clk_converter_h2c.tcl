# *************************************************************************
#
# Copyright 2023 AMD, Inc.
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
# H2C clock converter for the QDMA_ID != 0 datapath (multi-QDMA builds only).
#
# TUSER carries {qid[10:0], size[15:0]} = 27 bits, so the queue ID crosses the
# clock domain byte-locked to its own data beat.  The predecessor to this IP
# was 16 bits wide (size only) and the qid was carried beside the data in a
# side-FIFO, which skewed the qid by one packet at packet boundaries and
# misrouted traffic between CMACs.  See docs/03-qdma-subsystem.md 3.3.
#
# A clock converter is genuinely required on this path (unlike QDMA_ID == 0,
# which uses a same-clock axi_stream_register_slice): every QDMA instance
# produces its own 250 MHz axis_aclk, and instance != 0 must cross into the
# master instance's domain.
# *************************************************************************
set axis_clock_converter qdma_subsystem_clk_converter_h2c
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name $axis_clock_converter -dir ${ip_build_dir}
set_property -dict {
  CONFIG.HAS_TKEEP {1}
  CONFIG.HAS_TLAST {1}
  CONFIG.TDATA_NUM_BYTES {64}
  CONFIG.TUSER_WIDTH {27}
 } [get_ips $axis_clock_converter]
