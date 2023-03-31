
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

	la x1, 0x04000
	la x2, 0x05000
	la x3, 0x06000
	la x4, 0x07000
	la x5, 0x08000
	la x6, 0x09000
	la x7, 0x0a000

	li TESTNUM, 5
loop:
	li x8, 50
	sw x0, 0(x1) # miss
	sw x0, 0(x2) # miss
	sw x0, 0(x3) # miss
	sw x0, 0(x4) # miss
	sw x0, 0(x5) # miss
	sw x0, 0(x6) # miss
	sw x0, 0(x7) # miss

	# idle: use loop to prevent I$ thrashing
1:	addi x8, x8, -1
	TEST_INSERT_NOPS_5
	bne x8, x0, 1b

	addi TESTNUM, TESTNUM, -1
	bne TESTNUM, x0, loop
	j pass

TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
