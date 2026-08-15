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
# C2H clock converter for the QDMA_ID != 0 datapath (multi-QDMA builds only).
#
# TUSER carries {qid[10:0], ptp_ts[79:0], size[15:0]} = 107 bits, matching the
# QDMA_ID == 0 register-slice packing exactly, so the queue ID crosses the clock
# domain byte-locked to its own data beat.
#
# The RTL in qdma_subsystem_function.sv already drove all 107 bits through this
# converter; only the IP was still customized to the old 16-bit TUSER, which
# silently truncated qid and ptp_ts.  All three widths -- this IP, the
# QDMA_ID == 0 slice, and the buf_fifo -- must agree or the qid corrupts with no
# error anywhere.  See docs/03-qdma-subsystem.md 3.4.
# *************************************************************************
set axis_clock_converter qdma_subsystem_clk_converter_c2h
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name $axis_clock_converter -dir ${ip_build_dir}
set_property -dict {
  CONFIG.HAS_TKEEP {1}
  CONFIG.HAS_TLAST {1}
  CONFIG.TDATA_NUM_BYTES {64}
  CONFIG.TUSER_WIDTH {107}
 } [get_ips $axis_clock_converter]
