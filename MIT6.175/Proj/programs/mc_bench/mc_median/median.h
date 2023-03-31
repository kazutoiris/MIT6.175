//**************************************************************************
// Median filters
//--------------------------------------------------------------------------
// $Id: median.h,v 1.1.1.1 2006-02-20 03:54:52 cbatten Exp $

// Simple C version
void median_first_half( int n, int input[], volatile int results[] );
void median_second_half( int n, int input[], volatile int results[] );

// Simple assembly version
//void median_asm( int n, int input[], int results[] );
