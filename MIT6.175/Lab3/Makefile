testbenches=Dumb.tb FoldedMultiplier.tb SignedVsUnsigned.tb Ex3.tb Ex5.tb Ex7a.tb Ex7b.tb Ex9a.tb Ex9b.tb

compile:
	mkdir -p buildDir
	bsc -u -sim -bdir buildDir -info-dir buildDir -simdir buildDir -vdir buildDir -aggressive-conditions -keep-fires TestBench.bsv

%.tb: compile
	bsc -sim -e mkTb$(patsubst %.tb,%,$@) -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o buildDir/sim$(patsubst %.tb,%,$@) buildDir/*.ba
	./buildDir/sim$(patsubst %.tb,%,$@)

all: $(testbenches)

clean:
	rm -rf buildDir sim*

.PHONY: clean all add compile %.tb
.DEFAULT_GOAL := all
