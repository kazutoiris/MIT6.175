import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;


// Counter functions
function Bit#(2) updateCounter(Bool dir, Bit#(2) counter);
  return dir?saturatingInc(counter)
            :saturatingDec(counter);
endfunction

function Bit#(2) saturatingInc(Bit#(2) counter);
  let plusOne = counter + 1;
  return (plusOne == 0)?counter:plusOne;
endfunction

function Bit#(2) saturatingDec(Bit#(2) counter);
  return (counter == 0)?0:counter-1;
endfunction

// indexSize is the number of bits in the index
interface Bht#(numeric type indexSize);
    method Bool predict(Addr addr);
    method Action train(Addr addr, Bool taken);
endinterface


module mkBht( Bht#(indexSize) ) provisos( Add#(indexSize,a__,32) );
    
    // Direction predictor state
    //RegFile#(Bit#(indexSize),Bit#(2)) cntArray <- mkRegFileFull();
    Vector#(TExp#(indexSize), Reg#(Bit#(2))) counterArray <- replicateM(mkReg(1));

    method Bool predict(Addr addr);
        
        Bit#(indexSize) index = truncate(addr >> 2);
        Bit#(2) counter = counterArray[index];
        Bit#(1) first = truncate(counter >> 1);
    
        Bool taken = (first == 1);

        return taken;
    endmethod

    method Action train(Addr addr, Bool taken);
       
        Bit#(indexSize) index = truncate(addr >> 2);
        Bit#(2) counter = counterArray[index];
        
        counterArray[index] <= updateCounter(taken, counter);
    endmethod
endmodule
