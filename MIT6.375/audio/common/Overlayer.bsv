
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import Vector::*;

import FShow::*;
import StmtFSM::*;

// Overlayer is the opposite of OverSampler.
// You give it a sequences of n sized chunks, and it will output a sequence of
// s sized chunks taken by overlaying those n sized chunks at interlvals of s
// elements, averaging together the overlapped values.

// We expect s, n to be powers of 2, with s less than n.
typedef Server#(
    Vector#(n, t),
    Vector#(s, t)
) Overlayer#(numeric type n, numeric type s, type t);

// The init parameter is the initial value of the window to use.
module mkOverlayer(Vector#(n, t) init, Overlayer#(n, s, t) ifc)
    provisos(Bits#(t, t_sz), Arith#(t), Bitwise#(t), Add#(s, a__, n));

    Reg#(Vector#(n, t)) window <- mkReg(init);
    FIFO#(Vector#(n, t)) infifo <- mkFIFO();
    FIFO#(Vector#(s, t)) outfifo <- mkFIFO();

    // Average src into dst.
    function t addin(t src, t dst);
        return (src >> valueof(TLog#(TDiv#(n, s)))) + dst;
    endfunction

    rule shiftout (True);
        Vector#(n, t) x <- toGet(infifo).get();
        Vector#(TSub#(n,s), t) tail = drop(window);
        let nwindow = zipWith(addin, x, append(tail, replicate(0)));
        window <= nwindow;
        outfifo.enq(take(nwindow));
    endrule

    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);

endmodule

module mkOverlayerTest(Empty);
    Overlayer#(8, 2, int) overlayer <- mkOverlayer(replicate(0));

    function Vector#(2, t) v2(t a, t b);
        Vector#(2, t) v = newVector;
        v[0] = a; v[1] = b;
        return v;
    endfunction

    function Vector#(8, t) v8(t a, t b, t c, t d, t e, t f, t g, t h);
        Vector#(8, t) v = newVector;
        v[0] = a; v[1] = b; v[2] = c; v[3] = d;
        v[4] = e; v[5] = f; v[6] = g; v[7] = h;
        return v;
    endfunction

    function Action checkis(Vector#(2, int) exp);
        action
            let x <- overlayer.response.get();
            if (x != exp) begin
                $display("wnt: ", fshow(exp));
                $display("got: ", fshow(x));
            end
        endaction
    endfunction


    Stmt feed = (seq
        overlayer.request.put(v8(12, 52, 20, 0, 8, 60, 32, 72));
        overlayer.request.put(v8(20, 0, 8, 60, 32, 72, 16, 24));
        overlayer.request.put(v8(8, 60, 32, 72, 16, 24, 4, 8));
        overlayer.request.put(v8(32, 72, 16, 24, 4, 8, 12, 16));
    endseq);

    Stmt take = (seq
        checkis(v2(0, 0));
        checkis(v2(3, 13));
        checkis(v2(10, 0));
        checkis(v2(6, 45));
    endseq);

    mkAutoFSM((par feed; take; endpar));

endmodule

