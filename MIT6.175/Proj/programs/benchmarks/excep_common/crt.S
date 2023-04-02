# See LICENSE for license details.

#include "encoding.h"

#ifdef __riscv64
#error "RV64 not supported in handle_trap in syscall.c
#else
# define LREG lw
# define SREG sw
#endif

  .text
  .align 6
user_trap_entry:
  j trap_entry

  .align 6
supervisor_trap_entry:
  j supervisor_trap_entry

  .align 6
hypervisor_trap_entry:
  j hypervisor_trap_entry

  .align 6
machine_trap_entry:
  j trap_entry

  .align 6
  .globl _start
_start:
  li  x1, 0
  li  x2, 0
  li  x3, 0
  li  x4, 0
  li  x5, 0
  li  x6, 0
  li  x7, 0
  li  x8, 0
  li  x9, 0
  li  x10,0
  li  x11,0
  li  x12,0
  li  x13,0
  li  x14,0
  li  x15,0
  li  x16,0
  li  x17,0
  li  x18,0
  li  x19,0
  li  x20,0
  li  x21,0
  li  x22,0
  li  x23,0
  li  x24,0
  li  x25,0
  li  x26,0
  li  x27,0
  li  x28,0
  li  x29,0
  li  x30,0
  li  x31,0

  # initialize global pointer
  la gp, _gp_ptr

  # init tp, make it 64B aligned
  la  tp, _end + 63
  and tp, tp, -64

  # allocate 128KB of stack + TLS for each thread
#define STKSHIFT 17
  csrr a0, mhartid
  sll a2, a0, STKSHIFT
  add tp, tp, a2
  add sp, a0, 1
  sll sp, sp, STKSHIFT
  add sp, sp, tp

  # init mscratch
  la t0, excep_hdl_stack
  csrw mscratch, t0

  # HW init mstatus as: PRV0 = M, IE0 = 1; PRV1 = U, IE1 = 1
  # eret should pop stack to set it to user mode
  la t0, _init
  csrw mepc, t0
  mret

trap_entry: # exception handler
  # get pointer to local stack
  csrrw sp, mscratch, sp
  
  # save GPR to stack
  addi sp, sp, -128

  #sw x0, 0(sp) 
  sw x1, 4(sp)
  # x2/sp is done at last
  sw x3, 12(sp)
  sw x4, 16(sp)
  sw x5, 20(sp)
  sw x6, 24(sp)
  sw x7, 28(sp)
  sw x8, 32(sp)
  sw x9, 36(sp)
  sw x10, 40(sp)
  sw x11, 44(sp)
  sw x12, 48(sp)
  sw x13, 52(sp)
  sw x14, 56(sp)
  sw x15, 60(sp)
  sw x16, 64(sp)
  sw x17, 68(sp)
  sw x18, 72(sp)
  sw x19, 76(sp)
  sw x20, 80(sp)
  sw x21, 84(sp)
  sw x22, 88(sp)
  sw x23, 92(sp)
  sw x24, 96(sp)
  sw x25, 100(sp)
  sw x26, 104(sp)
  sw x27, 108(sp)
  sw x28, 112(sp)
  sw x29, 116(sp)
  sw x30, 120(sp)
  sw x31, 124(sp)
  # save original sp
  csrr t0, mscratch
  sw t0, 8(sp)

  # call C handler
  csrr a0, mcause
  csrr a1, mepc
  mv a2, sp
  jal handle_trap
  # return value is next PC
  csrw mepc, a0

  # restore mscratch
  addi t0, sp, 128
  csrw mscratch, t0

  # restore GPRs
  lw x1, 4(sp)
  # x2/sp is restored at last
  lw x3, 12(sp)
  lw x4, 16(sp)
  lw x5, 20(sp)
  lw x6, 24(sp)
  lw x7, 28(sp)
  lw x8, 32(sp)
  lw x9, 36(sp)
  lw x10, 40(sp)
  lw x11, 44(sp)
  lw x12, 48(sp)
  lw x13, 52(sp)
  lw x14, 56(sp)
  lw x15, 60(sp)
  lw x16, 64(sp)
  lw x17, 68(sp)
  lw x18, 72(sp)
  lw x19, 76(sp)
  lw x20, 80(sp)
  lw x21, 84(sp)
  lw x22, 88(sp)
  lw x23, 92(sp)
  lw x24, 96(sp)
  lw x25, 100(sp)
  lw x26, 104(sp)
  lw x27, 108(sp)
  lw x28, 112(sp)
  lw x29, 116(sp)
  lw x30, 120(sp)
  lw x31, 124(sp)
  # restore sp
  lw x2, 8(sp)

  # done, return
  mret


.data
# 1KB storage for exception handling
# it would be better to put it in a fixed address
# for the lab purpose, this is fine...
.align 6
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
  .word 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF, 0xDEADBEEF
excep_hdl_stack: 


.section ".tdata.begin"
.globl _tdata_begin
_tdata_begin:

.section ".tdata.end"
.globl _tdata_end
_tdata_end:

.section ".tbss.end"
.globl _tbss_end
_tbss_end:
