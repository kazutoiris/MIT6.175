
#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

	la x1, 0x04000

	li TESTNUM, 50
loop:
	sw x0, 0(x1) # miss
	TEST_INSERT_NOPS_10
	addi x1, x1, 64 # thrash the cache
	TEST_INSERT_NOPS_10
	TEST_INSERT_NOPS_10
	addi TESTNUM, TESTNUM, -1
	bne TESTNUM, x0, loop
	j pass

TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
