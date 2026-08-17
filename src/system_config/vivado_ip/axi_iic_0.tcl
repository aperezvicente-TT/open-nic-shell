# *************************************************************************
# AXI IIC master -- QSFP module management (DOM) on boards without CMS.
#
# WHY THIS EXISTS
# ---------------
# On Alveo cards the Card Management Subsystem owns the board I2C bus and reads
# QSFP module diagnostics for you.  The VCU1525 targets a bare xcvu9p part, where
# cms_subsystem is not an available IP (see vivado_ip.tcl), so the shell drives
# the bus itself.
#
# BUS TOPOLOGY (VCU1525 / Alveo U200, UG1268)
# -------------------------------------------
# There is ONE shared board I2C bus reaching the FPGA -- i2c_scl (BF20) and
# i2c_sda (BF17) -- not a bus per cage.  QSFPn_MODSELL is the chip select: drive
# the wanted cage's ModSelL LOW (and the other HIGH) before addressing the module
# at I2C address 0x50.  Cross-checked against corundum fpga_au200.xdc, which
# exposes exactly these two pins and no per-cage I2C.
#
# WHAT THE DRIVER CAN THEN READ (SFF-8636 page 0, addr 0x50)
#   bytes 22-23  module temperature (signed, 1/256 degC)
#   bytes 26-27  supply voltage (100 uV units)
#   bytes 34-41  per-lane RX optical power
#   bytes 148+   vendor name / part number / serial
#
# PARAMETER NAMES ARE NOT WHAT YOU EXPECT.  Verified by creating the IP in memory
# and dumping its CONFIG.* properties -- the frequency knob is IIC_FREQ_KHZ, NOT
# C_IIC_FREQ_KHZ, and the addressing knob is TEN_BIT_ADR taking the string
# "7_bit", NOT a boolean C_TEN_BIT_ADR.  Guessing these produces
# "Cannot find parameter" / "is not configurable" errors.
#
# AXI_ACLK_FREQ_MHZ MUST match the real clock or SCL comes out at the wrong rate:
# this instance is clocked by cms_clk, which system_config.sv generates at 50 MHz
# (clk_wiz_50Mhz: 125 MHz in -> 50 MHz out).  The IP default is 25.
#
# 100 kHz: SFF-8636 requires 400 kHz support but guarantees 100 kHz, and DOM
# polling is not rate-sensitive.  Start slow and reliable.
#
# NOTE: no '#' comments inside the set_property -dict braces below.  Tcl has no
# comments inside a braced list, so each word becomes a bogus property.
# *************************************************************************
set axi_iic axi_iic_0

create_ip -name axi_iic -vendor xilinx.com -library ip -module_name $axi_iic -dir ${ip_build_dir}

set_property -dict {
    CONFIG.IIC_FREQ_KHZ {100}
    CONFIG.TEN_BIT_ADR {7_bit}
    CONFIG.AXI_ACLK_FREQ_MHZ {50}
    CONFIG.C_GPO_WIDTH {2}
    CONFIG.C_SCL_INERTIAL_DELAY {5}
    CONFIG.C_SDA_INERTIAL_DELAY {5}
    CONFIG.C_SDA_LEVEL {1}
    CONFIG.IIC_BOARD_INTERFACE {Custom}
    CONFIG.USE_BOARD_FLOW {false}
} [get_ips $axi_iic]
