SIM             ?= verilator
TOPLEVEL_LANG    = verilog

# Use the system Python that has cocotb+pygpi installed,
# not the project venv which is missing these packages.
PYTHON_BIN      ?= /usr/bin/python3

# DUT sources (order matters: dependencies before tb_top)
VERILOG_SOURCES  = $(abspath ../udp_encap_tx.sv)
VERILOG_SOURCES += $(abspath ../udp_decap_rx.sv)
VERILOG_SOURCES += $(abspath tb_top.sv)

TOPLEVEL  = tb_top
MODULE    = test_encap_decap

# Verilator flags
COMPILE_ARGS += --timing
COMPILE_ARGS += --trace-fst --trace-structs
COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN

# FST waveform output
PLUSARGS += +dump_file=wave.fst

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves
waves:
	gtkwave wave.fst &
