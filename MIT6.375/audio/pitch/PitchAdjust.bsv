
import ClientServer::*;
import FIFO::*;
import GetPut::*;

import FixedPoint::*;
import Vector::*;

import ComplexMP::*;


typedef Server#(
    Vector#(nbins, ComplexMP#(isize, fsize, psize)),
    Vector#(nbins, ComplexMP#(isize, fsize, psize))
) PitchAdjust#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);


interface SettablePitchAdjust#(
        numeric type nbins, numeric type isize,
        numeric type fsize, numeric type psize
    );

    interface PitchAdjust#(nbins, isize, fsize, psize) pitchAdjust;
    interface Put#(FixedPoint#(isize, fsize)) setFactor;
endinterface

// s - the amount each window is shifted from the previous window.
//
// factor - the amount to adjust the pitch.
//  1.0 makes no change. 2.0 goes up an octave, 0.5 goes down an octave, etc...
module mkPitchAdjust(Integer s, SettablePitchAdjust#(nbins, isize, fsize, psize) ifc)
    provisos(Add#(a__, psize, TAdd#(isize, isize)), Add#(psize, b__, isize), Add#(c__, TLog#(nbins), isize), Add#(TAdd#(TLog#(nbins), 1), d__, isize));

    Reg#(FixedPoint#(isize, fsize)) factor <- mkReg(unpack(2));

    // complex double* in, complex double* out
    Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) in <- mkReg(unpack(0));
    Reg#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) out <- mkReg(unpack(0));

    Vector#(nbins, Reg#(Phase#(psize))) inphases <- replicateM(mkReg(0)); // static double inphases[N] = {0};
    Vector#(nbins, Reg#(Phase#(psize))) outphases <- replicateM(mkReg(0)); // static double outphases[N] = {0};

    // Reg#(Bit#(TLog#(nbins))) i <- mkReg(0);
    Reg#(Bit#(TAdd#(TLog#(nbins), 1))) i <- mkReg(0);
    Reg#(FixedPoint#(isize, fsize)) bin <- mkReg(0);

    Reg#(Bool) done <- mkReg(True);
    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) inputFIFO <- mkFIFO();
    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) outputFIFO <- mkFIFO();

    rule fifo_in (done && i == 0);
        in <= inputFIFO.first;
        inputFIFO.deq;
        out <= replicate(cmplxmp(0, 0));
        done <= False;
        bin <= 0;
    endrule

    rule process (!done);
        let nbin = factor + bin;
        let phase = in[i].phase;
        let mag = in[i].magnitude;
        let dphase = phase - inphases[i];
        let bin_int = fxptGetInt(bin);
        let nbin_int = fxptGetInt(nbin);
        FixedPoint#(isize, fsize) dphaseFxpt = fromInt(dphase);

        if (nbin_int != bin_int && bin_int >= 0 && bin_int < fromInteger(valueOf(nbins))) begin
            let shifted = truncate(fxptGetInt(fxptMult(dphaseFxpt, factor)));
            let new_outphases = outphases[bin_int] + shifted;
            outphases[bin_int] <= new_outphases;
            out[bin_int] <= cmplxmp(mag, new_outphases);
        end

        if (i == (fromInteger(valueOf(nbins)) - 1)) begin
            done <= True;
        end else begin
            i <= i+1;
        end

        inphases[i] <= phase;
        bin <= nbin;
    endrule

    rule fifo_out (done && i == (fromInteger(valueOf(nbins)-1)));
        i <= 0;
        outputFIFO.enq(out);
    endrule


    interface PitchAdjust pitchAdjust;
        interface Put request = toPut(inputFIFO);
        interface Get response = toGet(outputFIFO);
    endinterface

    interface Put setFactor;
        method Action put(FixedPoint#(isize, fsize) x);
            factor <= x;
        endmethod
    endinterface
endmodule
