#include <errno.h>
#include <stdio.h>
#include <cstring>
#include <cassert>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <semaphore.h>
#include <vector>
#include <string>
#include <iostream>
#include <fstream>
#include <list>
#include <signal.h>

#include "ConnectalProcRequest.h"
#include "ConnectalProcIndication.h"

using namespace std;

static ConnectalProcRequestProxy *connectalProc= 0;
volatile int run = 1;
uint32_t print_int = 0;

class ConnectalProcIndication: public ConnectalProcIndicationWrapper
{
public:
    virtual void sendMessage(uint32_t msg){
		    uint32_t type = msg>>16 ;
            	    uint32_t data = msg & ( (1>>16) - 1);
			if(type == 0) {
				if(data == 0) {
					fprintf(stderr, "PASSED\n");
				} else {
					fprintf(stderr, "FAILED: exit code = %d\n", data);
				}
		                run=0;
			} else if(type == 1) {
				fprintf(stderr, "%c", (char)data);
			} else if(type == 2) {
				print_int = uint32_t(data);
			} else if(type == 3) {
				print_int |= uint32_t(data) << 16;
				fprintf(stderr, "%d", print_int);
			}
  
    }
   ConnectalProcIndication(unsigned int id) : ConnectalProcIndicationWrapper(id){}
};

static ConnectalProcIndication *ind = 0;
int main(int argc, char * const *argv) {
    printf("Start testbench:\n");
    fflush(stdout);
    connectalProc = new ConnectalProcRequestProxy(IfcNames_ConnectalProcRequestS2H);
    ind = new ConnectalProcIndication(IfcNames_ConnectalProcIndicationH2S);
    connectalProc->hostToCpu(0x200);
    printf("Processor started");
    fflush(stdout);
    // Now the processor is running we are waiting for it to be done 
    while (run != 0){}     
    return 0;
}

