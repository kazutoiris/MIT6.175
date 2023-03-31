import RefTypes::*;
import ProcTypes::*;
import Types::*;
import MemTypes::*;
import CacheTypes::*;
import Vector::*;
import GetPut::*;

(* synthesize *)
module mkRefDummyMem(RefMem);
	Vector#(CoreNum, RefIMem) iVec = ?;
	Vector#(CoreNum, RefDMem) dVec = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		iVec[i] = (interface RefIMem;
			method Action fetch(Addr pc, Instruction inst);
				noAction;
			endmethod
		endinterface);
		dVec[i] = (interface RefDMem;
			method Action issue(MemReq req);
				noAction;
			endmethod
			method Action commit(MemReq req, Maybe#(CacheLine) line, Maybe#(MemResp) resp);
				noAction;
			endmethod
		endinterface);
	end

	interface iMem = iVec;
	interface dMem = dVec;
endmodule
