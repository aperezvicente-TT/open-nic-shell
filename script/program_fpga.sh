#==============================================================================
# Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT
#
#==============================================================================
#  Program local FPGA board without rebooting the server
# 
#  Usage ./program_fpga.sh [-t|--target_id target_name]
#                         [-p|--prog_file *.bit|*.mcs]
#                         [-c|--config_file *.ltx]
#                         [-r|--remote_host hostname|IP_address]
#
#  [NOTE] 1. This script should be executed on a host server with the target
#            FPGA board.
#         2. Target ID will be auto-detected from the first available device
#            if not specified. It can also be obtained from "Open New Target" 
#            under "Open Hardware Manager" of "PROGRAM AND DEBUG" in Vivado GUI.
#
#==============================================================================
#!/bin/bash

# Define usage
usage_func() {
  echo -e  "Usage:"
  echo -e  "  ./program_fpga.sh [option]
  Options and arguments:
  -t, --target_id    FPGA target device name or ID (auto-detected if not specified)
  -p, --prog_file    FPGA programming file in \"bit\" or \"mcs\" format
  -c, --config_file  DDR Configuration file in \"ltx\" format
  -r, --remote_host  Remote hostname or IP address used to program FPGA board\n"                   
  echo "Info: This script should be executed locally on a host server with the target FPGA board."
  echo "Info: For mcs programming, user has to provide /your/path/to/your_file.mcs."
  echo -e "Info: Target ID will be auto-detected from the first available FPGA device if not specified.\n"
}

# Auto-detect first FPGA target ID
auto_detect_target() {
  local host="$1"
  local port=3121
  
  # Create temporary TCL script
  local tcl_script="/tmp/get_target_$$.tcl"
  
  if [[ -z "$host" || "$host" == "localhost" ]]; then
    cat > "$tcl_script" << 'TCL_EOF'
open_hw_manager
if {[catch {connect_hw_server -allow_non_jtag} result]} {
    puts "ERROR: Failed to connect to hardware server"
    exit 1
}
set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No hardware targets found"
    exit 1
}
puts [lindex $targets 0]
TCL_EOF
  else
    cat > "$tcl_script" << EOF
open_hw_manager
if {[catch {connect_hw_server -url $host:$port -allow_non_jtag} result]} {
    puts "ERROR: Failed to connect to hardware server at $host:$port"
    exit 1
}
set targets [get_hw_targets]
if {[llength \$targets] == 0} {
    puts "ERROR: No hardware targets found on $host"
    exit 1
}
puts [lindex \$targets 0]
EOF
  fi
  
  # Run Vivado to get target
  local result
  result=$(vivado -nolog -nojournal -mode batch -source "$tcl_script" 2>&1)
  local exit_code=$?
  
  # Cleanup
  rm -f "$tcl_script"
  
  if [[ $exit_code -ne 0 ]]; then
    echo "ERROR: Failed to auto-detect target ID" >&2
    echo "$result" | tail -10 >&2
    return 1
  fi
  
  # Extract target ID from path like "localhost:3121/xilinx_tcf/Xilinx/21290605K042A"
  local target_line
  target_line=$(echo "$result" | grep -i 'xilinx_tcf/Xilinx/' | head -1)
  
  if [[ -z "$target_line" ]]; then
    echo "ERROR: Could not find target in Vivado output" >&2
    return 1
  fi
  
  # Extract just the target ID (e.g., "21290605K042A")
  local detected_id
  detected_id=$(echo "$target_line" | sed 's/.*\/Xilinx\///' | awk '{print $1}')
  
  if [[ -z "$detected_id" ]]; then
    echo "ERROR: Could not parse target ID" >&2
    return 1
  fi
  
  echo "$detected_id"
  return 0
}

prog_file=""
config_file=""
target_id=""
remote_host=""

# Process command-line options and arguments
OPTIONS="p:c:t:r:"
LONGOPTS="prog_file:,config_file:,target_id:,remote_host:"

# Parsing command-line options
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")

# Resetting command-line arguments
eval set -- "$PARSED"

# Extracting options and arguments
while true; do
  case "$1" in
    -p|--prog_file)
      prog_file=$(realpath $2)
      shift 2
      ;;
    -c|--config_file)
      config_file=$(realpath $2)
      shift 2
      ;;
    -t|--target_id)
      target_id="$2"
      shift 2
      ;;
    -r|--remote_host)
      remote_host="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Error: Invalid option"
      usage_func
      exit 1
      ;;
  esac
done

# Auto-detect target ID if not specified
if [ "$target_id" == "" ]; then
  echo "Target ID not specified, auto-detecting first available device..."
  target_id=$(auto_detect_target "$remote_host")
  if [ $? -ne 0 ] || [ -z "$target_id" ]; then
    echo "Error: Failed to auto-detect target ID"
    echo "Please specify target ID manually with -t option"
    echo "You can find available targets with: ./get_target_id.sh"
    exit 1
  fi
  echo "Auto-detected target ID: $target_id"
fi

echo "prog_file: $prog_file"
echo "config_file: $config_file"
echo "target_id: $target_id"
echo "remote_host: $remote_host"

# program fpga
if [[ ${prog_file} == *.mcs ]]; then
  # Build TCL arguments
  tcl_args="-prog_file $prog_file -target_id $target_id"
  if [ -n "$config_file" ]; then
    tcl_args="$tcl_args -config_file $config_file"
  fi
  if [ -n "$remote_host" ]; then
    tcl_args="$tcl_args -remote_host $remote_host"
  fi
  echo "vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args"
  vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args
else
  if [ "$prog_file" == "" ]; then
    # Build TCL arguments
    tcl_args="-target_id $target_id"
    if [ -n "$remote_host" ]; then
      tcl_args="$tcl_args -remote_host $remote_host"
    fi
    echo "vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args"
    vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args
  else
    # Build TCL arguments
    tcl_args="-target_id $target_id -prog_file $prog_file"
    if [ -n "$config_file" ]; then
      tcl_args="$tcl_args -config_file $config_file"
    fi
    if [ -n "$remote_host" ]; then
      tcl_args="$tcl_args -remote_host $remote_host"
    fi
    echo "vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args"
    vivado -mode tcl -source program_hw.tcl -tclargs $tcl_args
  fi
fi

if [[ ${prog_file} == *.mcs ]]; then
  echo "Info: Please reboot the machine when mcs programming is done"
fi
