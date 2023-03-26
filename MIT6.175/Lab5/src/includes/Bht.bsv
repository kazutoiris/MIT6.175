import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;
import Ehr::*;

// indexSize is the number of bits in the index
interface Bht#(numeric type indexSize);
    method Addr predPc(Addr pc, Addr ppc);
    method Action update(Addr pc, Bool taken);
endinterface

typedef Bit#(2) BhtDirection;
BhtDirection strongTaken = 2'b11;
BhtDirection weakTaken = 2'b10;
BhtDirection weakNotTaken = 2'b01;
BhtDirection strongNotTaken = 2'b00;



// mkBHT
module mkBht( Bht#(indexSize) ) provisos( Add#(indexSize,a__,32));
    Vector#(TExp#(indexSize), Reg#(BhtDirection)) directions <- replicateM(mkReg(weakNotTaken));

    method Addr predPc(Addr pc, Addr ppc);

        //removes the last 2 bits (always 0) and adjusts the length to the BHT current entry length
        Bit#(indexSize) bhtEntry = truncate(pc >> 2);
        //retrieves the predictor from the vector
        BhtDirection predictor = directions[bhtEntry];
        
        Bit#(1) decisionBit = truncate(predictor >> 1);
        if (decisionBit  == 1)
        begin
            return ppc;
        end
        else
        begin
            return pc + 4;
        end

    endmethod

    method Action update(Addr pc, Bool taken);

        //removes the last 2 bits (always 0) and adjusts the length to the BHT current entry length
        Bit#(indexSize) bhtEntry = truncate(pc >> 2);
        //retrieves the predictor from the vector
        BhtDirection predictor = directions[bhtEntry];

        directions[bhtEntry] <= updatePredictor(predictor, taken);
    endmethod

endmodule



//-------predictor update functions------------------------------------

function BhtDirection updatePredictor(BhtDirection previousPredictor, Bool taken);

    return taken? takenUpdate(previousPredictor) : notTakenUpdate(previousPredictor);

endfunction


function BhtDirection takenUpdate(BhtDirection previousPredictor);

    BhtDirection newPredictor = 2'b00;

    case(previousPredictor) matches
        2'b11 : newPredictor = 2'b11;
        2'b10 : newPredictor = 2'b11;
        2'b01 : newPredictor = 2'b11;
        2'b00 : newPredictor = 2'b01;
    endcase

    return newPredictor;

endfunction


function BhtDirection notTakenUpdate(BhtDirection previousPredictor);

    BhtDirection newPredictor = 2'b00;

    case(previousPredictor) matches
        2'b11 : newPredictor = 2'b10;
        2'b10 : newPredictor = 2'b00;
        2'b01 : newPredictor = 2'b00;
        2'b00 : newPredictor = 2'b00;
    endcase

    return newPredictor;

endfunction
