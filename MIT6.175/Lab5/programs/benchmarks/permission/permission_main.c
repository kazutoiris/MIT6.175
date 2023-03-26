#include "util.h"

int main(int argc, char *argv[]) {

  printStr("Benchmark permission\n");

  // we write mcontext and should fail since we are in user mode
  asm volatile("csrw mcontext, x0");
  while (1)
    ;

  return 0;
}
