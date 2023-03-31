#include "util.h"


// here may be lots of false sharing...
volatile int core0_tries = 0;
volatile int core0_success = 0;
volatile int core1_tries = 0;
volatile int core1_success = 0;
volatile int shared_count = 0;

// stats of core 1
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

#define MAX_COUNT 1000

// prevent GCC optimization
void __attribute__((optimize("O0"))) delay(int n) {
	for(int i = 0; i < n; i++);
}

int atomicIncrement(volatile int *p) {
	int ret;
	int data;
	asm volatile (
			"lr.w %0, (%3)\n"
			"addi %0, %0, 1\n"
			"sc.w %1, %0, (%3)\n"
			: "=r"(data), "=r"(ret), "=m"(*p)
			: "r"(p), "m"(*p)
			: "memory"
			);
	// ret = 0 --> success, = 1 --> fail
	return ret;
}

int count0()
{
	printStr("Benchmark mc_incrementers\n");

	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

    while( core0_success < MAX_COUNT )
    {
        int ret = atomicIncrement(&shared_count);
        core0_tries++;
        if( ret == 0 ) {
            core0_success++;
			// now do some random work as a delay
			delay(0);
        }
    }

	// stop counting instructions and cycles
	cycles = getCycle() - cycles;
	insts = getInsts() - insts;

	// wait for core 1 to finish
	while( main1_done == 0 );

	// print final count
    printStr("\ncore0 had "); printInt( core0_success ); printStr(" successes out of ");
    printInt( core0_tries ); printStr(" tries\n");

    printStr("core1 had "); printInt( core1_success ); printStr(" successes out of "); 
    printInt( core1_tries ); printStr(" tries\n");

    printStr("shared_count = "); printInt( shared_count ); printStr("\n");

	// print the cycles and inst count
	printStr("Cycles (core 0) = "); printInt(cycles); printChar('\n');
	printStr("Insts  (core 0) = "); printInt(insts); printChar('\n');
	printStr("Cycles (core 1) = "); printInt(main1_cycles); printChar('\n');
	printStr("Insts  (core 1) = "); printInt(main1_insts); printChar('\n');
	cycles = (cycles > main1_cycles) ? cycles : main1_cycles;
	insts = insts + main1_insts;
	printStr("Cycles  (total) = "); printInt(cycles); printChar('\n');
	printStr("Insts   (total) = "); printInt(insts); printChar('\n');

    int ret = ((core0_success + core1_success) != shared_count);
	printStr("Return "); printInt(ret); printChar('\n');
	return ret;
}

int count1()
{
	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

    while( core1_success < MAX_COUNT )
    {
        int ret = atomicIncrement(&shared_count);
        core1_tries++;
        if( ret == 0 ) {
            core1_success++;
			// now do some random work as a delay
			delay(0);
        }
    }

	// stop counting instructions and cycles
	cycles = getCycle() - cycles;
	insts = getInsts() - insts;
	main1_cycles = cycles;
	main1_insts = insts;

	// set done bit
	main1_done = 1;

    return 0;
}

int main( int argc, char *argv[] )
{
	int coreid = getCoreId();
    if( coreid == 0 ) {
        return count0();
    } else if(coreid == 1) {
        return count1();
    }
	return 0;
}
