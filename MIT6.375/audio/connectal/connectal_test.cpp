#include <stdio.h>
#include <stdint.h>
#include <sys/stat.h>
#include <pthread.h>

#include "MyDutRequest.h"
#include "MyDutIndication.h"

static MyDutRequestProxy *device = 0;

size_t putcount = 0;
size_t gotcount = 0;

// You need a lock when variables are shared by multiple threads:
// (1) the thread that sends request to HW and (2) another thread that processes indications from HW
pthread_mutex_t outpcmLock;
FILE *outpcm = NULL;

// The seperate thread in charge of indications invokes these call-back functions
class MyDutIndication : public MyDutIndicationWrapper
{
public:
    // You have to define all the functions (indication methods) defined in MyDutIndication
    virtual void returnOutput(uint16_t d) {
        if (gotcount < putcount) {
            if(fwrite(&d, 2, 1, outpcm) != 1) {
                fprintf(stderr, "write failed (out.pcm)\n");
                fclose(outpcm);
                pthread_mutex_lock(&outpcmLock);
                outpcm = NULL;
                pthread_mutex_unlock(&outpcmLock);
            }
            gotcount++;
        } else if (outpcm) {
            fclose(outpcm);
            pthread_mutex_lock(&outpcmLock);
            outpcm = NULL;
            pthread_mutex_unlock(&outpcmLock);
        }
    }

    // Required
    MyDutIndication(unsigned int id) : MyDutIndicationWrapper(id) {}
};

void run_test_bench(){
    FILE *inpcm = fopen("in.pcm", "rb");
    if (inpcm == NULL) {
        fprintf(stderr, "could not open in.pcm\n");
        return;
    }

    struct stat stat_buf;
    fstat(fileno(inpcm), &stat_buf);
    if (stat_buf.st_size % 2 != 0) {
        fprintf(stderr, "The size of in.pcm should be multiple of 2B\n");
        fclose(inpcm);
        return;
    }
    putcount = (size_t)stat_buf.st_size/2;

    outpcm = fopen("out.pcm", "wb");
    if (outpcm == NULL) {
        fprintf(stderr, "could not open out.pcm\n");
        fclose(inpcm);
        return;
    }

    pthread_mutex_init(&outpcmLock, NULL);

    printf("start sending in.pcm..\n");

    uint16_t elem;
    for (size_t i = 0; i < putcount; i++) {
        if(fread(&elem, 2, 1, inpcm) != 1) { // read 2B from in.cpm
            fprintf(stderr, "read failed (in.pcm)\n");
            fclose(inpcm);
            fclose(outpcm);
            pthread_mutex_destroy(&outpcmLock);
            return;
        }

        // Invoke putSampleInput method with 2B argument
        device->putSampleInput(elem);
    }

    // Just in case put seven more 0s for padding -- soft reset required for subsequent usage
    //  8-POINT FFT
    for (int j = 0; j < 7; j++) {
        device->putSampleInput(0);
    }

    // Wait until we collect all the output data
    struct timespec one_ms = {0, 1000000};
    pthread_mutex_lock(&outpcmLock);
    while (outpcm) {
        pthread_mutex_unlock(&outpcmLock);
        nanosleep(&one_ms , NULL);
        pthread_mutex_lock(&outpcmLock);
    }
    pthread_mutex_unlock(&outpcmLock);

    pthread_mutex_destroy(&outpcmLock);

    printf("run_test_bench finished!\n");
}

int main (int argc, const char **argv)
{
    // Service Indication messages from HW - Register the call-back functions to a indication thread
    MyDutIndication myIndication (IfcNames_MyDutIndicationH2S);

    // Open a channel to FPGA to issue requests
    device = new MyDutRequestProxy(IfcNames_MyDutRequestS2H);

    // Invoke reset_dut method of HW request ifc (Soft-reset)
    device->reset_dut();

    // Run the testbench: send in.cpm
    run_test_bench();
}
