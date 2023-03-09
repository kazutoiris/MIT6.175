
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import Reg6375::*;

import FShow::*;
import Vector::*;

typedef Server#(t, Vector#(n, t)) Chunker#(numeric type n, type t);
    
module mkChunker(Chunker#(n, t))
    provisos(Bits#(t, t_sz));

    FIFO#(t) infifo <- mkFIFO();
    FIFO#(Vector#(n, t)) outfifo <- mkFIFO();

    Reg#(Bit#(TLog#(n))) index <- mkReg(0);
    Reg#(Vector#(n, t)) pending <- mkRegU();

    rule iterate (True);
        let x <- toGet(infifo).get();
        let npending = pending;
        npending[index] = x;

        if (index == fromInteger(valueof(n)-1)) begin
            outfifo.enq(npending);
            index <= 0;
        end else begin
            index <= index+1;
            pending <= npending;
        end
    endrule
    
    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);
endmodule

module mkChunkerTest (Empty);
    Chunker#(4, Bit#(16)) chunker <- mkChunker();
    Reg#(Bit#(32)) feed <- mkReg(0);
    Reg#(Bit#(32)) check <- mkReg(0);
    Reg#(Bool) passed <- mkReg(True);

    function Action dofeed(Bit#(16) x);
        action
            chunker.request.put(x);
            feed <= feed+1;
        endaction
    endfunction

    function Action docheck(Bit#(16) a, Bit#(16) b, Bit#(16) c, Bit#(16) d);
        action
            Vector#(4, Bit#(16)) exp = newVector;
            exp[0] = a; exp[1] = b; exp[2] = c; exp[3] = d;
            let x <- chunker.response.get();
            if (x != exp) begin
                $display("wnt: ", fshow(exp));
                $display("got: ", fshow(x));
                passed <= False;
            end
            check <= check+1;
        endaction
    endfunction

    rule f0 (feed == 0); dofeed(4); endrule
    rule f1 (feed == 1); dofeed(3); endrule
    rule f2 (feed == 2); dofeed(9); endrule
    rule f3 (feed == 3); dofeed(1); endrule
    rule f4 (feed == 4); dofeed(22); endrule
    rule f5 (feed == 5); dofeed(29); endrule
    rule f6 (feed == 6); dofeed(21); endrule
    rule f7 (feed == 7); dofeed(22); endrule

    rule c0 (check == 0); docheck(4, 3, 9, 1); endrule
    rule c1 (check == 1); docheck(22, 29, 21, 22); endrule

    rule finish (feed == 8 && check == 2);
        if (passed) begin
            $display("PASSED");
        end else begin
            $display("FAILED");
        end
        $finish();
    endrule
    
endmodule

