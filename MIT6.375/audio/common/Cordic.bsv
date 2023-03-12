
import Complex::*;
import FixedPoint::*;
import Real::*;
import Vector::*;

import ClientServer::*;
import FIFO::*;
import GetPut::*;

import FShow::*;
import StmtFSM::*;

import ComplexMP::*;

// CORDIC.
//  Conversion of complex numbers in REAL/IMAGINARY format to and from
//  a MAGNITUDE/PHASE format.

instance FShow#(Real);
    function Fmt fshow(Real x);
        match {.n, .f} = splitReal(x);
        return $format(n, ".", trunc(10000*f));
    endfunction
endinstance

typedef Server#(
    Complex#(FixedPoint#(isize, fsize)),
    ComplexMP#(isize, fsize, psize)
) ToMagnitudePhase#(numeric type isize, numeric type fsize, numeric type psize);

typedef Server#(
    ComplexMP#(isize, fsize, psize),
    Complex#(FixedPoint#(isize, fsize))
) FromMagnitudePhase#(numeric type isize, numeric type fsize, numeric type psize);

// Return the phase change for the given cordic iteration as a Real number.
function Real cordicangle(Integer k);
    return atan(2**fromInteger(-k));
endfunction

// Return the phase change for the given cordic iteration as a Phase number.
function Phase#(n) cordicphase(Integer k);
    return tophase(cordicangle(k));
endfunction

// Calculate the Real value of the cordic gain after the given
// number of iterations. This will be evaluated statically.
function Real gain(Integer iters); 
    let ig = 1;
    if (iters > 0) begin
        ig = sqrt(1 + pow(2, -2*fromInteger(iters-1))) * gain(iters-1);
    end
    return ig;
endfunction

// Convert complex numbers in REAL/IMAGINARY format to MAGNITUDE/PHASE.
module mkCordicToMagnitudePhase (ToMagnitudePhase#(isize, fsize, psize));
    Reg#(Bool) idle <- mkReg(True);
    Reg#(FixedPoint#(isize, fsize)) rel <- mkRegU();
    Reg#(FixedPoint#(isize, fsize)) img <- mkRegU();
    Reg#(Phase#(psize)) phase <- mkRegU();
    Reg#(Bit#(TLog#(psize))) iter <- mkRegU(); 

    FIFO#(Complex#(FixedPoint#(isize, fsize))) infifo <- mkFIFO();
    FIFO#(ComplexMP#(isize, fsize, psize)) outfifo <- mkFIFO();

    // Table of cordic angles
    Vector#(psize, Phase#(psize)) cordicangles = genWith(cordicphase);

    // Return the inverse cordic gain after all the iterations are done.
    // This should be evaluated statically.
    function FixedPoint#(isize, fsize) igain();
        return fromReal(1/gain(valueof(psize)));
    endfunction

    rule start (idle);
        // Get the next number to convert.
        // We move the number to the right half plane here if needed.
        FixedPoint#(isize, fsize) r = infifo.first().rel;
        FixedPoint#(isize, fsize) i = infifo.first().img;
        Phase#(psize) p = 0;
        if (r < 0 && i >= 0) begin
            r = infifo.first().img;
            i = -infifo.first().rel;
            p = tophase(pi/2);
        end else if (r < 0) begin
            r = -infifo.first().img;
            i = infifo.first().rel;
            p = tophase(-pi/2);
        end

        if (r == 0 && i == 0) begin
            // Special case if r and i are both zero: no magnitude, no phase.
            outfifo.enq(cmplxmp(0, tophase(0)));
        end else begin
            idle <= False;
            rel <= r;
            img <= i;
            phase <= p;
            iter <= 0;
        end
        infifo.deq();
    endrule

    rule iterate (!idle);
        if (img > 0) begin
            rel <= rel + (img >> iter);
            img <= img - (rel >> iter);
            phase <= phase + cordicangles[iter];
        end else begin
            rel <= rel - (img >> iter);
            img <= img + (rel >> iter);
            phase <= phase - cordicangles[iter];
        end

        if (iter == maxBound) begin
            idle <= True;
            outfifo.enq(cmplxmp(rel * igain(), phase));
        end else begin
            iter <= iter+1;
        end
    endrule

    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);

endmodule

module mkCordicFromMagnitudePhase (FromMagnitudePhase#(isize, fsize, psize));
    Reg#(Bool) idle <- mkReg(True);
    Reg#(FixedPoint#(isize, fsize)) rel <- mkRegU();
    Reg#(FixedPoint#(isize, fsize)) img <- mkRegU();
    Reg#(Phase#(psize)) phase <- mkRegU();
    Reg#(Bit#(TLog#(psize))) iter <- mkRegU();

    FIFO#(ComplexMP#(isize, fsize, psize)) infifo <- mkFIFO();
    FIFO#(Complex#(FixedPoint#(isize, fsize))) outfifo <- mkFIFO();

    // Table of cordic angles
    Vector#(psize, Phase#(psize)) cordicangles = genWith(cordicphase);

    // Return the inverse cordic gain after all the iterations are done.
    // This should be evaluated statically.
    function FixedPoint#(isize, fsize) igain();
        return fromReal(1/gain(valueof(psize)));
    endfunction

    rule start (idle);
        // Get the next number to convert.
        // We move the number to the right half plane here if needed.
        FixedPoint#(isize, fsize) m = infifo.first().magnitude * igain();
        Phase#(psize) p = infifo.first().phase;
        if (p > tophase(pi/2)) begin
            rel <= 0;
            img <= m;
            phase <= p - tophase(pi/2);
        end else if (p < tophase(-pi/2)) begin
            rel <= 0;
            img <= -m;
            phase <= p + tophase(pi/2);
        end else begin
            rel <= m;
            img <= 0;
            phase <= p;
        end
            
        iter <= 0;
        idle <= False;
        infifo.deq();
    endrule

    rule iterate (!idle);
        if (phase > 0) begin
            rel <= rel - (img >> iter);
            img <= img + (rel >> iter);
            phase <= phase - cordicangles[iter];
        end else begin
            rel <= rel + (img >> iter);
            img <= img - (rel >> iter);
            phase <= phase + cordicangles[iter];
        end

        if (iter == maxBound) begin
            idle <= True;
            outfifo.enq(cmplx(rel, img));
        end else begin
            iter <= iter+1;
        end
    endrule
            
    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);

endmodule


// Unit tests for Cordic
(* synthesize *)
module mkCordicTest (Empty);
    Reg#(Bool) passed <- mkReg(True);

    ToMagnitudePhase#(16, 16, 10) tomp <- mkCordicToMagnitudePhase();
    FromMagnitudePhase#(16, 16, 20) frmp <- mkCordicFromMagnitudePhase();
    
    function Stmt testtomp(Complex#(FixedPoint#(16, 16)) x, ComplexMP#(16, 16, 10) exp);
        return (seq
            $display("-- tomp: ", fshow(x), "---------");
            tomp.request.put(x);
            action
                let got <- tomp.response.get();
                if (got.magnitude - exp.magnitude > fromReal(0.0001)
                    || got.magnitude - exp.magnitude < fromReal(-0.0001)
                    || got.phase != exp.phase
                ) begin
                    $display("tomp ", fshow(x));
                    $display("got: ", fshow(got));
                    $display("wnt: ", fshow(exp));
                    passed <= False;
                end
            endaction
        endseq);
    endfunction

    function Stmt testfrmp(ComplexMP#(16, 16, 20) x, Complex#(FixedPoint#(16, 16)) exp);
        return (seq
            $display("-- frmp: ", fshow(x), "---------");
            frmp.request.put(x);
            action
                let got <- frmp.response.get();
                if (got.rel - exp.rel > fromReal(0.001)
                    || got.rel - exp.rel < fromReal(-0.001)
                    || got.img - exp.img > fromReal(0.001)
                    || got.img - exp.img < fromReal(-0.001)
                ) begin
                    $display("frmp ", fshow(x));
                    $display("got: ", fshow(got));
                    $display("wnt: ", fshow(exp));
                    passed <= False;
                end
            endaction       
        endseq);
    endfunction
                
    
    Stmt tomptests = (seq
        testtomp(cmplx(1, 0), cmplxmp(1, tophase(0)));
        testtomp(cmplx(5, 0), cmplxmp(5, tophase(0)));
        testtomp(cmplx(-1, 0), cmplxmp(1, tophase(pi)));
        testtomp(cmplx(0, 1), cmplxmp(1, tophase(pi/2)));
        testtomp(cmplx(1, 1), cmplxmp(fromReal(sqrt(2)), tophase(pi/4)));
        testtomp(cmplx(-1, 1), cmplxmp(fromReal(sqrt(2)), tophase(3*pi/4)));
        testtomp(cmplx(-1, -1), cmplxmp(fromReal(sqrt(2)), tophase(-3*pi/4)));
        testtomp(cmplx(1, -1), cmplxmp(fromReal(sqrt(2)), tophase(-pi/4)));
        testtomp(cmplx(0, 0), cmplxmp(0, tophase(0)));

        // There was a bug that after 0,0 as input, everything was forever
        // 0,0. Try something after the 0,0 to make sure it still works:
        testtomp(cmplx(-1, 1), cmplxmp(fromReal(sqrt(2)), tophase(3*pi/4)));
    endseq);

    Stmt frmptests = (seq
        testfrmp(cmplxmp(1, tophase(0)), cmplx(1, 0));
        testfrmp(cmplxmp(5, tophase(0)), cmplx(5, 0));
        testfrmp(cmplxmp(1, tophase(pi)), cmplx(-1, 0));
        testfrmp(cmplxmp(fromReal(sqrt(2)), tophase(pi/4)), cmplx(1, 1));
        testfrmp(cmplxmp(fromReal(sqrt(2)), tophase(3*pi/4)), cmplx(-1, 1));
        testfrmp(cmplxmp(fromReal(sqrt(2)), tophase(-3*pi/4)), cmplx(-1, -1));
        testfrmp(cmplxmp(fromReal(sqrt(2)), tophase(-pi/4)), cmplx(1, -1));
        testfrmp(cmplxmp(0, ?), cmplx(0, 0));
    endseq);

    mkAutoFSM((seq tomptests; frmptests; endseq));

endmodule

