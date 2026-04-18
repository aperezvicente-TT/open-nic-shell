# Elaboration-only sanity check for Tier 1b RTL graft.
# Opens the ipcheck project and runs synth_design -rtl (elab only, no synth).
open_project /home/alex/mpi-shfs/fpga/open-nic-shell/build/au200_2cmac_2pf_rdma_v2_ipcheck/open_nic_shell/open_nic_shell.xpr
set_param general.maxThreads 8
synth_design -rtl -name rtl_elab -top open_nic_shell -part xcu200-fsgd2104-2-e
puts "ELAB_CHECK_OK"
close_project
