import ClientServer::*;
import Complex::*;
import ComplexMP::*;
import FixedPoint::*;
import FIFO::*;
import Vector::*;
import Cordic::*;
import GetPut::*;

typedef Server#(
    Vector#(nbins, ComplexMP#(isize, fsize, psize)),
    Vector#(nbins, Complex#(FixedPoint#(isize, fsize)))
) FromMP#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);

typedef Server#(
    Vector#(nbins, Complex#(FixedPoint#(isize, fsize))),
    Vector#(nbins, ComplexMP#(isize, fsize, psize))
) ToMP#(numeric type nbins, numeric type isize, numeric type fsize, numeric type psize);

module mkFromMP(FromMP#(nbins, isize, fsize, psize) ifc);
    Vector#(nbins, FromMagnitudePhase#(isize, fsize, psize)) cordicFromMagnitudePhase <- replicateM(mkCordicFromMagnitudePhase());

    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) inputFIFO <- mkFIFO();
    FIFO#(Vector#(nbins, Complex#(FixedPoint#(isize, fsize)))) outputFIFO <- mkFIFO();

    rule in;
        for(Integer i = 0; i < valueOf(nbins); i = i + 1) begin
            cordicFromMagnitudePhase[i].request.put(inputFIFO.first[i]);
        end
        inputFIFO.deq;
        // $display("mkFromMP inputFIFO.deq");
    endrule

    rule out;
        Vector#(nbins, Complex#(FixedPoint#(isize, fsize))) res = unpack(0);
        for(Integer i = 0; i < valueOf(nbins); i = i+1) begin
            res[i] <- cordicFromMagnitudePhase[i].response.get();
        end
        outputFIFO.enq(res);
        // $display("mkFromMP outputFIFO.enq");
    endrule

    interface Put request = toPut(inputFIFO);
    interface Get response = toGet(outputFIFO);

endmodule

module mkToMP(ToMP#(nbins, isize, fsize, psize) ifc);
    Vector#(nbins, ToMagnitudePhase#(isize, fsize, psize)) cordicToMagnitudePhase <- replicateM(mkCordicToMagnitudePhase());

    FIFO#(Vector#(nbins, Complex#(FixedPoint#(isize, fsize)))) inputFIFO <- mkFIFO();
    FIFO#(Vector#(nbins, ComplexMP#(isize, fsize, psize))) outputFIFO <- mkFIFO();

    rule in;
        for(Integer i = 0; i < valueOf(nbins); i = i+1) begin
            cordicToMagnitudePhase[i].request.put(inputFIFO.first[i]);
        end
        inputFIFO.deq;
        // $display("mkToMP inputFIFO.deq");
    endrule

    rule out;
        Vector#(nbins, ComplexMP#(isize, fsize, psize)) res;
        for(Integer i = 0; i < valueOf(nbins); i = i+1) begin
            res[i] <- cordicToMagnitudePhase[i].response.get();
        end
        // $display("mkToMP outputFIFO.enq");
        outputFIFO.enq(res);
    endrule

    interface Put request = toPut(inputFIFO);
    interface Get response = toGet(outputFIFO);

endmodule
