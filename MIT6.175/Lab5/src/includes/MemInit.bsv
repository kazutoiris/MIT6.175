
import GetPut::*;
import BRAM::*;

import Types::*;
import MemTypes::*;
import MemUtil::*;
import RegFile::*;
import Fifo::*;
import Memory::*;
import CacheTypes::*;

module mkMemInitRegFile(RegFile#(Bit#(16), Data) mem, MemInitIfc ifc);
    Reg#(Bool) initialized <- mkReg(False);

    interface Put request;
        method Action put(MemInit x) if (!initialized);
          case (x) matches
            tagged InitLoad .l: begin
                mem.upd(truncate(l.addr>>2), l.data);
            end

            tagged InitDone: begin
                initialized <= True;
            end
          endcase
        endmethod
    endinterface

    method Bool done() = initialized;

endmodule

module mkMemInitBRAM(BRAM1Port#(Bit#(16), Data) mem, MemInitIfc ifc);
    Reg#(Bool) initialized <- mkReg(False);

    interface Put request;
        method Action put(MemInit x) if (!initialized);
          case (x) matches
            tagged InitLoad .l: begin
                mem.portA.request.put(BRAMRequest {
                    write: True,
                    responseOnWrite: False,
                    address: truncate(l.addr>>2),
                    datain: l.data});
            end

            tagged InitDone: begin
                initialized <= True;
            end
          endcase
        endmethod
    endinterface

    method Bool done() = initialized;

endmodule

module mkMemInitWideMem(WideMem mem, MemInitIfc ifc);
    Reg#(Bool) initialized <- mkReg(False);

    interface Put request;
        method Action put(MemInit x) if (!initialized);
          case (x) matches
            tagged InitLoad .l: begin
               mem.req(toWideMemReq(MemReq{op:St,
                                           addr:l.addr,
                                           data:l.data}));
            end
            tagged InitDone: begin
                initialized <= True;
            end
          endcase
        endmethod
    endinterface

    method Bool done() = initialized;

endmodule

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

module mkDummyMemInit(MemInitIfc);
    Reg#(Bool) initialized <- mkReg(False);

    interface Put request;
        method Action put(MemInit x) if (!initialized);
          case (x) matches
            tagged InitDone: begin
                initialized <= True;
            end
          endcase
        endmethod
    endinterface

    method Bool done() = initialized;

endmodule
