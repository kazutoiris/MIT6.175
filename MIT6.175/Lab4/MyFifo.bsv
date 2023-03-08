import Ehr::*;
import Vector::*;

interface Fifo#(numeric type n, type t);
    method Bool notFull;
    method Action enq(t x);
    method Bool notEmpty;
    method Action deq;
    method t first;
    method Action clear;
endinterface

module mkMyConflictFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Reg#(Bit#(TLog#(n)))    enqP     <- mkReg(0);
    Reg#(Bit#(TLog#(n)))    deqP     <- mkReg(0);
    Reg#(Bit#(TLog#(n)))    size     <- mkReg(0);

    method Bool notFull();
        return !(size == fromInteger(valueOf(n)));
    endmethod

    method Action enq (t x) if (!(size == fromInteger(valueOf(n))));
        data[enqP] <= x;
        enqP <= (enqP + 1) % fromInteger(valueOf(n));
        size <= size + 1;
    endmethod

    method Bool notEmpty();
        return !(size == 0);
    endmethod

    method Action deq() if (!(size == 0));
        deqP <= (deqP + 1) % fromInteger(valueOf(n));
        size <= size - 1;
    endmethod

    method t first() if (!(size == 0));
        return data[deqP];
    endmethod

    method Action clear();
        deqP <= 0;
        enqP <= 0;
        size <= 0;
    endmethod

endmodule

// {notEmpty, first, deq} < {notFull, enq} < clear
module mkMyPipelineFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(3, Bit#(TLog#(n))) enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) deqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) size     <- mkEhr(0);

    // 0

    method Bool notEmpty();
        return !(size[0] == 0);
    endmethod

    method Action deq() if (!(size[0] == 0));
        deqP[0] <= (deqP[0] + 1) % fromInteger(valueOf(n));
        size[0] <= size[0] - 1;
    endmethod

    method t first() if (!(size[0] == 0));
        return data[deqP[0]];
    endmethod

    // 1

    method Bool notFull();
        return !(size[1] == fromInteger(valueOf(n)));
    endmethod

    method Action enq (t x) if (!(size[1] == fromInteger(valueOf(n))));
        size[1] <= size[1] + 1;
        data[enqP[1]] <= x;
        enqP[1] <= (enqP[1] + 1) % fromInteger(valueOf(n));
    endmethod

    // 2

    method Action clear();
        deqP[2] <= 0;
        enqP[2] <= 0;
        size[2] <= 0;
    endmethod

endmodule

// {notFull, enq} < {notEmpty, first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Ehr#(2, t))  data     <- replicateM(mkEhrU());
    Ehr#(3, Bit#(TLog#(n))) enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) deqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) size     <- mkEhr(0);

    // 0

    method Bool notFull();
        return !(size[0] == fromInteger(valueOf(n)));
    endmethod

    method Action enq (t x) if (!(size[0] == fromInteger(valueOf(n))));
        data[enqP[0]][0] <= x;
        enqP[0] <= (enqP[0] + 1) % fromInteger(valueOf(n));
        size[0] <= size[0] + 1;
    endmethod

    // 1

    method Bool notEmpty();
        return !(size[1] == 0);
    endmethod

    method Action deq() if (!(size[1] == 0));
        deqP[1] <= (deqP[1] + 1) % fromInteger(valueOf(n));
        size[1] <= size[1] - 1;
    endmethod

    method t first() if (!(size[1] == 0));
        return data[deqP[1]][1];
    endmethod

    // 2

    method Action clear();
        deqP[2] <= 0;
        enqP[2] <= 0;
        size[2] <= 0;
    endmethod
endmodule

// {notFull, enq, notEmpty, first, deq} < clear
module mkMyCFFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data         <- replicateM(mkRegU());
    Ehr#(2, Bit#(TLog#(n))) enqP         <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(n))) deqP         <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(n))) size         <- mkEhr(0);

    Ehr#(2, Bool)           req_deq      <- mkEhr(False);
    Ehr#(2, Maybe#(t))      req_enq      <- mkEhr(tagged Invalid);

    (*no_implicit_conditions, fire_when_enabled*)
    rule canonicalize;
        // enq and deq
        if ((!(size[0] == fromInteger(valueOf(n))) && isValid(req_enq[1])) && (!(size[0] == 0) && req_deq[1])) begin
            data[enqP[0]] <= fromMaybe(?, req_enq[1]);
            enqP[0] <= (enqP[0] + 1) % fromInteger(valueOf(n));
            deqP[0] <= (deqP[0] + 1) % fromInteger(valueOf(n));
        // deq only
        end else if (!(size[0] == 0) && req_deq[1]) begin
            deqP[0] <= (deqP[0] + 1) % fromInteger(valueOf(n));
            size[0] <= size[0] - 1;
        // enq only
        end else if (!(size[0] == fromInteger(valueOf(n))) && isValid(req_enq[1])) begin
            enqP[0] <= (enqP[0] + 1) % fromInteger(valueOf(n));
            data[enqP[0]] <= fromMaybe(?, req_enq[1]);
            size[0] <= size[0] + 1;
        end
        req_enq[1] <= tagged Invalid;
        req_deq[1] <= False;
    endrule

    method Bool notFull();
        return !(size[0] == fromInteger(valueOf(n)));
    endmethod

    method Action enq (t x) if (!(size[0] == fromInteger(valueOf(n))));
        req_enq[0] <= tagged Valid (x);
    endmethod

    method Bool notEmpty();
        return !(size[0] == 0);
    endmethod

    method Action deq() if (!(size[0] == 0));
        req_deq[0] <= True;
    endmethod

    method t first() if (!(size[0] == 0));
        return data[deqP[0]];
    endmethod

    method Action clear();
        enqP[1] <= 0;
        deqP[1] <= 0;
        size[1] <= 0;
    endmethod

endmodule
