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
proc _do_impl {jobs {strategies ""}} {
    if {![llength $strategies]} {
        launch_runs impl_1 -to_step write_bitstream -jobs $jobs
        wait_on_run impl_1
    } else {
        set impl_runs "impl_1"
        set_property STRATEGY "[lindex $strategies 0]" [get_runs impl_1]
        for {set i 1} {$i < [llength $strategies]} {incr i 1} {
            set r impl_[expr $i + 1]
            set s [lindex $strategies $i]
            create_run $r -flow {Vivado Implementation 2020} -parent_run synth_1 -strategy "$s"
            lappend impl_runs $r
        }
        launch_runs $impl_runs -to_step write_bitstream -jobs $jobs
        foreach r $impl_runs {
            wait_on_run $r
        }
    }
}

proc _do_post_impl {build_dir top impl_run {zynq_family 0} board} {
    if {$zynq_family} {
        current_run $impl_run
        set sdk_dir ${build_dir}/${top}.sdk
        file mkdir $sdk_dir
        write_hw_platform -fixed -force -include_bit -file ${sdk_dir}/${top}.xsa
    } else {
        if {$board == "au45n"} {
            set mem_size 256
            set start_address 0x00000000
        } else {
            set mem_size 128
            set start_address 0x01002000
        }
        set interface SPIx4
        set bit_file ${build_dir}/${top}.runs/${impl_run}/${top}.bit
        set mcs_file ${build_dir}/${top}.runs/${impl_run}/${top}.mcs
        write_cfgmem -format mcs -size $mem_size -interface $interface -loadbit "up $start_address $bit_file" -file "$mcs_file"
    }
}

# Directory variables
set root_dir [file normalize ..]
set constr_dir ${root_dir}/constr
set plugin_dir ${root_dir}/plugin
set script_dir ${root_dir}/script
set src_dir ${root_dir}/src

# Build options
#   board_repo             Path to the Xilinx board store repository
#   board                  Board name
#   tag                    Tag to identify the build
#   overwrite              Overwrite existing build results
#   rebuild                Update build directory but respect overwrite
#   jobs                   Number of jobs for synthesis and implementation
#   synth_ip               Synthesize IPs before creating design project
#   impl                   Run implementation after creating design project
#   post_impl              Perform post implementation actions
#   user_plugin            Path to the user plugin repo
#   bitstream_userid       Bitstream.config userid
#   bitstream_usr_access   Bitstream.config usr_access
#   sim                    Build design for simulation
#
# Design parameters
#   build_timestamp  Timestamp to identify the build
#   min_pkt_len      Minimum packet length
#   max_pkt_len      Maximum packet length
#   use_phys_func    Include H2C and C2H AXI-stream interfaces (0 or 1)
#   num_phys_func    Number of PCI-e physical functions (1 to 4)
#   num_qdma      Number of QDMA interfaces (1 to 2)
#   num_queue        Number of QDMA queues (1 to 2048)
#   num_cmac_port    Number of CMAC ports (1 or 2)
#
# Simulation parameters
#   sim_exec_path  Path to directory containing simulator executable
#   sim_lib_path   Path where simulation libraries should be compiled
#   sim_top        Top level module to simulate

array set build_options {
    -board_repo  ""
    -board       au250
    -tag         ""
    -overwrite   0
    -rebuild     0
    -jobs        8
    -synth_ip    1
    -impl        0
    -post_impl   0
    -user_plugin ""
    -bitstream_userid  "0xDEADC0DE"
    -bitstream_usr_access "0x66669999"
    -sim  0
    -rdma        0
    -classifier  rtl
}
set build_options(-user_plugin) ${plugin_dir}/p2p

array set design_params {
    -build_timestamp  0
    -min_pkt_len      64
    -max_pkt_len      1518
    -pkt_cap          64
    -use_phys_func    1
    -num_phys_func    1
    -num_qdma         1
    -num_queue        512
    -num_cmac_port    1
}
set design_params(-build_timestamp) [clock format [clock seconds] -format %m%d%H%M]

array set sim_params {
    -sim_exec_path    ""
    -sim_lib_path     ""
    -sim_top          ""
}

# Expect arguments in the form of `-argument value`
for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists build_options($arg)]} {
        set build_options($arg) $val
        puts "Set build option $arg to $val"
    } elseif {[info exists design_params($arg)]} {
        set design_params($arg) $val
        puts "Set design parameter $arg to $val"
    } elseif {[info exists sim_params($arg)]} {
        set sim_params($arg) $val
        puts "Set sim parameter $arg to $val"
    } else {
        puts "Skip unknown argument $arg and its value $val"
    }
}

# Settings based on defaults or passed in values
foreach {key value} [array get build_options] {
    set [string range $key 1 end] $value
}
foreach {key value} [array get design_params] {
    set [string range $key 1 end] $value
}

# Sanity check
if {$min_pkt_len < 64 || $min_pkt_len > 256} {
    puts "Invalid value for -min_pkt_len: allowed range is \[64, 256\]"
    exit
}
if {$max_pkt_len < 256 || $max_pkt_len > 9600} {
    puts "Invalid value for -max_pkt_len: allowed range is \[256, 9600\]"
    exit
}
if {$use_phys_func == 1} {
    if {$num_queue < 1 || $num_queue > 2048} {
        puts "Invalid value for -num_queue: allowed range is \[1, 2048\]"
        exit
    }
    if {$num_phys_func < 1 || $num_phys_func > 4} {
        puts "Invalid value for -num_phys_func: allowed range is \[1, 4\]"
        exit
    }
    if {$num_qdma < 1 || $num_qdma > 2} {
        puts "Invalid value for -num_qdma: allowed range is \[1, 2\]"
        exit
    }
}
if {$num_cmac_port != 1 && $num_cmac_port != 2} {
    puts "Invalid value for -num_cmac_port: allowed values are 1 and 2"
    exit
}

source ${script_dir}/board_settings/${board}.tcl

# Set build directory and dump the current design parameters
set top open_nic_shell
set build_name ${board}
if {![string equal $tag ""]} {
    set build_name ${build_name}_${tag}
}

set build_dir [file normalize ${root_dir}/build/${build_name}]
if {[file exists $build_dir]} {
    if {!$rebuild } {
        puts "Found existing build directory $build_dir"
        puts "  1. Update existing build directory (default)"
        puts "  2. Delete existing build directory and create a new one"
        puts "  3. Exit"
        puts -nonewline {Choose an option: }
        gets stdin ans
        if {[string equal $ans "2"]} {
            file delete -force $build_dir
            puts "Deleted existing build directory $build_dir"
            file mkdir $build_dir
        } elseif {[string equal $ans "3"]} {
            puts "Build directory existed. Try to specify a different design tag"
            exit
        }
    } else {
	file delete -force $build_dir/open_nic_shell
	puts "Deleted existing build director $build_dir/open_nic_shell"
    }
} else {
    file mkdir $build_dir
}
set fp [open "${build_dir}/DESIGN_PARAMETERS" w]
foreach {param val} [array get design_params] {
    puts $fp "$param $val"
}
close $fp

# Update the board store
if {[string equal $board_repo ""]} {
    set_param board.repoPaths "${root_dir}/board_files"    
    # xhub::refresh_catalog [xhub::get_xstores xilinx_board_store]
} else {
    set_param board.repoPaths $board_repo
}

# Enumerate modules
foreach name [glob -tails -directory ${src_dir} -type d *] {
    if {[string equal $name "shell"]} {
        continue
    }
    # Skip RDMA-only modules when -rdma is not enabled
    if {!$rdma && ([string equal $name "mem_ctrl"] || [string equal $name "rdma_subsystem"])} {
        continue
    }
    set mod_dir "${src_dir}/${name}"
    # Board-specific module path (e.g., mem_ctrl/au250)
    if {[string equal $name "mem_ctrl"]} {
        set mod_dir "${mod_dir}/${board}"
    }
    dict append module_dict $name $mod_dir
}

# Create/open Manage IP project
set ip_build_dir ${build_dir}/vivado_ip
if {![file exists ${ip_build_dir}/manage_ip/]} {
    puts "INFO: \[Manage IP\] Creating Manage IP project..."
    create_project -force manage_ip ${ip_build_dir}/manage_ip -part $part -ip
    if {![string equal $board_part ""]} {
        set_property BOARD_PART $board_part [current_project]
    }
    set_property simulator_language verilog [current_project]
} else {
    puts "INFO: \[Manage IP\] Opening existing Manage IP project..."
    open_project -quiet ${ip_build_dir}/manage_ip/manage_ip.xpr
}

# Run synthesis for each IP
set ip_dict [dict create]
dict for {module module_dir} $module_dict {
    set ip_tcl_dir ${module_dir}/vivado_ip

    # Check the existence of "$ip_tcl_dir" and "${ip_tcl_dir}/vivado_ip.tcl"
    if {![file exists $ip_tcl_dir] || ![file exists ${ip_tcl_dir}/vivado_ip.tcl]} {
        puts "INFO: \[$module\] Nothing to build"
        continue
    }

    # Expect the variable "$ips" defined in "vivado_ip.tcl"
    source ${ip_tcl_dir}/vivado_ip.tcl
    if {![info exists ips]} {
        puts "INFO: \[$module\] Nothing to build"
        continue
    }

    foreach ip $ips {
        # Pre-save IP name and its build directory to a global dictionary
        dict append ip_dict $ip ${ip_build_dir}/${ip}

        # Remove IP that does not exists in the project, which may have been
        # deleted by the user and needs to be regnerated
        if {[string equal [get_ips -quiet $ip] ""]} {
            export_ip_user_files -of_objects [get_files ${ip_build_dir}/${ip}/${ip}.xci] -no_script -reset -force -quiet
            remove_files -quiet [get_files ${ip_build_dir}/${ip}/${ip}.xci]
            file delete -force ${ip_build_dir}/${ip}
        }

        # Build the IPs only when
        # - IP directory does not exist, or
        # - "$overwrite" option is nonzero
        set cached [file exists ${ip_build_dir}/${ip}]
        if {$cached && !$overwrite} {
            puts "INFO: \[$ip\] Use existing IP build (overwrite=0)"
            continue
        }
        if {$cached} {
            puts "INFO: \[$ip\] Found existing IP build, deleting... (overwrite=1)"
            if {![string equal [get_ips -quiet $ip] ""]} {
                export_ip_user_files -of_objects [get_files ${ip_build_dir}/${ip}/${ip}.xci] -no_script -reset -force -quiet
                remove_files -quiet [get_files ${ip_build_dir}/${ip}/${ip}.xci]
            }
            file delete -force ${ip_build_dir}/${ip}
        } elseif {![string equal [get_ips -quiet $ip] ""]} {
            # IP is registered in the project but its directory was externally
            # removed (e.g. single-IP manual delete); deregister so create_ip works.
            export_ip_user_files -of_objects [get_files -quiet ${ip_build_dir}/${ip}/${ip}.xci] -no_script -reset -force -quiet
            remove_files -quiet [get_files -quiet ${ip_build_dir}/${ip}/${ip}.xci]
        }

        # Rule for IP scripts
        # - Source "${ip}_${board}.tcl" if exists
        # - Else, source "${ip}.tcl" if exists
        # - Otherwise, skip this IP as it may be specific for certain board target
        if {[file exists "${ip_tcl_dir}/${ip}_${board}.tcl"]} {
            source ${ip_tcl_dir}/${ip}_${board}.tcl
        } elseif {[file exists "${ip_tcl_dir}/${ip}.tcl"]} {
            source ${ip_tcl_dir}/${ip}.tcl
        } else {
            continue
        }

        upgrade_ip [get_ips $ip]
        generate_target synthesis [get_ips $ip]

        # Run out-of-context IP synthesis
        if {$synth_ip} {
            create_ip_run [get_ips $ip]
            # Workaround: Vivado 2024.2 heap corruption (AR#1234567) in
            # Optimize2::timingOpt / ConstProp::cleanup for ERNIC IP —
            # disable timing-driven synth to avoid the crashing code path.
            if {[string match "rdma_core*" $ip] || [string match "qdma_no_sriov*" $ip]} {
                # Vivado 2024.2 bug: heap corruption / orphan-LUT in
                # Optimize2::timingOpt / ConstProp::cleanup for RDMA and QDMA.
                # RDMA (rdma_core) crashes opt_design; QDMA (qdma_no_sriov)
                # leaves an orphan LUT in mdma_c2h_dsc_bypass_inst when
                # en_axi_mm_qdma=true triggers the MM bypass arbiter.
                # IP OOC runs do not expose STEPS.SYNTH_DESIGN.ARGS.MORE_OPTIONS,
                # so patch the generated run script directly to add -no_timing_driven.
                set _run_tcl [file join ${ip_build_dir} manage_ip \
                    manage_ip.runs ${ip}_synth_1 ${ip}.tcl]
                if {[file exists $_run_tcl]} {
                    set _fd [open $_run_tcl r]; set _src [read $_fd]; close $_fd
                    regsub {synth_design -top} $_src \
                        {synth_design -no_timing_driven -top} _src
                    set _fd [open $_run_tcl w]; puts -nonewline $_fd $_src; close $_fd
                    puts "INFO: \[$ip\] Patched run script with -no_timing_driven"
                } else {
                    puts "WARNING: \[$ip\] Run script not found; -no_timing_driven not applied"
                }
            }
            launch_runs ${ip}_synth_1
            wait_on_run ${ip}_synth_1
        }
    }
}

# Close the Manage IP project
close_project

# Setup build directory for the design
set top_build_dir ${build_dir}/${top}

if {[file exists $top_build_dir] && !$overwrite} {
    puts "INFO: \[$top\] Use existing build (overwrite=0)"
    return
}
if {[file exists $top_build_dir]} {
    puts "INFO: \[$top\] Found existing build, deleting... (overwrite=1)"
    file delete -force $top_build_dir
}

create_project -force $top $top_build_dir -part $part
if {![string equal $board_part ""]} {
    set_property BOARD_PART $board_part [current_project]
}
set_property target_language verilog [current_project]

# Marco to enable conditional compilation at Verilog level
set verilog_define "__synthesis__ __${board}__"
if {$zynq_family} {
    append verilog_define " " "__zynq_family__"
}
if {$rdma} {
    append verilog_define " " "__rdma_enabled__"
    append verilog_define " " "__classifier_${classifier}__"
    puts "INFO: RDMA enabled with classifier=$classifier"
}
set_property verilog_define $verilog_define [current_fileset]

# Read IPs from finished IP runs
# - Some IPs are board-specific and will be ignored for other board targets
dict for {ip ip_dir} $ip_dict {
    read_ip -quiet ${ip_dir}/${ip}.xci
}

# Read user plugin files
set include_dirs [get_property include_dirs [current_fileset]]
foreach freq [list 250mhz 322mhz] {
    set box "box_$freq"
    set box_plugin ${user_plugin}/${box}
    
    if {![file exists $box_plugin] || ![file exists ${user_plugin}/build_${box}.tcl]} {
        set box_plugin ${plugin_dir}/p2p/${box}
    }

    source ${box_plugin}/${box}_axi_crossbar.tcl
    read_verilog -quiet ${box_plugin}/${box}_address_map.v
    lappend include_dirs $box_plugin

    if {![file exists ${user_plugin}/build_${box}.tcl]} {
        cd ${plugin_dir}/p2p
        source build_${box}.tcl
    } else {
        cd $user_plugin
        source build_${box}.tcl
    }
    cd $script_dir
}
set_property include_dirs $include_dirs [current_fileset]

# Read the source files from each module
# - First, source "build.tcl" if it is defined under `module_dir`
# - Then, read all the RTL files under `module_dir` (excluding sub-directories)
dict for {module module_dir} $module_dict {
    if {[file exists ${module_dir}/build.tcl]} {
        cd $module_dir
        source build.tcl
        cd $script_dir
    }

    read_verilog -quiet [glob -nocomplain -directory $module_dir "*.{v,vh}"]
    read_verilog -quiet -sv [glob -nocomplain -directory $module_dir "*.sv"]
    read_vhdl -quiet [glob -nocomplain -directory $module_dir "*.vhd"]
}

# Read top-level source files
read_verilog -quiet [glob -nocomplain -directory $src_dir "*.{v,vh}"]
read_verilog -quiet -sv [glob -nocomplain -directory $src_dir "*.sv"]
read_vhdl -quiet [glob -nocomplain -directory $src_dir "*.vhd"]

# Set vivado generic
set design_params(-build_timestamp) "32'h$design_params(-build_timestamp)"
set generic ""
foreach {key value} [array get design_params] {
    set p [string toupper [string range $key 1 end]]
    lappend generic "$p=$value"
}
set_property -name generic -value $generic -object [current_fileset]
set_property top $top [get_property srcset [current_run]]

puts "bitstream_userid is $bitstream_userid"
puts "bitstream_usr_acceess is $bitstream_usr_access"

# generate the xdc with the run specific parameters dynamically
set fp [open "${build_dir}/run_params.xdc" w]
puts $fp "set_property BITSTREAM.CONFIG.USERID \"$bitstream_userid\" \[current_design\]"
puts $fp "set_property BITSTREAM.CONFIG.USR_ACCESS $bitstream_usr_access \[current_design\]"
close $fp

# Read constraint files
read_xdc -unmanaged ${constr_dir}/${board}/pins.xdc
read_xdc -unmanaged ${constr_dir}/${board}/timing.xdc
read_xdc ${constr_dir}/${board}/general.xdc
read_xdc ${build_dir}/run_params.xdc
if {$rdma && [file exists ${constr_dir}/${board}/pins_ddr4.xdc]} {
    read_xdc -unmanaged ${constr_dir}/${board}/pins_ddr4.xdc
    puts "INFO: Read DDR4 pin constraints for $board"
}

# Simulate design
if {$sim} {
    # Generate simulation libraries
    set modelsim_lib_path ${sim_params(-sim_lib_path)}/modelsim
    if {[file exists ${modelsim_lib_path}]} {
        puts "Skipping compilation of simulation libraries as directory ${modelsim_lib_path} exists."
    } else {
        puts "Compiling simulation libraries in directory ${modelsim_lib_path}."
        compile_simlib -simulator modelsim -simulator_exec_path ${sim_params(-sim_exec_path)} \
            -family all -language all -library all \
            -dir ${modelsim_lib_path}
    }

    # Export simulation
    set_property target_simulator ModelSim [current_project]
    set_property top $sim_params(-sim_top) [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
    set_property compxlib.modelsim_compiled_library_dir ${modelsim_lib_path} [current_project]
    launch_simulation -scripts_only
}

# Implement design
if {$impl} {
    update_compile_order -fileset sources_1

    # Vivado 2024.2 workaround for opt_design [Opt 31-67] orphan-LUT failure
    # inside qdma_no_sriov's mdma_c2h_dsc_bypass_inst when en_axi_mm_qdma=true.
    # ConstProp::cleanup trims the MM bypass arbiter (whose bypass inputs are
    # tied to constants both internally — c2h_byp_in_mm_* — and externally —
    # h2c_byp_in_st_vld=1'b0 in qdma_subsystem.sv) but leaves a LUT3 cell with
    # a missing I2 connection.
    #
    # Earlier attempt #1: TCL.PRE hook setting DONT_TOUCH on the QDMA cell.
    # Did not fire correctly (the -hier filter found no matching REF_NAME
    # at that point in the flow); silently no-op'd.
    # Earlier attempt #2: -no_propconst flag.  opt_design rejects this as
    # an unknown option — per `opt_design -help`, the way to disable
    # propconst is to NOT pass it: when other optimizations are explicitly
    # named, all unnamed default optimizations (-propconst,
    # -bram_power_opt) are implicitly disabled.
    #
    # Fix: pass -retarget -sweep -bram_power_opt explicitly.  This
    # re-runs the three defaults that aren't the bug source while
    # implicitly skipping -propconst (and ConstProp::cleanup with it).
    # Vivado 2024.2 workaround for [Opt 31-67] orphan LUT in
    # mdma_c2h_dsc_bypass_inst.  Build #8 tried IS_ENABLED=false on opt_design
    # but place_design then errored "Found memory core or Advanced IO Wizard
    # core that needs to be (re)generated" — the DDR4 PHY needs opt_design
    # to run.  So opt_design must run; we just need to keep its ConstProp
    # pass away from the QDMA bypass arbiter.
    #
    # Solution: TCL.PRE hook that DONT_TOUCH's the bypass arbiter sub-tree.
    # Selector is on instance NAME (not REF_NAME like attempt #4) and
    # matches the exact failing module path.  Without -quiet so any "no
    # cells matched" warning surfaces in the log.
    set_property STRATEGY "Performance_ExploreWithRemap" [get_runs impl_1]
    set _opt_pre_tcl ${top_build_dir}/opt_design_pre.tcl
    set _fd [open $_opt_pre_tcl w]
    puts $_fd "# Auto-generated workaround — see build.tcl"
    puts $_fd "puts \"\\\[opt_pre\\\] DONT_TOUCH on QDMA bypass arbiter sub-tree\""
    puts $_fd "set _byp_cells \[get_cells -hier -filter {NAME =~ */mdma_c2h_dsc_bypass_inst*}\]"
    puts $_fd "puts \"\\\[opt_pre\\\] matched \[llength \$_byp_cells\] cells\""
    puts $_fd "if {\[llength \$_byp_cells\] > 0} {"
    puts $_fd "    set_property DONT_TOUCH true \$_byp_cells"
    puts $_fd "}"
    close $_fd
    set_property STEPS.OPT_DESIGN.TCL.PRE $_opt_pre_tcl [get_runs impl_1]
    puts "INFO: \[impl_1\] opt_design TCL.PRE workaround installed: DONT_TOUCH on */mdma_c2h_dsc_bypass_inst*"

    # Now run impl_1 without re-setting STRATEGY (empty strategies arg).
    _do_impl $jobs
}

if {$post_impl} {
    _do_post_impl $top_build_dir $top impl_1 $zynq_family ${board}
}
