#!/bin/bash

vmh_dir=programs/build/excep/bin
log_dir=bluesim/logs
wait_time=1

# create bsim log dir
mkdir -p ${log_dir}

# kill previous bsim if any
pkill ubuntu.exe
pkill bsim
# run test
test_name="permission"
echo "-- benchmark test: ${test_name} --"
# copy vmh file
mem_file=${vmh_dir}/${test_name}.riscv
if [ ! -f $mem_file ]; then
	echo "ERROR: $mem_file does not exit, you need to first compile"
	exit
fi
cp ${mem_file} bluesim/program

# run test
make run.bluesim > ${log_dir}/${test_name}.log # run bsim, redirect outputs to log
sleep ${wait_time} # wait for bsim to setup
echo ""

pkill ubuntu.exe
pkill bsim
