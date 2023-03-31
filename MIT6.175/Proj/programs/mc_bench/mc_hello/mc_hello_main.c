#include "util.h"


#define FIFO_SIZE 16
// prevent false sharing (16 words): gcc align is ignored by compiler ...
volatile uint32_t fifo_data[FIFO_SIZE + 16];
volatile int head_index_buf[16] = {0};
volatile int tail_index_buf[16] = {0};
volatile int *head_index = head_index_buf;
volatile int *tail_index = tail_index_buf;

volatile int done = 0; // core 1 finish printing

char *message = "Hello World!\nThis message has been written to a software FIFO by core 0 and read and printed by core 1.\n";

// Core 0
// Generate the text
int core0()
{
    // copy "Hello World!" to a common fifo
    uint32_t data = 0;
    int new_tail_index = 0; // temp var to contain intermediate index val
	char *x = message;
    do {
        uint32_t* y = (uint32_t*)(((uint32_t)x) & ~0x03);
        uint32_t fullC = *y;
        uint32_t mod = ((uint32_t)x) & 0x3;
        uint32_t shift = mod << 3;
        data = (fullC & (0xFF << shift)) >> shift;
		x++;
        
        // now write data to the fifo
		new_tail_index = *tail_index;
        fifo_data[new_tail_index] = data;

        new_tail_index++;
        if( new_tail_index == FIFO_SIZE ) {
            new_tail_index = 0;
        }
        while( *head_index == new_tail_index ); // wait for consumer to catch up
        *tail_index = new_tail_index;
    } while( data != 0 );

	while(!done);

    return 0;
}

// Core 1
// Print the text
int core1()
{
    // print the string found in the common fifo
    uint32_t data = 0;
    int new_head_index = 0;
    do {
		new_head_index = *head_index;
        while( new_head_index == *tail_index ); // wait for data to be produced
        data = fifo_data[new_head_index];
        new_head_index++;
        if( new_head_index == FIFO_SIZE ) {
            new_head_index = 0;
        }
        *head_index = new_head_index;
        if( data != 0 ) {
            printChar( data );
        }
    } while( data != 0 );

	done = 1;

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
