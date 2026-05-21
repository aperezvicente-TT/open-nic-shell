SIM             ?= verilator
TOPLEVEL_LANG    = verilog

# Use the system Python that has cocotb+pygpi installed.
PYTHON_BIN      ?= /usr/bin/python3

# DUT sources (order matters: dependencies before tb_top).
VERILOG_SOURCES  = $(abspath ../rdma_regs.sv)
VERILOG_SOURCES += $(abspath ../rdma_rx_classifier.sv)
VERILOG_SOURCES += $(abspath ../rdma_hdr_parser.sv)
VERILOG_SOURCES += $(abspath ../rdma_rx_ring.sv)
VERILOG_SOURCES += $(abspath ../tt_rdma_v1_endpoint_250mhz.sv)
VERILOG_SOURCES += $(abspath tb_top.sv)

TOPLEVEL  = tb_top
MODULE   ?= test_passthrough

# Verilator flags
COMPILE_ARGS += --timing
COMPILE_ARGS += --trace-fst --trace-structs
COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: waves
waves:
	gtkwave wave.fst &
