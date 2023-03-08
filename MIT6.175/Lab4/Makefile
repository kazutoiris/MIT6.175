all: compile conflict pipeline bypass cfnc cf

compile:
	mkdir -p buildDir
	bsc -u -sim -bdir buildDir -info-dir buildDir -simdir buildDir -vdir buildDir -aggressive-conditions -keep-fires TestBench.bsv

conflict: compile
	bsc -sim -e mkTbConflictFunctional -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simConflictFunctional

pipeline: compile
	bsc -sim -e mkTbPipelineFunctional -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simPipelineFunctional
	bsc -sim -e mkTbPipelineScheduling -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simPipelineScheduling

bypass: compile
	bsc -sim -e mkTbBypassFunctional -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simBypassFunctional
	bsc -sim -e mkTbBypassScheduling -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simBypassScheduling

cfnc: compile
	bsc -sim -e mkTbCFNCFunctional -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simCFNCFunctional
	bsc -sim -e mkTbCFNCScheduling -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simCFNCScheduling

cf: compile
	bsc -sim -e mkTbCFFunctional -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simCFFunctional
	bsc -sim -e mkTbCFScheduling -bdir buildDir -info-dir buildDir -simdir buildDir -aggressive-conditions -keep-fires -o simCFScheduling

clean:
	rm -rf buildDir sim*

.PHONY: clean all compile conflict pipeline bypass cfnc cf
.DEFAULT_GOAL := all
