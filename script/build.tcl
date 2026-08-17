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
# Apply threading settings to a run.  Two mechanisms are needed because each run
# executes in its own Vivado process:
#  - general.maxThreads is a session parameter, so it is injected through a
#    TCL.PRE hook on the run's first step (all steps of a run share one process).
#  - -ultrathreads is a command option, passed via "MORE OPTIONS" on the
#    place/route steps.  It spreads maxThreads across the device's SLRs and is
#    supported on UltraScale+ SSI parts only (xcu200 = VU9P, 3 SLRs).  Note it
#    makes placement non-reproducible run to run.
proc _set_run_threading {run first_step pre_tcl max_threads ultrathreads} {
    if {$max_threads > 0} {
        set_property STEPS.${first_step}.TCL.PRE $pre_tcl [get_runs $run]
    }
    if {$ultrathreads} {
        foreach step {PLACE_DESIGN ROUTE_DESIGN} {
            set_property -name "STEPS.${step}.ARGS.MORE OPTIONS" -value {-ultrathreads} \
                -objects [get_runs $run]
        }
    }
}

proc _do_impl {jobs {strategies ""} {to_step write_bitstream} {max_threads 0} {ultrathreads 0} {pre_tcl ""}} {
    if {![llength $strategies]} {
        _set_run_threading impl_1 OPT_DESIGN $pre_tcl $max_threads $ultrathreads
        launch_runs impl_1 -to_step $to_step -jobs $jobs
        if {[catch {wait_on_run impl_1} e]} {
            puts "WARNING: \[Impl\] impl_1 reported a failure while waiting: $e"
        }
    } else {
        set impl_runs "impl_1"
        set_property STRATEGY "[lindex $strategies 0]" [get_runs impl_1]
        for {set i 1} {$i < [llength $strategies]} {incr i 1} {
            set r impl_[expr $i + 1]
            set s [lindex $strategies $i]
            create_run $r -flow {Vivado Implementation 2020} -parent_run synth_1 -strategy "$s"
            lappend impl_runs $r
        }
        foreach r $impl_runs {
            _set_run_threading $r OPT_DESIGN $pre_tcl $max_threads $ultrathreads
        }
        launch_runs $impl_runs -to_step $to_step -jobs $jobs
        # wait_on_run raises a Tcl error when a run fails, which would abandon the
        # remaining strategies and skip the comparison summary.  Collect instead.
        foreach r $impl_runs {
            if {[catch {wait_on_run $r} e]} {
                puts "WARNING: \[Impl\] $r reported a failure while waiting: $e"
            }
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
#   impl_to_step           Last implementation step to run (default write_bitstream).
#                          Use post_route_phys_opt_design to stop before bitstream
#                          generation, e.g. when the CMAC IP only has a
#                          Design_Linking license.
#   max_threads            Value for "set_param general.maxThreads" inside every
#                          synthesis/implementation run (1-32 on 2024.2; the Linux
#                          default is 8).  0 leaves the tool default alone.  Each
#                          step still applies its own internal cap (8 for place,
#                          route, phys_opt, DRC and STA) unless ultrathreads is on.
#   ultrathreads           Pass -ultrathreads to place_design and route_design.
#                          Spreads max_threads across the SLRs of an UltraScale+
#                          SSI part, which is the only way past the per-step cap.
#                          Trades away run-to-run reproducibility of placement.
#   impl_strategies        Tcl list of implementation strategies.  More than one
#                          creates impl_2..impl_N off the same synth_1 and runs
#                          them concurrently (-jobs), so a strategy sweep costs
#                          little extra wall clock on a many-core host.  Note each
#                          concurrent run needs its own ~20-30 GB of RAM.
#   pcie_gen4x8            Build the QDMA endpoint as Gen4 x8 (edge lanes 0-7)
#                          instead of the board default Gen3 x16.  Same raw
#                          bandwidth (128 Gb/s), half the lanes, so it is the
#                          right choice in a slot bifurcated x8x8 or one that
#                          only trains 8 lanes.  au50 only for now: the board
#                          file must define a pci_express_x8 interface whose
#                          refclk is within 2 GT quads of lanes 0-7, and the
#                          shell must narrow pcie_rxp/txp under the matching
#                          macro.  Emits `__au50_gen4x8__`.
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
#   flow_ctrl_en       Pause GENERATION: per-CMAC RX fill drives that CMAC's
#                      ctl_tx_pause_req, so receive overload backpressures the
#                      sender instead of discarding (docs Ch. 13 §13.4).  0 = the
#                      historical behaviour, and verified to synthesise to zero
#                      logic.
#   flow_ctrl_react_en Pause REACTION: honour a pause frame the peer sends us
#                      (docs Ch. 13 §13.3.1).  Enable SEPARATELY from
#                      flow_ctrl_en and test alone: the path is unexercised and
#                      this CMAC config exposes no ctl_rx_pause_ack, so a
#                      latching level would stall that port's TX until the
#                      watchdog fires.
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
    -impl_to_step write_bitstream
    -impl_strategies "Vivado Implementation Defaults"
    -max_threads 0
    -ultrathreads 0
    -post_impl   0
    -user_plugin ""
    -bitstream_userid  "0xDEADC0DE"
    -bitstream_usr_access "0x66669999"
    -pcie_gen4x8 0
    -sim  0
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
    -flow_ctrl_en       0
    -flow_ctrl_react_en 0
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
# -pcie_gen4x8 needs three things per board: a pci_express_x8 board interface,
# a refclk legal for lanes 0-7, and a shell macro that narrows pcie_rxp/txp.
# Only au50 has all three today, so refuse anywhere else rather than build a
# 16-lane top level against an 8-lane endpoint.
if {$pcie_gen4x8 && $board ne "au50"} {
    puts "Invalid value for -pcie_gen4x8: only supported on -board au50 (got $board)"
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

# Pre-step hook used to raise the thread limit inside each run's own process
set threading_pre_tcl ${build_dir}/set_max_threads.tcl
if {$max_threads > 0} {
    set fp [open $threading_pre_tcl w]
    puts $fp "# Generated by build.tcl -- raises the per-run thread limit"
    puts $fp "set_param general.maxThreads ${max_threads}"
    puts $fp "puts \"INFO: \\\[Threading\\\] general.maxThreads = \[get_param general.maxThreads\]\""
    close $fp
    puts "INFO: \[Threading\] max_threads=${max_threads} ultrathreads=${ultrathreads} (hook: ${threading_pre_tcl})"
}

# Update the board store
if {[string equal $board_repo ""]} {
    set_param board.repoPaths "${root_dir}/board_files"    
    # xhub::refresh_catalog [xhub::get_xstores xilinx_board_store]
} else {
    set_param board.repoPaths $board_repo
}

# Enumerate modules
foreach name [glob -tails -directory ${src_dir} -type d *] {
    if {![string equal $name "shell"]} {
        dict append module_dict $name "${src_dir}/${name}"
    }
}

# Create/open Manage IP project
set ip_build_dir ${build_dir}/vivado_ip

# "overwrite" means every IP is rebuilt, so drop the whole IP build directory --
# Manage IP project included.  Deleting only the per-IP directories leaves their
# .xci registered in the project and create_ip then fails with "IP name '<ip>' is
# already in use in this project" (the manual "rm -rf" the build guide calls for).
if {$overwrite && [file exists $ip_build_dir]} {
    puts "INFO: \[Manage IP\] overwrite=1: deleting ${ip_build_dir}"
    file delete -force $ip_build_dir
}

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
#
# The OOC IP synthesis runs are mutually independent, so they are all created
# first and then launched together with "-jobs $jobs".  Waiting on each run
# individually inside the loop (the original behaviour) serialized the whole IP
# stage onto one core regardless of "-jobs".
set ip_synth_runs {}
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
            # Deleting only the directory leaves the .xci registered in the Manage
            # IP project, so the create_ip below fails with "IP name '$ip' is
            # already in use".  Unregister it first.
            if {![string equal [get_ips -quiet $ip] ""]} {
                # Work off the IP object, not a path: with the directory already
                # gone the .xci is still a project record but no longer on disk
                catch {export_ip_user_files -of_objects [get_ips $ip] -no_script -reset -force -quiet}
                catch {remove_files -quiet [get_property IP_FILE [get_ips $ip]]}
            }
            file delete -force ${ip_build_dir}/${ip}
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

        # Create the out-of-context IP synthesis run; launched in parallel below
        if {$synth_ip} {
            create_ip_run [get_ips $ip]
            lappend ip_synth_runs ${ip}_synth_1
        }
    }
}

# Launch all pending IP synthesis runs concurrently, then wait for all of them
if {[llength $ip_synth_runs]} {
    puts "INFO: \[Manage IP\] Launching [llength $ip_synth_runs] IP synthesis run(s) with -jobs $jobs"
    launch_runs $ip_synth_runs -jobs $jobs
    foreach r $ip_synth_runs {
        wait_on_run $r
    }
    foreach r $ip_synth_runs {
        set st [get_property STATUS [get_runs $r]]
        set pr [get_property PROGRESS [get_runs $r]]
        puts "INFO: \[Manage IP\] $r: $st ($pr)"
        if {![string equal $pr "100%"]} {
            puts "ERROR: \[Manage IP\] $r did not complete ($st)"
            exit 1
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
# au55n / Varium C1100 bifurcated x8x8: two QDMA endpoints on ONE x16 edge
# connector, so the lane budget is 8 per endpoint (not 16) and the single PERST
# pin is shared.  That shape differs from every other target, hence its own
# macro.  Gated on board AND num_qdma, so no other board and no 1-QDMA au55n
# build can see it.  See docs/au55n-2qdma-gen4x8-design.md.
if {$board eq "au55n" && $num_qdma == 2} {
    append verilog_define " " "__au55n_dual_x8__"
}
# au50 / Alveo U50 Gen4 x8: one QDMA endpoint on edge lanes 0..7 only, so the
# lane budget is 8 rather than 16.  Same 128 Gb/s as the stock Gen3 x16 build.
# Gated on board AND the option, so the default Gen3 x16 au50 target is
# untouched.  See docs/au50-1cmac-1pf-gen4x8.md.
if {$board eq "au50" && $pcie_gen4x8} {
    append verilog_define " " "__au50_gen4x8__"
}
# vcu1525: the VCU1525 and the Alveo U200 are the same board design (UG1268) --
# identical PCIe refclk (AM11/AM10) and PERST (BD21), identical status LEDs
# (BC21/BB21/BA20), identical QSFP sidebands and MSP432 satellite pins.  Emit
# __au200__ as well so every `ifdef __au200__ branch in the RTL (top-level ports,
# system_config CMS/satellite handling, gpio_led logic) applies unchanged instead
# of being duplicated for a second name.  The genuine board differences are NOT
# in RTL and are handled where they belong:
#   - QSFP refclks on MGTREFCLK1 (K11/K10, P11/P10)  -> constr/vcu1525/pins.xdc
#   - 161.1328125 MHz refclk, no *_BOARD_INTERFACE   -> *_vcu1525 IP tcls
if {$board eq "vcu1525"} {
    append verilog_define " " "__au200__"
    # Make the three status LEDs actually work.  open_nic_shell.sv has a complete
    # LED block (LED0 = heartbeat, LED1/LED2 = per-CMAC link with activity blink)
    # but it is guarded by `__gpio_led__, which NOTHING in this repo ever defines
    # -- so on au200/au250 the gpio_led[2:0] output is left completely undriven
    # and the LEDs are dark.  Defining it here lights them on vcu1525.
    # (au200/au250 have the same dead-code bug; not changing them unasked.)
    append verilog_define " " "__gpio_led__"
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

    # Top-level synthesis runs as part of the implementation launch, so give it the
    # raised thread limit too (synth_design has its own internal cap)
    if {$max_threads > 0 && [llength [get_runs -quiet synth_1]]} {
        set_property STEPS.SYNTH_DESIGN.TCL.PRE $threading_pre_tcl [get_runs synth_1]
    }

    _do_impl $jobs $impl_strategies $impl_to_step $max_threads $ultrathreads $threading_pre_tcl

    # Summarize every implementation run so a strategy sweep can be compared at a
    # glance (WNS/TNS/WHS are only populated once the run has been routed)
    puts "INFO: \[Impl\] ==== implementation run summary ===="
    foreach r [lsort [get_runs impl_*]] {
        puts [format "INFO: \[Impl\] %-8s %-42s %-12s %-6s WNS=%s TNS=%s WHS=%s" \
            $r \
            [get_property STRATEGY [get_runs $r]] \
            [get_property PROGRESS [get_runs $r]] \
            [get_property STATUS   [get_runs $r]] \
            [get_property STATS.WNS [get_runs $r]] \
            [get_property STATS.TNS [get_runs $r]] \
            [get_property STATS.WHS [get_runs $r]]]
    }
}

if {$post_impl} {
    # Pick the run to turn into a flash image.  With a strategy sweep, impl_1 is
    # just the first strategy, not necessarily the one that closed timing -- so
    # prefer the run with the best WNS among those that produced a bitstream.
    set best_run ""
    set best_wns ""
    foreach r [lsort [get_runs -quiet impl_*]] {
        if {![file exists ${top_build_dir}/${top}.runs/${r}/${top}.bit]} {
            continue
        }
        set w [get_property STATS.WNS [get_runs $r]]
        if {[string equal $w ""]} {
            continue
        }
        if {[string equal $best_wns ""] || $w > $best_wns} {
            set best_wns $w
            set best_run $r
        }
    }

    if {$zynq_family} {
        _do_post_impl $top_build_dir $top impl_1 $zynq_family ${board}
    } elseif {![string equal $best_run ""]} {
        puts "INFO: \[Post-impl\] Using $best_run for write_cfgmem (WNS=$best_wns)"
        if {$best_wns < 0} {
            puts "CRITICAL WARNING: \[Post-impl\] $best_run has negative WNS ($best_wns);\
                  the resulting .mcs is functional but not timing-clean"
        }
        _do_post_impl $top_build_dir $top $best_run $zynq_family ${board}
    } else {
        puts "WARNING: \[Post-impl\] no implementation run produced a bitstream;\
              skipping write_cfgmem"
    }
}
