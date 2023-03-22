#=======================================================================
# UCB CS250 Makefile fragment for benchmarks
#-----------------------------------------------------------------------
#
# Each benchmark directory should have its own fragment which
# essentially lists what the source files are and how to link them
# into an riscv and/or host executable. All variables should include
# the benchmark name as a prefix so that they are unique.
#

vvadd_c_src = \
	vvadd_main.c \
	syscalls.c \

vvadd_riscv_src = \
	crt.S \

vvadd_c_objs     = $(patsubst %.c, %.o, $(vvadd_c_src))
vvadd_riscv_objs = $(patsubst %.S, %.o, $(vvadd_riscv_src))

vvadd_host_bin = vvadd.host
$(vvadd_host_bin) : $(vvadd_c_src)
	$(HOST_COMP) $^ -o $(bmarks_build_bin_dir)/$(vvadd_host_bin)

vvadd_riscv_bin = vvadd.riscv
$(vvadd_riscv_bin) : $(vvadd_c_objs) $(vvadd_riscv_objs)
	cd $(bmarks_build_obj_dir); $(RISCV_LINK) $(vvadd_c_objs) $(vvadd_riscv_objs) -o $(bmarks_build_bin_dir)/$(vvadd_riscv_bin) $(RISCV_LINK_OPTS)

