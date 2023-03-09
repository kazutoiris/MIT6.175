
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import Reg6375::*;

import Vector::*;

typedef Server#(Vector#(n, t), t) Splitter#(numeric type n, type t);
    
module mkSplitter(Splitter#(n, t))
    provisos(Bits#(t, t_sz));

    FIFO#(Vector#(n, t)) infifo <- mkFIFO();
    FIFO#(t) outfifo <- mkFIFO();

    Reg#(Bit#(TLog#(n))) index <- mkReg(0);

    rule iterate (True);
        outfifo.enq(infifo.first()[index]);
        
        if (index == fromInteger(valueof(n)-1)) begin
            infifo.deq();
            index <= 0;
        end else begin
            index <= index+1;
        end
    endrule
    
    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);
endmodule

module mkSplitterTest (Empty);
    Splitter#(4, Bit#(16)) splitter <- mkSplitter();
    Reg#(Bit#(32)) feed <- mkReg(0);
    Reg#(Bit#(32)) check <- mkReg(0);
    Reg#(Bool) passed <- mkReg(True);

    function Vector#(4, Bit#(16)) v4(Bit#(16) a, Bit#(16) b, Bit#(16) c, Bit#(16) d);
        Vector#(4, Bit#(16)) v = newVector;
        v[0] = a; v[1] = b; v[2] = c; v[3] = d;
        return v;
    endfunction

    function Action dofeed(Vector#(4, Bit#(16)) x);
        action
            splitter.request.put(x);
            feed <= feed+1;
        endaction
    endfunction

    function Action docheck(Bit#(16) exp);
        action
            let x <- splitter.response.get();
            if (x != exp) begin
                $display("wnt: ", exp);
                $display("got: ", x);
                passed <= False;
            end
            check <= check+1;
        endaction
    endfunction

    rule f0 (feed == 0); dofeed(v4(4, 3, 9, 1)); endrule
    rule f1 (feed == 1); dofeed(v4(22, 29, 21, 22)); endrule
    
    rule c0 (check == 0); docheck(4); endrule
    rule c1 (check == 1); docheck(3); endrule
    rule c2 (check == 2); docheck(9); endrule
    rule c3 (check == 3); docheck(1); endrule
    rule c4 (check == 4); docheck(22); endrule
    rule c5 (check == 5); docheck(29); endrule
    rule c6 (check == 6); docheck(21); endrule
    rule c7 (check == 7); docheck(22); endrule

    rule finish (feed == 2 && check == 8);
        if (passed) begin
            $display("PASSED");
        end else begin
            $display("FAILED");
        end
        $finish();
    endrule

endmodule

