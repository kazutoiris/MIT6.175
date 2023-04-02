#!/bin/bash


bmarks_tests=(
	mc_print
	mc_hello
	mc_produce_consume
	mc_median
	mc_vvadd
	mc_multiply
	mc_dekker
	)

vmh_dir=programs/build/mc_bench/bin
log_dir=logs
wait_time=3

# create bsim log dir
mkdir -p ${log_dir}

# kill previous bsim if any
pkill ubuntu.exe
pkill bsim

# run each test
for test_name in ${bmarks_tests[@]}; do
	# copy vmh file
	mem_file=${vmh_dir}/${test_name}.riscv
	if [ ! -f $mem_file ]; then
		echo "ERROR: $mem_file does not exit, you need to first compile"
		exit
	fi
	cp ${mem_file} bluesim/program 

	# run test
    make run.bluesim > ${log_dir}/${test_name}.log  # run bsim, redirect outputs to log
	sleep ${wait_time} # wait for bsim to setup
    pkill ubuntu.exe
    pkill bsim
	echo ""
done
