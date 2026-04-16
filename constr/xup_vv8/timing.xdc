# *************************************************************************
# BittWare XUP-VV8 (VU13P) timing / placement constraints for OpenNIC shell.
# *************************************************************************
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_p]

set_false_path -through [get_ports pcie_rstn]

# Async CDC bounds between QDMA 250MHz AXI-stream and CMAC 322.265625 MHz
foreach axis_aclk [get_clocks -of_object [get_nets axis_aclk*]] {
    foreach cmac_clk [get_clocks -of_object [get_nets cmac_clk*]] {
        set_max_delay -datapath_only -from $axis_aclk -to $cmac_clk 4.000
        set_max_delay -datapath_only -from $cmac_clk -to $axis_aclk 3.103
    }
}

# Keep QDMA, CMAC and packet adapters in SLR=1 with the PCIe and QSFP-DD 3
# hard IP so the data path does not have to cross SLR boundaries.
create_pblock pblock_qdma_subsystem
add_cells_to_pblock [get_pblocks pblock_qdma_subsystem] [get_cells -quiet {qdma_if*.qdma_subsystem_inst}]
resize_pblock [get_pblocks pblock_qdma_subsystem] -add {SLR1}

create_pblock pblock_cmac_subsystem
add_cells_to_pblock [get_pblocks pblock_cmac_subsystem] [get_cells -quiet {cmac_port*.cmac_subsystem_inst}]
resize_pblock [get_pblocks pblock_cmac_subsystem] -add {SLR1}
