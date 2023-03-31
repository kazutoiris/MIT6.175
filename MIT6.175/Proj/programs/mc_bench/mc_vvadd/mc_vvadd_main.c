//**************************************************************************
// Vector-vector add benchmark
//--------------------------------------------------------------------------
//
// This benchmark uses adds to vectors and writes the results to a
// third vector. The input data (and reference data) should be
// generated using the vvadd_gendata.pl perl script and dumped
// to a file named dataset1.h The smips-gcc toolchain does not
// support system calls so printf's can only be used on a host system,
// not on the smips processor simulator itself. You should not change
// anything except the HOST_DEBUG and PREALLOCATE macros for your timing
// runs.

//--------------------------------------------------------------------------
// Input/Reference Data

#include "util.h"
#include "dataset1.h"

//--------------------------------------------------------------------------
// Shared output data

volatile int results_data[DATA_SIZE];
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

//--------------------------------------------------------------------------
// Main

// Do the work of the even additions
int main0( )
{
  int i;

  printStr("Benchmark mc_vvadd\n");

  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the addition
  for( i = 0 ; i < DATA_SIZE/2 ; i = i+1 ) {
      results_data[i] = input1_data[i] + input2_data[i];
  }

  // stop counting instructions and cycles
  cycles = getCycle() - cycles;
  insts = getInsts() - insts;

  // wait for main1 to finish
  while( main1_done == 0 );

  // print the cycles and inst count
  printStr("Cycles (core 0) = "); printInt(cycles); printChar('\n');
  printStr("Insts  (core 0) = "); printInt(insts); printChar('\n');
  printStr("Cycles (core 1) = "); printInt(main1_cycles); printChar('\n');
  printStr("Insts  (core 1) = "); printInt(main1_insts); printChar('\n');
  cycles = (cycles > main1_cycles) ? cycles : main1_cycles;
  insts = insts + main1_insts;
  printStr("Cycles  (total) = "); printInt(cycles); printChar('\n');
  printStr("Insts   (total) = "); printInt(insts); printChar('\n');

  // Check the results
  int ret = verify( DATA_SIZE, results_data, verify_data );
	printStr("Return "); printInt(ret); printChar('\n');
	return ret;
}

// Do the work of the even additions
int main1( )
{
  int i;

  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the addition
  for( i = DATA_SIZE/2 ; i < DATA_SIZE ; i = i+1 ) {
      results_data[i] = input1_data[i] + input2_data[i];
  }

  // stop counting instructions and cycles
  cycles = getCycle() - cycles;
  insts = getInsts() - insts;
  main1_cycles = cycles;
  main1_insts = insts;
  main1_done = 1;

  // Return success
  return 0;
}

int main(int argc, char *argv[] )
{
	int coreid = getCoreId();
    if( coreid == 0 ) {
        return main0();
    } else if( coreid == 1 ) {
        return main1();
    }
	return 0;
}
