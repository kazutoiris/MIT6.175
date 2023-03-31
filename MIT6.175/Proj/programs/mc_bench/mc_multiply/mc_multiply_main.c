// *************************************************************************
// multiply filter bencmark
// -------------------------------------------------------------------------
//
// This benchmark tests the software multiply implemenation. The
// input data (and reference data) should be generated using the
// multiply_gendata.pl perl script and dumped to a file named
// dataset1.h You should not change anything except the
// HOST_DEBUG and PREALLOCATE macros for your timing run.

// Update for multicore processor:
// This benchmark has been modified to run on a two core SMIPS processor.
// main0 works on even entries in the list and main1 works on odd entries in
// the list.

#include "util.h"
#include "multiply.h"

//--------------------------------------------------------------------------
// Input/Reference Data

#include "dataset1.h"

//--------------------------------------------------------------------------
// Shared output data

volatile int results_data[DATA_SIZE];
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

//--------------------------------------------------------------------------
// Main

// Do the work of even multiplies
int main0( )
{
  int i;

  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the multiplication for the first half
  for( i = 0 ; i < DATA_SIZE/2 ; i = i+1 ) {
    results_data[i] = multiply( input_data1[i], input_data2[i] );
  }

  // stop counting instructions and cycles
  insts = getInsts() - insts;
  cycles = getCycle() - cycles;

  // wait for main1 to finish
  while( main1_done == 0 );


  // print the cycle and inst count
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

// Do the work of odd multiplies
int main1( )
{
  int i;

  printStr("Benchmark mc_multiply\n");

  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the multiplication for the second half
  for( i = DATA_SIZE/2 ; i < DATA_SIZE ; i = i+1 ) {
    results_data[i] = multiply( input_data1[i], input_data2[i] );
  }

  // stop counting instructions and cycles
  cycles = getCycle() - cycles;
  insts = getInsts() - insts;
  main1_cycles = cycles;
  main1_insts = insts;

  // signal that main1 finished
  main1_done = 1;

  // always return success, main0 will keep track of accuracy
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
