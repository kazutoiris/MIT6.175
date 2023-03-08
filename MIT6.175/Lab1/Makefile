compile:
	mkdir -p buildDir
	bsc -u -sim -bdir buildDir -info-dir buildDir -simdir buildDir -vdir buildDir -aggressive-conditions TestBench.bsv

mux: compile
	bsc -sim -e mkTbMux -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simMux buildDir/*.ba
	./buildDir/simMux

muxsimple: compile
	bsc -sim -e mkTbMuxSimple -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simMuxSimple buildDir/*.ba
	./buildDir/simMuxSimple

rca: compile
	bsc -sim -e mkTbRCA -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simRca buildDir/*.ba
	./buildDir/simRca

rcasimple: compile
	bsc -sim -e mkTbRCASimple -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simRcaSimple buildDir/*.ba
	./buildDir/simRcaSimple

csa: compile
	bsc -sim -e mkTbCSA -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simCsa buildDir/*.ba
	./buildDir/simCsa

csasimple: compile
	bsc -sim -e mkTbCSASimple -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simCsaSimple buildDir/*.ba
	./buildDir/simCsaSimple

bs: compile
	bsc -sim -e mkTbBS -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simBs buildDir/*.ba
	./buildDir/simBs

all: mux muxsimple rca rcasimple csa csasimple bs

clean:
	rm -rf buildDir sim* *.vcd

.PHONY: clean all add compile
.DEFAULT_GOAL := all
