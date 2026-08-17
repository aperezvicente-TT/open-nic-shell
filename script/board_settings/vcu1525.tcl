# VCU1525 (Virtex UltraScale+ FPGA VCU1525 Reconfigurable Acceleration Platform).
#
# Same board design as the Alveo U200 (UG1268): identical PCIe refclk (AM11/AM10),
# PCIe PERST (BD21), status LEDs (BC21/BB21/BA20) and QSFP sidebands.  Two things
# differ and are handled in constr/vcu1525/pins.xdc and the cmac_usplus_*_vcu1525
# IP tcls:
#   1. QSFP refclks land on MGTREFCLK1 of each quad (K11/K10 quad 231,
#      P11/P10 quad 230) rather than the U200's MGTREFCLK0 (M11/M10, T11/T10).
#   2. The SI5335A frequency plan is FS-selected; this board is strapped for
#      161.1328125 MHz, not the U200's 156.25 MHz.
#
# board_part is deliberately EMPTY: Vivado 2024.2 ships no VCU1525 board file, so
# the design is targeted by part alone.  build.tcl already guards
# `set_property BOARD_PART` on a non-empty string.  Consequence: every IP config
# for this board must avoid *_BOARD_INTERFACE properties and set pins/refclks
# explicitly.
set part xcvu9p-fsgd2104-2L-e
set board_part ""
set zynq_family 0
