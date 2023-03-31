//**************************************************************************
// Median filter (c version)
//--------------------------------------------------------------------------
// $Id: median.c,v 1.1.1.1 2006-02-20 03:54:52 cbatten Exp $

void median_first_half( int n, int input[], volatile int results[] )
{
  int A, B, C, i;

  // Zero the begining
  results[0]   = 0;
  results[n-1] = 0;

  // Do the filter
  for ( i = 1; i < n/2; i++ ) {

    A = input[i-1];
    B = input[i];
    C = input[i+1];

    if ( A < B ) {
      if ( B < C )     
        results[i] = B;
      else if ( C < A )
        results[i] = A;
      else
        results[i] = C;
    }

    else {
      if ( A < C )     
        results[i] = A;
      else if ( C < B )
        results[i] = B;
      else             
        results[i] = C;
    }

  }

}

void median_second_half( int n, int input[], volatile int results[] )
{
  int A, B, C, i;

  // Do the filter
  for ( i = n/2; i < (n-1); i++ ) {

    A = input[i-1];
    B = input[i];
    C = input[i+1];

    if ( A < B ) {
      if ( B < C )     
        results[i] = B;
      else if ( C < A )
        results[i] = A;
      else
        results[i] = C;
    }

    else {
      if ( A < C )     
        results[i] = A;
      else if ( C < B )
        results[i] = B;
      else             
        results[i] = C;
    }

  }

  // Zero the end
  results[n-1] = 0;


}

