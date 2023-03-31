
src_dir=../../src

compile:
	mkdir -p buildDir
	bsc -u -sim \
		-bdir buildDir -info-dir buildDir -simdir buildDir -vdir buildDir \
		-p +:$(src_dir):$(src_dir)/includes \
		-D CORE_NUM=2 \
		-aggressive-conditions -show-schedule Tb.bsv

tb: compile
	bsc -sim -e mkTb -bdir buildDir -info-dir buildDir -simdir buildDir -o simTb buildDir/*.ba

all: tb

clean:
	rm -rf buildDir sim*

.PHONY: compile clean tb
.DEFAULT_GOAL := all
