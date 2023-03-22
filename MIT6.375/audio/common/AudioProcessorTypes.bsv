import Complex::*;
import FixedPoint::*;
import GetPut::*;

typedef Int#(16) Sample;

interface AudioProcessor;
    method Action putSampleInput(Sample in);
    method ActionValue#(Sample) getSampleOutput();
endinterface

interface SettableAudioProcessor#(numeric type isize, numeric type fsize);
    interface AudioProcessor audioProcessor;
    interface Put#(FixedPoint#(isize, fsize)) setFactor;
endinterface

// Turn a real Sample into a ComplexSample.
function ComplexSample tocmplx(Sample x);
    return cmplx(fromInt(x), 0);
endfunction

// Extract the real component from complex.
function Sample frcmplx(ComplexSample x);
    return unpack(truncate(x.rel.i));
endfunction

typedef 8 FFT_POINTS;
typedef TLog#(FFT_POINTS) FFT_LOG_POINTS;
typedef Complex#(FixedPoint#(16, 16)) ComplexSample;
