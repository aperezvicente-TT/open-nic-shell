// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
`ifndef __OPEN_NIC_SHELL_MACROS_VH__
`define __OPEN_NIC_SHELL_MACROS_VH__

`define getbit(width, index, offset)    ((index)*(width) + (offset))
`define getvec(width, index)            ((index)*(width)) +: (width)

// Boards that wire three LVCMOS12 status LEDs to bank-64 GPIO.  U200 and U250
// are the same PCB family and share this pinout (BC21/BB21/BA20, verified
// pin-function identical on xcu200-fsgd2104 and xcu250-figd2104); every other
// bank-64 sideband in constr/au200 and constr/au250 is likewise pin-identical.
// The U250 board wiring was confirmed on hardware: build 0x07311243 lit the
// heartbeat and the CMAC0 link LED on a live card.
// Add a board here and give it the three pins in its pins.xdc.
`ifdef __au200__
  `define __gpio_led__
`endif
`ifdef __au250__
  `define __gpio_led__
`endif

`endif
