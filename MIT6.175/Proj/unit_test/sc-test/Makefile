
src_dir := ../../src

core_num := 2 4
targets := $(addprefix tb_,$(core_num))

$(targets): tb_%:
	mkdir -p $(patsubst tb_%,buildDir_%,$@)
	bsc -u -sim \
		-bdir $(patsubst tb_%,buildDir_%,$@) -info-dir $(patsubst tb_%,buildDir_%,$@) \
		-simdir $(patsubst tb_%,buildDir_%,$@) -vdir $(patsubst tb_%,buildDir_%,$@) \
		-p +:$(src_dir):$(src_dir)/includes:$(src_dir)/ref \
		-D CORE_NUM=$(patsubst tb_%,%,$@) \
                +RTS -Ksize -RTS \
		-aggressive-conditions -show-schedule Tb.bsv
	bsc -sim -e mkTb \
		-bdir $(patsubst tb_%,buildDir_%,$@) -info-dir $(patsubst tb_%,buildDir_%,$@) \
		-simdir $(patsubst tb_%,buildDir_%,$@) \
                +RTS -Ksize -RTS \
		-o $(patsubst tb_%,simTb_%,$@) $(patsubst tb_%,buildDir_%,$@)/*.ba $(src_dir)/ref/mem.c

all: $(targets)

clean:
	rm -rf buildDir* sim* *.txt *.out

.PHONY: all clean $(targets)
.DEFAULT_GOAL := all
