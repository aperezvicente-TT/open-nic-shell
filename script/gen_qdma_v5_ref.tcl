# *************************************************************************
# gen_qdma_v5_ref.tcl
#
# Generate the soft QDMA v5.0 (EQDMA soft) DESCRIPTOR-BYPASS example design
# to obtain the PLAINTEXT, correct-IP reference RTL for the au200
# (xcu200, Virtex UltraScale+):
#   dsc_byp_h2c.sv  dsc_byp_c2h.sv  qdma_qsts.sv  qdma_app.sv
#
# Why this exists: the shell's qdma_subsystem_h2c_byp.sv was originally copied
# from the Versal *CPM5* example (wrong IP family). This regenerates the
# reference for the IP we actually build with (soft qdma_v5_x on UltraScale+),
# so the descriptor-bypass datapath + marker/qsts handshake can be diffed.
# See docs/12-sg-tx-bypass-implementation-plan.md §12.14.3 / §12.14.4.
#
# IP config below mirrors src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl
# (ST-only, Descriptor_bypass_and_internal). Vivado 2024.2 -> qdma_v5_0
# (this is the version the eth_1pf_2cmac bitstream is built with).
#
# Usage:
#   source /opt/amd/Vivado/2024.2/settings64.sh
#   vivado -mode batch -source script/gen_qdma_v5_ref.tcl [-tclargs <outdir> <part>]
#
# Output reference RTL:  <outdir>/exdes/qdma_no_sriov_ex/imports/dsc_byp_h2c.sv
# *************************************************************************

set outdir [expr {$argc >= 1 ? [lindex $argv 0] : "qdma_v5_ref"}]
set part   [expr {$argc >= 2 ? [lindex $argv 1] : "xcu200-fsgd2104-2-e"}]

create_project -force qdma_ref $outdir/proj -part $part
set qdma qdma_no_sriov
create_ip -name qdma -vendor xilinx.com -library ip -module_name $qdma
set_property -dict {
    CONFIG.mode_selection {Advanced}
    CONFIG.pl_link_cap_max_link_width {X16}
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s}
    CONFIG.dsc_byp_mode {Descriptor_bypass_and_internal}
    CONFIG.testname {st}
    CONFIG.dma_intf_sel_qdma {AXI_Stream_with_Completion}
    CONFIG.en_axi_mm_qdma {false}
    CONFIG.xlnx_ref_board {AU200}
} [get_ips $qdma]

generate_target all [get_ips $qdma]
open_example_project -force -in_process -dir $outdir/exdes [get_ips $qdma]

puts "==== DONE. reference RTL: ===="
foreach f [glob -nocomplain $outdir/exdes/qdma_no_sriov_ex/imports/dsc_byp_*.sv \
                            $outdir/exdes/qdma_no_sriov_ex/imports/qdma_qsts.sv] {
    puts "  $f"
}
