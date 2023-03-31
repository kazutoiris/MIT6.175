#include "util.h"
#include "dataset1.h" // from qsort

#define FIFO_SIZE 16
// prevent false sharing (16 words): gcc align is ignored by compiler ...
volatile int fifo_data[FIFO_SIZE + 16];
volatile int head_index_buf[16] = {0};
volatile int tail_index_buf[16] = {0};
volatile int *head_index = head_index_buf;
volatile int *tail_index = tail_index_buf;

// stats
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

// Core 1
// Generate the data
int core1()
{
	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

    // copy input_data to a common fifo
    int data = 0;
    int new_tail_index = 0; // temp var to contain intermediate index val
    for(int i = 0; i < DATA_SIZE; i++) {
	//printStr("-");
        data = input_data[i];
        
        // now write data to the fifo
		new_tail_index = *tail_index;
        fifo_data[new_tail_index] = data;

        new_tail_index++;
        if( new_tail_index == FIFO_SIZE ) {
            new_tail_index = 0;
        }
        while( *head_index == new_tail_index ); // wait for consumer to catch up
        *tail_index = new_tail_index;
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

// Core 0
// consume & check data
int core0()
{
	printStr("Benchmark mc_produce_consume\n");

	// start counting instructions and cycles
	int cycles, insts;
	cycles = getCycle();
	insts = getInsts();

    // check data found in the common fifo
    uint32_t data = 0;
    int new_head_index = 0;
    for(int i = 0; i < DATA_SIZE; i++) {
		new_head_index = *head_index;
        while( new_head_index == *tail_index ); // wait for data to be produced
        data = fifo_data[new_head_index];
        new_head_index++;
        if( new_head_index == FIFO_SIZE ) {
            new_head_index = 0;
        }
        *head_index = new_head_index;
        if( data != input_data[i] ) {
			printStr("At index "); printInt(i);
			printStr(", receive data = ");
			printInt(data);
			printStr(", but expected data = ");
			printInt(input_data[i]);
			printStr(", mismatch!\n");
			printStr("Return "); printInt(i+1); printChar('\n');
			return (i+1);
        }
    }

	// stop counting instructions and cycles
	cycles = getCycle() - cycles;
	insts = getInsts() - insts;

	// wait for core 1 to complete
	while(main1_done == 0);

	// print the cycles and inst count
	printStr("Cycles (core 0) = "); printInt(cycles); printChar('\n');
	printStr("Insts  (core 0) = "); printInt(insts); printChar('\n');
	printStr("Cycles (core 1) = "); printInt(main1_cycles); printChar('\n');
	printStr("Insts  (core 1) = "); printInt(main1_insts); printChar('\n');
	cycles = (cycles > main1_cycles) ? cycles : main1_cycles;
	insts = insts + main1_insts;
	printStr("Cycles  (total) = "); printInt(cycles); printChar('\n');
	printStr("Insts   (total) = "); printInt(insts); printChar('\n');

	printStr("Return 0\n");
	return 0;
}

int main( int argc, char *argv[] ) {
	int coreid = getCoreId();
    if( coreid == 0 ) {
        return core0();
    } else if( coreid == 1 ) {
        return core1();
    }
    return 0;
}
