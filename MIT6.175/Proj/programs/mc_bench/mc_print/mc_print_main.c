#include "util.h"

volatile int done = 0;

int main(int argc, char *argv[]) {
	int core = getCoreId();

    if( core == 0 ) {
        printChar('0');
		while(done == 0);
		printChar('\n');
    } else if(core == 1) {
        printChar('1');
		done = 1;
    }

    return 0;
}
