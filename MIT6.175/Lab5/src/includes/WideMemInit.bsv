import GetPut::*;
import Types::*;
import BRAM::*;
import Fifo::*;
import MemTypes::*;
import Memory::*;

module mkWideMemInitDDR3( Fifo#(n,DDR3_Req) reqQ, WideMemInitIfc ifc );
    // logic to initialize DRAM
    Reg#(Bool) initialized <- mkReg(False);

    interface Put request;
        method Action put(WideMemInit x) if (!initialized);
          case (x) matches
            tagged InitLoad .l: begin
                DDR3_Req ddr3_req = DDR3_Req {
					write: True, 
					byteen: maxBound, 
					address: (l.addr>>2), 
					data: l.data
				};
                reqQ.enq( ddr3_req );
            end
            tagged InitDone: begin
                initialized <= True;
				//$display("WideMemInit: init mem done");
            end
          endcase
        endmethod
    endinterface
    method Bool done() = initialized;
endmodule

