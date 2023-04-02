// See LICENSE for license details.

#include "util.h"
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>

// tag of data to host
enum ToHostTag {
  ExitCode = 0,
  PrintChar = 1,
  PrintIntLow = 2,
  PrintIntHigh = 3
};

// execption handler for print
void printInt_hdl(uint32_t c) {
  // print low 16 bits
  int lo = (c & 0x0000FFFF) | (((uint32_t)PrintIntLow) << 16);
  asm volatile("csrw mcontext, %0" : : "r"(lo));
  // print high 16 bits
  int hi = (c >> 16) | (((uint32_t)PrintIntHigh) << 16);
  asm volatile("csrw mcontext, %0" : : "r"(hi));
}

void printChar_hdl(uint32_t c) {
  c = (c & 0x0000FFFF) | (((uint32_t)PrintChar) << 16);
  asm volatile("csrw mcontext, %0" : : "r"(c));
}

void printStr_hdl(char *x) {
  while (1) {
    // get 4B aligned addr
    uint32_t *y = (uint32_t *)(((uint32_t)x) & ~0x03);
    uint32_t fullC = *y;
    uint32_t mod = ((uint32_t)x) & 0x3;
    uint32_t shift = mod << 3;
    uint32_t c = (fullC & (0x0FF << shift)) >> shift;
    if (c == (uint32_t)'\0')
      break;
    printChar_hdl(c);
    x++;
  }
}

// mul handler
void mul_hdl(int dest_idx, int src1_idx, int src2_idx, long *regs) {
  uint32_t x = (uint32_t)(regs[src1_idx]);
  uint32_t y = (uint32_t)(regs[src2_idx]);
  uint32_t res = 0;
  for (int i = 0; i < 32; i++) {
    if ((x & 0x1) == 1) {
      res += y;
    }
    x = x >> 1;
    y = y << 1;
  }
  regs[dest_idx] = (long)res;
}

// exit handler
void toHostExit_hdl(uint32_t ret) {
  ret = (ret & 0x0000FFFF) | (((uint32_t)ExitCode) << 16);
  asm volatile("csrw mcontext, %0" : : "r"(ret));
  // stall here
  while (1)
    ;
}

// syscall base function
// num: syscall type
// arg0: arguments
static long syscall(long num, long arg0) {
  register long a7 asm("a7") = num;
  register long a0 asm("a0") = arg0;
  asm volatile("scall" : "+r"(a0) : "r"(a7));
  return a0;
}

// print & exit implemented as system calls
enum SyscallID {
  SysToHostExit = 0,
  SysPrintInt = 1,
  SysPrintChar = 2,
  SysPrintStr = 3
};

void toHostExit(uint32_t ret) { syscall((long)SysToHostExit, (long)ret); }

void printInt(uint32_t c) { syscall((long)SysPrintInt, (long)c); }

void printChar(uint32_t c) { syscall((long)SysPrintChar, (long)c); }

void printStr(char *x) { syscall((long)SysPrintStr, (long)x); }

long handle_trap(long cause, long epc, long *regs) {
  if (cause == CAUSE_ILLEGAL_INSTRUCTION) {
    uint32_t inst = *((uint32_t *)epc);
    if ((inst & MASK_MUL) == MATCH_MUL) {
      // is MUL inst, jump to handler
      uint32_t dest = (inst >> 7) & 0x01F;
      uint32_t src1 = (inst >> 15) & 0x01F;
      uint32_t src2 = (inst >> 20) & 0x01F;
      mul_hdl(dest, src1, src2, regs);
    } else {
      // unrecognized inst
      toHostExit_hdl(1);
    }
  } else if (cause == CAUSE_USER_ECALL) {
    long type = regs[17]; // a7
    long arg0 = regs[10]; // a0
    if (type == (long)SysToHostExit) {
      toHostExit_hdl((uint32_t)arg0);
    } else if (type == (long)SysPrintChar) {
      printChar_hdl(arg0);
    } else if (type == (long)SysPrintInt) {
      printInt_hdl(arg0);
    } else if (type == (long)SysPrintStr) {
      printStr_hdl((char *)arg0);
    } else {
      // unrecognized sys call
      toHostExit_hdl(1);
    }
  } else {
    // error
    toHostExit_hdl(1);
  }
  // except resolve, we can skip inst at epc
  return epc + 4;
}

int __attribute__((weak)) main(int argc, char **argv) {
  // single-threaded programs override this function.
  printStr("Implement main(), foo!\n");
  return -1;
}

void _init(int cid, int nc) {
  int ret = main(0, 0); // call main function
  toHostExit((uint32_t)ret);
}
