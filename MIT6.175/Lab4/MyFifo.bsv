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
    Reg#(Bool)              notEmpty <- mkReg(False);
    Reg#(Bool)              notFull  <- mkReg(True);
    Bit#(TLog#(n))          size     = fromInteger(valueOf(n)-1);

    method Bool notFull();
        return notFull;
    endmethod

    method Action enq (t x) if (notFull);
        notEmpty <= True;
        data[enqP] <= x;
        let nextEnqP = enqP + 1;
        if (nextEnqP > size) begin
            nextEnqP = 0;
        end
        if (nextEnqP == deqP) begin
            notFull <= False;
        end
        enqP <= nextEnqP;
    endmethod

    method Bool notEmpty();
        return notEmpty;
    endmethod

    method Action deq() if (notEmpty);
        notFull <= True;
        let nextDeqP = deqP + 1;
        if (nextDeqP > size) begin
            nextDeqP = 0;
        end
        if (nextDeqP == enqP) begin
            empty <= True;
        end
        deqP <= nextDeqP;
    endmethod

    method t first() if (notEmpty);
        return data[deqP];
    endmethod

    method Action clear();
        deqP <= 0;
        enqP <= 0;
        notEmpty <= False;
        notFull <= True;
    endmethod

endmodule

// {notEmpty, first, deq} < {notFull, enq} < clear
module mkMyPipelineFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(3, Bit#(TLog#(n))) enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) deqP     <- mkEhr(0);
    Ehr#(3, Bool)           notEmpty <- mkEhr(False);
    Ehr#(3, Bool)           notFull  <- mkEhr(True);
    Bit#(TLog#(n))          size     = fromInteger(valueOf(n)-1);

    // 0

    method Bool notEmpty();
        return notEmpty[0];
    endmethod

    method Action deq() if (notEmpty[0]);
        notFull[0] <= True;
        let nextDeqP = deqP[0] + 1;
        if (nextDeqP > size) begin
            nextDeqP = 0;
        end
        if (nextDeqP == enqP[0]) begin
            notEmpty[0] <= False;
        end
        deqP[0] <= nextDeqP;
    endmethod

    // 1

    method Bool notFull();
        return notFull[1];
    endmethod

    method Action enq (t x) if (notFull[1]);
        notEmpty[1] <= True;
        data[enqP[1]] <= x;
        let nextEnqP = enqP[1] + 1;
        if (nextEnqP > size) begin
            nextEnqP = 0;
        end
        if (nextEnqP == deqP[1]) begin
            notFull[1] <= False;
        end
        enqP[1] <= nextEnqP;
    endmethod

    method t first() if (notEmpty[0]);
        return data[deqP[0]];
    endmethod

    // 2

    method Action clear();
        deqP[2]     <= 0;
        enqP[2]     <= 0;
        notEmpty[2] <= False;
        notFull[2]  <= True;
    endmethod

endmodule

// {notFull, enq} < {notEmpty, first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Ehr#(2, t))  data     <- replicateM(mkEhrU());
    Ehr#(3, Bit#(TLog#(n))) enqP     <- mkEhr(0);
    Ehr#(3, Bit#(TLog#(n))) deqP     <- mkEhr(0);
    Ehr#(3, Bool)           notEmpty <- mkEhr(False);
    Ehr#(3, Bool)           notFull  <- mkEhr(True);
    Bit#(TLog#(n))          size     = fromInteger(valueOf(n)-1);

    // 0

    method Bool notFull();
        return notFull[0];
    endmethod

    method Action enq (t x) if (notFull[0]);
        notEmpty[0] <= True;
        data[enqP[0]][0] <= x;
        let nextEnqP = enqP[0] + 1;
        if (nextEnqP > size) begin
            nextEnqP = 0;
        end
        if (nextEnqP == deqP[0]) begin
            notFull[0] <= False;
        end
        enqP[0] <= nextEnqP;
    endmethod

    // 1

    method Bool notEmpty();
        return notEmpty[1];
    endmethod

    method Action deq() if (notEmpty[1]);
        notFull[1] <= True;
        let nextDeqP = deqP[1] + 1;
        if (nextDeqP > size) begin
            nextDeqP = 0;
        end
        if (nextDeqP == enqP[1]) begin
            notEmpty[1] <= False;
        end
        deqP[1] <= nextDeqP;
    endmethod

    method t first() if (notEmpty[1]);
        return data[deqP[1]][1];
    endmethod

    // 2

    method Action clear();
        deqP[2] <= 0;
        enqP[2] <= 0;
        notEmpty[2] <= False;
        notFull[2] <= True;
    endmethod
endmodule

// {notFull, enq, notEmpty, first, deq} < clear
module mkMyCFFifo( Fifo#(n, t) ) provisos (Bits#(t,tSz));
    // n is size of fifo
    // t is data type of fifo
    Vector#(n, Reg#(t))     data         <- replicateM(mkRegU());
    Ehr#(2, Bit#(TLog#(n))) enqP         <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(n))) deqP         <- mkEhr(0);
    Ehr#(2, Bool)           notEmpty     <- mkEhr(False);
    Ehr#(2, Bool)           notFull      <- mkEhr(True);
    Ehr#(2, Bool)           req_deq      <- mkEhr(False);
    Ehr#(2, Maybe#(t))      req_enq      <- mkEhr(tagged Invalid);
    Bit#(TLog#(n))          size         = fromInteger(valueOf(n)-1);

    (*no_implicit_conditions, fire_when_enabled*)
    rule canonicalize;
        // enq and deq
        if ((notFull[0] && isValid(req_enq[1])) && (notEmpty[0] && req_deq[1])) begin
            notEmpty[0] <= True;
            notFull[0] <= True;
            data[enqP[0]] <= fromMaybe(?, req_enq[1]);
            enqP[0] <= nextEnqP;
            deqP[0] <= nextDeqP;
        // deq only
        end else if (notEmpty[0] && req_deq[1]) begin
            if (nextDeqP == enqP[0]) begin
                notEmpty[0] <= False;
            end
            notFull[0] <= True;
            deqP[0] <= nextDeqP;
        // enq only
        end else if (notFull[0] && isValid(req_enq[1])) begin
            if (nextEnqP == deqP[0]) begin
                notFull[0] <= False;
            end
            notEmpty[0] <= True;
            data[enqP[0]] <= fromMaybe(?, req_enq[1]);
            enqP[0] <= nextEnqP;
        end
        req_enq[1] <= tagged Invalid;
        req_deq[1] <= False;
    endrule

    method Bool notFull();
        return notFull[0];
    endmethod

    method Action enq (t x) if (notFull[0]);
        req_enq[0] <= tagged Valid (x);
    endmethod

    method Bool notEmpty();
        return notEmpty[0];
    endmethod

    method Action deq() if (notEmpty[0]);
        req_deq[0] <= True;

    endmethod

    method t first() if (notEmpty[0]);
        return data[deqP[0]];
    endmethod

    method Action clear();
        enqP[1] <= 0;
        deqP[1] <= 0;
        notEmpty[1] <= False;
        notFull[1] <= True;
    endmethod

endmodule
