// *************************************************************************
// multiply function (c version)
// -------------------------------------------------------------------------
// $Id: multiply.c,v 1.1 2006-03-05 07:03:29 cbatten Exp $

int multiply( int x, int y )
{
    int i;
    int result = 0;

    for (i = 0; i < 32; i++) {
        if ((x & 0x1) == 1) {
            result = result + y;
        } else if (x == 0) {
            break;
        }
        x = x >> 1;
        y = y << 1;
    } 
    return result;
}

