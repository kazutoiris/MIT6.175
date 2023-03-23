import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;
import Ehr::*;


interface BHT#(numeric type bhtIndex);
    method Addr predPc(Addr pc, Addr targetPC);
    method Action update(Addr pc, Bool taken);
endinterface

module mkBypassBHT(BHT#(bhtIndex)) provisos( Add#(bhtIndex, a__, 32), NumAlias#(TExp#(bhtIndex), bhtEntries) );
    Vector#(bhtEntries, Ehr#(2, Bit#(2))) bhtArr <- replicateM(mkEhr(2'b01));

    function Bool direcPred(Bit#(2) val);
        Bit#(1) high = truncate(val >> 1);
        return (high == 1);
    endfunction

    function Bit#(2) getEntry(Addr pc);
        Bit#(bhtIndex) index = truncate(pc >> 2);
        return bhtArr[index][0];
    endfunction

    method Addr predPc(Addr pc, Addr targetPC);
        let taken = direcPred(getEntry(pc));
        let target = taken?  targetPC : pc + 4;
        return target;
    endmethod

    method Action update(Addr pc, Bool taken);
        Bit#(bhtIndex) index = truncate(pc >> 2);
        let old = getEntry(pc);
        Bit#(2) newEntry = ?;
        Bit#(2) maxDp = 2'b11;
        Bit#(2) minDp = 2'b00;
        if (taken) begin
            newEntry = old+1;
            newEntry = newEntry == minDp? maxDp : newEntry;
        end else begin
            newEntry = old-1;
            newEntry = newEntry == maxDp? minDp : newEntry;
        end
        bhtArr[index][1] <= newEntry;
    endmethod
endmodule

module mkBHT(BHT#(bhtIndex)) provisos( Add#(bhtIndex, a__, 32), NumAlias#(TExp#(bhtIndex), bhtEntries) );
    Vector#(bhtEntries, Reg#(Bit#(2))) bhtArr <- replicateM(mkReg(2'b01));

    function Bool direcPred(Bit#(2) val);
        Bit#(1) high = truncate(val >> 1);
        return (high == 1);
    endfunction

    function Bit#(2) getEntry(Addr pc);
        Bit#(bhtIndex) index = truncate(pc >> 2);
        return bhtArr[index];
    endfunction

    method Addr predPc(Addr pc, Addr targetPC);
        let taken = direcPred(getEntry(pc));
        let target = taken?  targetPC : pc + 4;
        return target;
    endmethod

    method Action update(Addr pc, Bool taken);
        Bit#(bhtIndex) index = truncate(pc >> 2);
        let old = getEntry(pc);
        Bit#(2) newEntry = ?;
        Bit#(2) maxDp = 2'b11;
        Bit#(2) minDp = 2'b00;
        if (taken) begin
            newEntry = old+1;
            newEntry = newEntry == minDp? maxDp : newEntry;
        end else begin
            newEntry = old-1;
            newEntry = newEntry == maxDp? minDp : newEntry;
        end
        bhtArr[index] <= newEntry;
    endmethod
endmodule
