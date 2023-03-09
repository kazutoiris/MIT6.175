
import Counter::*;
import FIFO::*;
import FixedPoint::*;

interface Multiplier;
    method Action putOperands(FixedPoint#(16, 16) coeff, Int#(16) samp);
    method ActionValue#(FixedPoint#(16, 16)) getResult();
endinterface

(* synthesize *)
module mkMultiplier (Multiplier);

    FIFO#(FixedPoint#(16, 16)) results <- mkFIFO();
    
    method Action putOperands(FixedPoint#(16, 16) coeff, Int#(16) samp);
        results.enq(coeff * fromInt(samp));
    endmethod

    method ActionValue#(FixedPoint#(16, 16)) getResult();
        results.deq();
        return results.first();
    endmethod

endmodule
