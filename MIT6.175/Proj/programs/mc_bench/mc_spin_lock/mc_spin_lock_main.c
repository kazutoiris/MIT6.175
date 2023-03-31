#include "util.h"

// prevent false sharing
// locks
volatile int mutex_buf[16];
// accumulator
volatile int count_buf[16];

volatile int *mutex = mutex_buf;
volatile int *count = count_buf;

void lock(volatile int *p) {
	int cur_val;
	int lock_val = 1;
	int sc_ret;
	asm volatile (
			"1: lr.w %0, (%3)\n"
			"   bnez %0, 1b\n"
			"   sc.w %1, %4, (%3)\n"
			"   bnez %1, 1b\n"
			: "=r"(cur_val), "=r"(sc_ret), "=m"(*p)
			: "r"(p), "r"(lock_val), "m"(*p)
			: "memory"
			);
}

void unlock(volatile int *p) {
	*p = 0;
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
	printStr("Benchmark mc_spin_lock\n");

	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

	// do many locking & unlocking
	for(int i = 0; i < MAX_COUNT; i++) {
		lock(mutex);
		int val = *count;
		delay(5);
		printChar('0');
		*count = val + 1;
		unlock(mutex);
		delay(1);
	}

	// stop counting instructions and cycles
	cycles = getCycle() - cycles;
	insts = getInsts() - insts;

	// wait for main1 to finish
	while( main1_done == 0 );

	// print final count
	printStr("\nCore 0 increments counter by ");
	printInt(MAX_COUNT);
	printStr("\nCore 1 increments counter by ");
	printInt(MAX_COUNT + MAX_COUNT);
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

	// check & return
	int ret = (*count) != (MAX_COUNT + MAX_COUNT + MAX_COUNT);
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
		lock(mutex);
		int val = *count;
		delay(5);
		printChar('1');
		*count = val + 2;
		unlock(mutex);
		delay(1);
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
