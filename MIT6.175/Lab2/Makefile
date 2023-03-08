compile:
	mkdir -p buildDir
	bsc -u -sim -bdir buildDir -info-dir buildDir -simdir buildDir -vdir buildDir -aggressive-conditions TestBench.bsv

fifo: compile
	bsc -sim -e mkTestBenchFifo -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simFifo
	./buildDir/simFifo

inelastic: compile
	bsc -sim -e mkTbFftInelasticPipeline -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simInelastic
	./buildDir/simInelastic

elastic: compile
	bsc -sim -e mkTbFftElasticPipeline -bdir buildDir -info-dir buildDir -simdir buildDir -o buildDir/simElastic
	./buildDir/simElastic

all: fifo inelastic elastic

clean:
	rm -rf buildDir sim*

.PHONY: clean all inelastic elastic fifo compile
.DEFAULT_GOAL := all
