import Types::*;
import CMemTypes::*;
import RegFile::*;
import MemInit::*;

interface IMemory;
    method MemResp req(Addr a);
    interface MemInitIfc init;
endinterface

(* synthesize *)
module mkIMemory(IMemory);
	// In simulation we always init memory from a fixed VMH file (for speed)
	RegFile#(Bit#(16), Data) mem <- mkRegFileFullLoad("mem.vmh");
	MemInitIfc memInit <- mkDummyMemInit;
   // RegFile#(Bit#(16), Data) mem <- mkRegFileFull();
   // MemInitIfc memInit <- mkMemInitRegFile(mem);

    method MemResp req(Addr a) if (memInit.done());
        return mem.sub(truncate(a>>2));
    endmethod

    interface MemInitIfc init = memInit;
endmodule

