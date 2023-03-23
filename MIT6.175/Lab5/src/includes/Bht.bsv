import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;

interface DirectionPred#(numeric type bhtIndex);
    method Addr ppcDP(Addr pc, Addr targetPC);
    method Action update(Addr pc, Bool taken);
endinterface


module mkBHT(DirectionPred#(bhtIndex)) provisos( Add#(bhtIndex,a__,32), NumAlias#(TExp#(bhtIndex), bhtEntries) );

    //2^index Bht entries initialized to !weaklyTaken
    Vector# (bhtEntries, Reg#(Bit#(2))) bhtArr <-replicateM(mkReg(2'b01));

    //max and min allowable vals for dp Bits
    Bit#(2) maxDp = 2'b11; Bit#(2) minDp = 2'b00;

    //get rid of last two bits of PC and truncate it down to bht index size
    function Bit#(bhtIndex) getBhtIndex(Addr pc)  = truncate(pc >> 2) ;

    //if taken return targetPC. Otherwise return pc+4
    function Addr computeTarget(Addr pc, Addr targetPC, Bool taken) = taken ? targetPC : pc + 4;

    //if strongly/weakly taken, return True. Else False
    function Bool extractDir(Bit#(2) dpBits);

        Bool stronglyTaken = (2'b11 == dpBits);
        Bool weaklyTaken = (2'b10 == dpBits);
        return (stronglyTaken || weaklyTaken);

    endfunction

    //get the dPbits at the specified index
    function Bit#(2) getBhtEntry(Addr pc) = bhtArr[getBhtIndex(pc)];

    //if taken +1, if not -1 : flipped comparisions b/c of overflow
    function Bit#(2) newDpBits(Bit#(2) dpBits, Bool taken);

        if (taken) begin
            let newDp = dpBits + 1;
            return newDp == minDp ? maxDp : newDp;
        end
        else begin
            let newDp = dpBits - 1;
            return newDp == maxDp ? minDp : newDp;
        end
    endfunction


    //compute the ppc according to the bht array
    method Addr ppcDP(Addr pc, Addr targetPC);
        let direction = extractDir(getBhtEntry(pc));
        return computeTarget(pc, targetPC, direction);
    endmethod

    method Action update(Addr pc, Bool taken);
        let index = getBhtIndex(pc);
        let dpBits = getBhtEntry(pc);
        bhtArr[index] <=newDpBits(dpBits, taken);
    endmethod
endmodule