#!/bin/bash

asm_tests=(
	median
	multiply
	qsort
	towers
	vvadd
	)

vmh_dir=programs/build/benchmarks/vmh
log_dir=logs
wait_time=3

# create bsim log dir
mkdir -p ${log_dir}

# run each test
for test_name in ${asm_tests[@]}; do
	echo "-- benchmark test: ${test_name} --"
	# copy vmh file
	mem_file=${vmh_dir}/${test_name}.riscv.vmh
	if [ ! -f $mem_file ]; then
		echo "ERROR: $mem_file does not exit, you need to first compile"
		exit
	fi
	cp ${mem_file} bluesim/mem.vmh 

	# run test
	make run.bluesim > ${log_dir}/${test_name}.log & # run bsim, redirect outputs to log
	sleep ${wait_time} # wait for bsim to setup
done
