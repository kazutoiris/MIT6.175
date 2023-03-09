
import ClientServer::*;
import Complex::*;
import FIFO::*;
import Reg6375::*;
import GetPut::*;
import Real::*;
import Vector::*;

import AudioProcessorTypes::*;

typedef Server#(
    Vector#(points, Complex#(cmplxd)),
    Vector#(points, Complex#(cmplxd))
) FFT#(numeric type points, type cmplxd);

// Get the appropriate twiddle factor for the given stage and index.
// This computes the twiddle factor statically.
function Complex#(cmplxd) getTwiddle(Integer stage, Integer index, Integer points)
    provisos(RealLiteral#(cmplxd));
    Integer i = ((2*index)/(2 ** (log2(points)-stage))) * (2 ** (log2(points)-stage));
    return cmplx(fromReal(cos(fromInteger(i)*pi/fromInteger(points))),
                 fromReal(-1*sin(fromInteger(i)*pi/fromInteger(points))));
endfunction

// Generate a table of all the needed twiddle factors.
// The table can be used for looking up a twiddle factor dynamically.
typedef Vector#(TLog#(points), Vector#(TDiv#(points, 2), Complex#(cmplxd))) TwiddleTable#(numeric type points, type cmplxd);
function TwiddleTable#(points, cmplxd) genTwiddles()  provisos(Add#(2, a__, points), RealLiteral#(cmplxd));
    TwiddleTable#(points, cmplxd) twids = newVector;
    for (Integer s = 0; s < valueof(TLog#(points)); s = s+1) begin
        for (Integer i = 0; i < valueof(TDiv#(points, 2)); i = i+1) begin
            twids[s][i] = getTwiddle(s, i, valueof(points));
        end
    end
    return twids;
endfunction

// Given the destination location and the number of points in the fft, return
// the source index for the permutation.
function Integer permute(Integer dst, Integer points);
    Integer src = ?;
    if (dst < points/2) begin
        src = dst*2;
    end else begin
        src = (dst - points/2)*2 + 1;
    end
    return src;
endfunction

// Reorder the given vector by swapping words at positions
// corresponding to the bit-reversal of their indices.
// The reordering can be done either as as the
// first or last phase of the FFT transformation.
function Vector#(points, Complex#(cmplxd)) bitReverse(Vector#(points,Complex#(cmplxd)) inVector);
    Vector#(points, Complex#(cmplxd)) outVector = newVector();
    for(Integer i = 0; i < valueof(points); i = i+1) begin
        Bit#(TLog#(points)) reversal = reverseBits(fromInteger(i));
        outVector[reversal] = inVector[i];
    end
    return outVector;
endfunction

// 2-way Butterfly
function Vector#(2, Complex#(cmplxd)) bfly2(Vector#(2, Complex#(cmplxd)) t, Complex#(cmplxd) k) provisos(Arith#(cmplxd));
    Complex#(cmplxd) m = t[1] * k;

    Vector#(2, Complex#(cmplxd)) z = newVector();
    z[0] = t[0] + m;
    z[1] = t[0] - m;

    return z;
endfunction

// Perform a single stage of the FFT, consisting of butterflys and a single
// permutation.
// We pass the table of twiddles as an argument so we can look those up
// dynamically if need be.
function Vector#(points, Complex#(cmplxd)) stage_ft(TwiddleTable#(points, cmplxd) twiddles, Bit#(TLog#(TLog#(points))) stage, Vector#(points, Complex#(cmplxd)) stage_in)
    provisos(Arith#(cmplxd), Add#(2, a__, points));
    Vector#(points, Complex#(cmplxd)) stage_temp = newVector();
    for(Integer i = 0; i < (valueof(points)/2); i = i+1) begin
        Integer idx = i * 2;
        let twid = twiddles[stage][i];
        let y = bfly2(takeAt(idx, stage_in), twid);

        stage_temp[idx]   = y[0];
        stage_temp[idx+1] = y[1];
    end

    Vector#(points, Complex#(cmplxd)) stage_out = newVector();
    for (Integer i = 0; i < valueof(points); i = i+1) begin
        stage_out[i] = stage_temp[permute(i, valueof(points))];
    end
    return stage_out;
endfunction

module mkCombinationalFFT (FFT#(points, cmplxd)) provisos(Add#(2, a__, points), Arith#(cmplxd), RealLiteral#(cmplxd), Bits#(cmplxd, b__));

  // Statically generate the twiddle factors table.
  TwiddleTable#(points, cmplxd) twiddles = genTwiddles();

  // Define the stage_f function which uses the generated twiddles.
  function Vector#(points, Complex#(cmplxd)) stage_f(Bit#(TLog#(TLog#(points))) stage, Vector#(points, Complex#(cmplxd)) stage_in);
      return stage_ft(twiddles, stage, stage_in);
  endfunction

  FIFO#(Vector#(points, Complex#(cmplxd))) inputFIFO  <- mkFIFO();
  FIFO#(Vector#(points, Complex#(cmplxd))) outputFIFO <- mkFIFO();

  // This rule performs fft using a big mass of combinational logic.
  rule comb_fft;

    Vector#(TAdd#(1, TLog#(points)), Vector#(points, Complex#(cmplxd))) stage_data = newVector();
    stage_data[0] = inputFIFO.first();
    inputFIFO.deq();

    for(Integer stage = 0; stage < valueof(TLog#(points)); stage=stage+1) begin
        stage_data[stage+1] = stage_f(fromInteger(stage), stage_data[stage]);
    end

    outputFIFO.enq(stage_data[valueof(TLog#(points))]);
  endrule

  interface Put request;
    method Action put(Vector#(points, Complex#(cmplxd)) x);
        inputFIFO.enq(bitReverse(x));
    endmethod
  endinterface

  interface Get response = toGet(outputFIFO);

endmodule

// Wrapper around The FFT module we actually want to use
module mkFFT (FFT#(points, cmplxd))
    provisos(Add#(2, a__, points), Bits#(cmplxd, b__), RealLiteral#(cmplxd), Arith#(cmplxd));

    // FFT#(points, cmplxd) fft <- mkLinearFFT();
    FFT#(points, cmplxd) fft <- mkCombinationalFFT();

    interface Put request = fft.request;
    interface Get response = fft.response;
endmodule

// Inverse FFT, based on the mkFFT module.
// ifft[k] = fft[N-k]/N
module mkIFFT (FFT#(points, cmplxd))
    provisos(Add#(2, a__, points), Bits#(cmplxd, b__), RealLiteral#(cmplxd), Arith#(cmplxd), Bitwise#(cmplxd));

    FFT#(points, cmplxd) fft <- mkFFT();
    FIFO#(Vector#(points, Complex#(cmplxd))) outfifo <- mkFIFO();

    Integer n = valueof(points);
    Integer lgn = valueof(TLog#(points));

    function Complex#(cmplxd) scaledown(Complex#(cmplxd) x);
        return cmplx(x.rel >> lgn, x.img >> lgn);
    endfunction

    rule inversify (True);
        let x <- fft.response.get();
        Vector#(points, Complex#(cmplxd)) rx = newVector;

        for (Integer i = 0; i < n; i = i+1) begin
            rx[i] = x[(n - i)%n];
        end
        outfifo.enq(map(scaledown, rx));
    endrule

    interface Put request = fft.request;
    interface Get response = toGet(outfifo);

endmodule

module mkLinearFFT (FFT#(points, cmplxd))
    provisos(Add#(2, a__, points),
    Bits#(cmplxd, b__),
    RealLiteral#(cmplxd),
    Arith#(cmplxd));
  // Statically generate the twiddle factors table.
  TwiddleTable#(points, cmplxd) twiddles = genTwiddles();

  // Define the stage_f function which uses the generated twiddles.
  function Vector#(points, Complex#(cmplxd)) stage_f(Bit#(TLog#(TLog#(points))) stage, Vector#(points, Complex#(cmplxd)) stage_in);
      return stage_ft(twiddles, stage, stage_in);
  endfunction

  FIFO#(Vector#(points, Complex#(cmplxd))) inputFIFO  <- mkFIFO();
  FIFO#(Vector#(points, Complex#(cmplxd))) outputFIFO <- mkFIFO();
  // This rule performs fft using a big mass of combinational logic.
  rule linear_fft;

    Vector#(points, Complex#(cmplxd)) stage_data = newVector();
    stage_data = inputFIFO.first();
    inputFIFO.deq();

    for (Integer stage = 0; stage < valueOf(TLog#(points)); stage = stage+1) begin
        stage_data = stage_f(fromInteger(stage), stage_data);
    end

    outputFIFO.enq(stage_data);
  endrule

    interface Put request;
        method Action put(Vector#(points, Complex#(cmplxd)) x);
            inputFIFO.enq(bitReverse(x));
        endmethod
    endinterface

  interface Get response = toGet(outputFIFO);

endmodule
