# *************************************************************************
#
# DDR4 constraints for Alveo U250
#
# The MIG IP uses the board interface (C0_DDR4_BOARD_INTERFACE = ddr4_sdram_c0)
# so physical pin assignments are inferred automatically from the board file.
# The constraints below handle MMCM placement and IO bank voltage references
# required for the DDR4 controller on AU250.
#
# *************************************************************************

# MMCM placement for DDR4 infrastructure clock
set_property LOC MMCM_X0Y2 [get_cells ddr4_inst/inst/u_ddr4_infrastructure/gen_mmcme4.u_mmcme_adv_inst]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_pins ddr4_inst/inst/u_ddr4_infrastructure/gen_mmcme4.u_mmcme_adv_inst/CLKIN1]

# Internal voltage reference for DDR4 IO banks
set_property INTERNAL_VREF 0.84 [get_iobanks 63]
set_property INTERNAL_VREF 0.84 [get_iobanks 62]
set_property INTERNAL_VREF 0.84 [get_iobanks 61]
