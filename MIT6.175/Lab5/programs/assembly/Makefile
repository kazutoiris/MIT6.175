#=======================================================================
# Makefile for riscv-tests/isa
#-----------------------------------------------------------------------

asmdir := $(CURDIR)

asm_build_dir := $(asmdir)/../build/assembly
asm_build_bin_dir := $(asm_build_dir)/bin
asm_build_dump_dir := $(asm_build_dir)/dump
asm_build_vmh_dir := $(asm_build_dir)/vmh

default: all

#--------------------------------------------------------------------
# Sources
#--------------------------------------------------------------------
rv32ui_tests = \
	simple \
	add addi \
	and andi \
	auipc \
	beq bge bgeu blt bltu bne \
	j jal jalr \
	lw \
	lui \
	or ori \
	sw \
	sll slli \
	slt slti \
	sra srai \
	srl srli \
	sub \
	xor xori \
	bpred_bht bpred_j bpred_ras \
	cache \

#--------------------------------------------------------------------
# Build rules
#--------------------------------------------------------------------

RISCV_TOOL_DIR = /mit/6.175/rv32-gcc/bin
RISCV_PREFIX = $(RISCV_TOOL_DIR)/riscv32-unknown-elf
# gcc
RISCV_GCC = $(RISCV_PREFIX)-gcc
RISCV_GCC_OPTS = -m32 -static -fvisibility=hidden -nostdlib -nostartfiles -Wa,-march=RVI
incs := -I$(asmdir)/../env -I$(asmdir)/macros
# link
RISCV_LINK_OPTS = -T$(asmdir)/link.ld
# objdump
RISCV_OBJDUMP = $(RISCV_PREFIX)-objdump --disassemble --disassemble-zeroes --section=.text --section=.text.startup --section=.data
# convert to VMH: 64KB memory
RISCV_ELF2HEX = $(RISCV_TOOL_DIR)/elf2hex
VMH_WIDTH = 8
VMH_DEPTH = 65536

VPATH += $(asmdir)/src
VPATH += $(asmdir)/macros
VPATH += $(asm_build_bin_dir)
VPATH += $(asm_build_dump_dir)
VPATH += $(asm_build_vmh_dir)

#------------------------------------------------------------
# Build assembly tests

rv32ui_tests_bin  = $(addsuffix .riscv, $(rv32ui_tests))
rv32ui_tests_dump = $(addsuffix .riscv.dump, $(rv32ui_tests))
rv32ui_tests_vmh = $(addsuffix .riscv.vmh, $(rv32ui_tests))

$(rv32ui_tests_bin): %.riscv: %.S
	$(RISCV_GCC) $(RISCV_GCC_OPTS) $(incs) $(RISCV_LINK_OPTS) $< -o $(asm_build_bin_dir)/$@

$(rv32ui_tests_vmh): %.riscv.vmh: %.riscv
	@echo $(basename $<)
	@echo "@0" > $(asm_build_vmh_dir)/temp
	$(RISCV_ELF2HEX) $(VMH_WIDTH) $(VMH_DEPTH) $(asm_build_bin_dir)/$< >> $(asm_build_vmh_dir)/temp
	python $(asmdir)/../trans_vmh.py $(asm_build_vmh_dir)/temp $(asm_build_vmh_dir)/$@

$(rv32ui_tests_dump): %.riscv.dump: %.riscv
	$(RISCV_OBJDUMP) $(asm_build_bin_dir)/$< > $(asm_build_dump_dir)/$@

#------------------------------------------------------------
# Default
$(asm_build_bin_dir):
	mkdir -p $@

$(asm_build_obj_dir):
	mkdir -p $@

$(asm_build_dump_dir):
	mkdir -p $@

$(asm_build_vmh_dir):
	mkdir -p $@


all: $(asm_build_bin_dir) $(asm_build_obj_dir) $(asm_build_dump_dir) $(asm_build_vmh_dir) $(rv32ui_tests_dump) $(rv32ui_tests_vmh)


#------------------------------------------------------------
# Clean up

clean:
	rm -rf $(asm_build_dir)


.PHONY: all clean


