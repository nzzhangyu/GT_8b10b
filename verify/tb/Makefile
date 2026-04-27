# defaults
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
WAVES ?= 1
LANE_NUM ?= 2

# Directory Definition
tb_list	= $(abspath ../../verify/tb)
pkg_list = $(abspath ../../design/pkg)
rtl_list = $(abspath ../../design/rtl)
tb_files = $(rtl_list)/$(tc).sv
sim_ip_list = $(abspath ../ip)
include_list = $(abspath ../../design/incl)

# Cocotb Config
ctb ?= test_axi2gi
tc  ?= tb_gt_8b10b_top
TOPLEVEL = $(tc)
MODULE = $(ctb)
export PYTHONPATH := $(PYTHONPATH):$(PWD)/..:$(PWD)/../tb

# Verilator Compilation Options
# --trace: Enable waveform tracing (VCD format)
# --trace-fst: Enable more efficient FST waveform format (recommended for large projects)
# -Wno-fatal: Do not treat warnings as fatal errors
# --bbox-sys: Handle/Blackbox system task calls
EXTRA_ARGS += --trace-fst --trace-structs -Wno-fatal --bbox-sys
EXTRA_ARGS += +incdir+${include_list}
EXTRA_ARGS += -GLANE_NUM=$(LANE_NUM)

# File list processing
# Ensure Packages are parsed prior to Design modules for dependency resolution.
VERILOG_SOURCES += $(shell cat ./filelist.f 2>/dev/null)
# VERILOG_SOURCES += $(abspath ../../design/rtl)/$(tc).sv
VERILOG_SOURCES += $(wildcard $(abspath ../../design/rtl)/*.v)
VERILOG_SOURCES += $(wildcard $(abspath ../../design/rtl)/*.sv)

run:
	$(MAKE) sim 2>&1 | tee sim_output.log

# Include standard Cocotb simulation rules
include $(shell cocotb-config --makefiles)/Makefile.sim

mklist:
	rm -rf ./filelist.f
	touch ./filelist.f
	find $(pkg_list) -type f \( -name "*.v" -o -name "*.sv" \) >> filelist.f
	find $(rtl_list) -type f \( -name "*.v" -o -name "*.sv" \) >> filelist.f
	find $(sim_ip_list) -type f \( -name "*.v" -o -name "*.sv" \) >> filelist.f

clean_all:
	rm -rf sim_build
	rm -f *.vcd *.fst *.xml
	rm -f ./filelist.f
	find . -name "__pycache__" | xargs rm -rf