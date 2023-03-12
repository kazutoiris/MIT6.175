
import ClientServer::*;
import GetPut::*;
import FIFO::*;

import Vector::*;

import FShow::*;
import StmtFSM::*;

// An OverSampler samples overlapping windows of data.
// For example, say we want to sample with a window size of n=16 elements, but
// we only want to move the window s=2 elements over each time we sample. This
// means each datum will be sampled 16/2 = 8 times.
//
// To use the oversampler, input the data in chunks of size s. It will output
// the windows of size n properly overlapped.

typedef Server#(
    Vector#(s, t),
    Vector#(n, t)
) OverSampler#(numeric type s, numeric type n, type t);

// The parameter init specifies the initial value of the window.
module mkOverSampler(Vector#(n, t) init, OverSampler#(s, n, t) ifc)
    provisos(Add#(s, a__, n), Bits#(t, t_sz));

    Reg#(Vector#(n, t)) window <- mkReg(init);

    FIFO#(Vector#(s, t)) infifo <- mkFIFO();
    FIFO#(Vector#(n, t)) outfifo <- mkFIFO();

    rule shiftin (True);
        Vector#(s, t) x <- toGet(infifo).get();
        Vector#(n, t) nwindow = append(drop(window), x);
        window <= nwindow;
        outfifo.enq(nwindow);
    endrule

    interface Put request = toPut(infifo);
    interface Get response = toGet(outfifo);
    
endmodule

module mkOverSamplerTest(Empty);
    OverSampler#(2, 8, int) sampler <- mkOverSampler(replicate(0));

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

    function Action checkis(Vector#(8, int) exp);
        action
            let x <- sampler.response.get();
            if (x != exp) begin
                $display("wnt: ", fshow(exp));
                $display("got: ", fshow(x));
            end
        endaction
    endfunction


    Stmt feed = (seq
        sampler.request.put(v2(1, 5));
        sampler.request.put(v2(2, 0));
        sampler.request.put(v2(8, 6));
        sampler.request.put(v2(3, 7));
    endseq);

    Stmt take = (seq
        checkis(v8(0, 0, 0, 0, 0, 0, 1, 5));
        checkis(v8(0, 0, 0, 0, 1, 5, 2, 0));
        checkis(v8(0, 0, 1, 5, 2, 0, 8, 6));
        checkis(v8(1, 5, 2, 0, 8, 6, 3, 7));
    endseq);

    mkAutoFSM((par feed; take; endpar));

endmodule

