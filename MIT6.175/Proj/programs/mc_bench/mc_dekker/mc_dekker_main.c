#include "util.h"

// prevent false sharing
// locks
volatile int want_0_buf[16];
volatile int want_1_buf[16];
volatile int turn_buf[16];
// accumulator
volatile int count_buf[16];

volatile int *want[2] = {want_0_buf, want_1_buf};
volatile int *turn = turn_buf;
volatile int *count = count_buf;

void lock(int i) {
	*want[i] = 1;
	while(*want[!i]) {
		if(*turn != i) {
			*want[i] = 0;
			while(*turn != i);
			*want[i] = 1;
			FENCE(); // st -> ld ordering for TSO
		}
	}
}

void unlock(int i) {
	*turn = !i;
	*want[i] = 0;
}

// prevent GCC optimization
void __attribute__((optimize("O0"))) delay(int n) {
	for(int i = 0; i < n; i++);
}

#define MAX_COUNT 300
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

int main0() {
	printStr("Benchmark mc_dekker\n");

	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

	// do many locking & unlocking
	for(int i = 0; i < MAX_COUNT; i++) {
		lock(0);
		int val = *count;
		delay(5);
		printChar('0');
		*count = val - 2;
		unlock(0);
	}

	// stop counting instructions and cycles
	cycles = getCycle() - cycles;
	insts = getInsts() - insts;

	// wait for main1 to finish
	while( main1_done == 0 );

	// print final count
	printStr("\nCore 0 decrements counter by ");
	printInt(MAX_COUNT + MAX_COUNT);
	printStr("\nCore 1 increments counter by ");
	printInt(MAX_COUNT + MAX_COUNT + MAX_COUNT);
	printStr("\nFinal counter value = ");
	printInt(*count);
	printChar('\n');

	// print the cycles and inst count
	printStr("Cycles (core 0) = "); printInt(cycles); printChar('\n');
	printStr("Insts  (core 0) = "); printInt(insts); printChar('\n');
	printStr("Cycles (core 1) = "); printInt(main1_cycles); printChar('\n');
	printStr("Insts  (core 1) = "); printInt(main1_insts); printChar('\n');
	cycles = (cycles > main1_cycles) ? cycles : main1_cycles;
	insts = insts + main1_insts;
	printStr("Cycles  (total) = "); printInt(cycles); printChar('\n');
	printStr("Insts   (total) = "); printInt(insts); printChar('\n');

	int ret = (*count) != (MAX_COUNT);
	printStr("Return "); printInt(ret); printChar('\n');
	return ret;
}

int main1() {
	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

	// do many locking & unlocking
	for(int i = 0; i < MAX_COUNT; i++) {
		lock(1);
		int val = *count;
		delay(5);
		printChar('1');
		*count = val + 3;
		unlock(1);
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

int main(int argc, char *argv[]) {
	int core = getCoreId();
    if( core == 0 ) {
        return main0();
    } else if(core == 1) {
        return main1();
    }
	return 0;
}
