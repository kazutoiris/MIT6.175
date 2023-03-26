import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;

// indexSize is the number of bits in the index
interface Ras#(numeric type indexSize);
    method ActionValue#(Addr) pop();
    method Action push(Addr addr);
endinterface

// mkRas
module mkRas( Ras#(indexSize) );
    Vector#(TExp#(indexSize), Reg#(Addr)) stack <- replicateM(mkRegU);
    Reg#(Bit#(indexSize)) top <- mkReg(0);
    Bit#(indexSize) max_index = fromInteger(valueOf(indexSize)-1);
 
    function Bit#(indexSize) next(Bit#(indexSize) ptr);
	    return ptr == max_index ? 0 : ptr + 1;
    endfunction

    function Bit#(indexSize) prev(Bit#(indexSize) ptr);
        return ptr == 0 ? max_index : ptr - 1;
    endfunction

    method ActionValue#(Addr) pop();
	    let index = prev(top);
	    let rAddr = stack[index];
	    top <= index;
	    return rAddr;
    endmethod

    method Action push(Addr addr);
        stack[top] <= addr;
	    top <= next(top);
    endmethod

endmodule
