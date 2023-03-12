
import Complex::*;
import FixedPoint::*;
import FShow::*;
import Real::*;

// MAGNITUDE/PHASE representation of a complex number.
//
//  The PHASE is represented using N bits, interpreted as a signed twos
//  compliment integer p, such that the phase angle is (p * PI/(2^(N-1)).
//  This places the phase in the interval [-PI, PI).
//  For example, if the PHASE is represented with N=3 bits, the value 'b010
//  means an angle of 2 * PI/4 = PI/2.

typedef Int#(n) Phase#(numeric type n);

// Convert a real number (in radians) to phase.
function Phase#(n) tophase(Real rads);
    return unpack(fromInteger(round(rads * (2**(fromInteger(valueof(n)-1)))/ pi)));
endfunction

// A complex number in magnitude, phase format.
typedef struct {
    FixedPoint#(misize, mfsize) magnitude;
    Phase#(psize) phase;
} ComplexMP#(numeric type misize, numeric type mfsize, numeric type psize)
    deriving(Bits, Eq);

function ComplexMP#(misize, mfsize, psize) cmplxmp(
    FixedPoint#(misize, mfsize) mag, Phase#(psize) phs);
    return ComplexMP { magnitude: mag, phase: phs };
endfunction

function Phase#(psize) phaseof(ComplexMP#(misize, mfsize, psize) x);
    return x.phase;
endfunction

instance FShow#(ComplexMP#(mi, mf, p));
    function Fmt fshow(ComplexMP#(mi, mf, p) x);
        return $format("<", fshow(x.magnitude), ", ", fshow(x.phase), ">");
    endfunction
endinstance

