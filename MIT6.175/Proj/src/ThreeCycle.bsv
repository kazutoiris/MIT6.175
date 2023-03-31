import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import ICache::*;
import DCache::*;
import DCacheStQ::*;
import DCacheLHUSM::*;
import MemReqIDGen::*;
import CacheTypes::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MessageFifo::*;
import RefTypes::*;


typedef enum {
	Fetch,
	Execute,
	Commit
} Stage deriving(Bits, Eq, FShow);

module mkCore#(CoreID id)(
	WideMem iMem, 
	RefDMem refDMem, // debug: reference data mem
	Core ifc
);
    Reg#(Addr)        pc <- mkRegU;
    CsrFile         csrf <- mkCsrFile(id);
    RFile             rf <- mkRFile;

	Reg#(ExecInst) eInstReg <- mkRegU; 
	Reg#(Stage)       stage <- mkReg(Fetch);

	// mem req id
	MemReqIDGen memReqIDGen <- mkMemReqIDGen;

	// I mem
	ICache        iCache <- mkICache(iMem);

	// D cache
	MessageFifo#(2) toParentQ <- mkMessageFifo;
	MessageFifo#(2) fromParentQ <- mkMessageFifo;
`ifdef LHUSM
	DCache dCache <- mkDCacheLHUSM(
`elsif STQ
    DCache dCache <- mkDCacheStQ(
`else
    DCache dCache <- mkDCache(
`endif
		id,
		toMessageGet(fromParentQ),
		toMessagePut(toParentQ),
		refDMem
	);

	rule doFetch(csrf.started && stage == Fetch);
		iCache.req(pc);
		stage <= Execute;
		$display("%0t: core %d: Fetch: PC = %h", $time, id, pc);
	endrule

	rule doExecute(csrf.started && stage == Execute);
		let inst <- iCache.resp;
		// decode & reg read & exe
		let dInst = decode(inst);
		let rVal1 = rf.rd1(validValue(dInst.src1));
		let rVal2 = rf.rd2(validValue(dInst.src2));
		let csrVal = csrf.rd(validValue(dInst.csr));
		let eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);
		// print trace
        $display("%0t: core %d: Exe: inst (%h) expanded: ", $time, id, inst, showInst(inst));
		// check unsupported instruction
		if(eInst.iType == Unsupported) begin
			$fwrite(stderr, "ERROR: Executing unsupported instruction. Exiting\n");
			$finish;
		end
		// access D$
		if(eInst.iType == Ld) begin
			let rid <- memReqIDGen.getID;
			let r = MemReq{op: Ld, addr: eInst.addr, data: ?, rid: rid};
			dCache.req(r);
			$display("Exe: issue mem req ", fshow(r), "\n");
		end
		else if(eInst.iType == St) begin
			let rid <- memReqIDGen.getID;
			let r = MemReq{op: St, addr: eInst.addr, data: eInst.data, rid: rid};
			dCache.req(r);
			$display("Exe: issue mem req ", fshow(r), "\n");
		end
		else if(eInst.iType == Lr) begin
			let rid <- memReqIDGen.getID;
			let r = MemReq{op: Lr, addr: eInst.addr, data: ?, rid: rid};
			dCache.req(r);
			$display("Exe: issue mem req ", fshow(r), "\n");
		end
		else if(eInst.iType == Sc) begin
			let rid <- memReqIDGen.getID;
			let r = MemReq{op: Sc, addr: eInst.addr, data: eInst.data, rid: rid};
			dCache.req(r);
			$display("Exe: issue mem req ", fshow(r), "\n");
		end
		else if(eInst.iType == Fence) begin
			let rid <- memReqIDGen.getID;
			let r = MemReq{op: Fence, addr: ?, data: ?, rid: rid};
			dCache.req(r);
			$display("Exe: issue mem req ", fshow(r), "\n");
		end
		else begin
			$display("Exe: no mem op");
		end
		// save eInst & change stage
		eInstReg <= eInst;
		stage <= Commit;
	endrule

	rule doCommit(csrf.started && stage == Commit);
		ExecInst eInst = eInstReg;
		// get mem resp for Ld/Lr/Sc
		if(eInst.iType == Ld || eInst.iType == Lr || eInst.iType == Sc) begin
			eInst.data <- dCache.resp;
		end
		// write back to reg file
		if(isValid(eInst.dst)) begin
			rf.wr(fromMaybe(?, eInst.dst), eInst.data);
		end
		csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
		$display("%0t: core %d: Commit, eInst.data = %h", $time, id, eInst.data);
		// change PC
		pc <= eInst.brTaken ? eInst.addr : pc+4;
		// change stage
		stage <= Fetch;
	endrule

	interface MessageGet toParent = toMessageGet(toParentQ);
	interface MessagePut fromParent = toMessagePut(fromParentQ);

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

	method Bool cpuToHostValid = csrf.cpuToHostValid;

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
        csrf.start;
        pc <= startpc;
    endmethod
endmodule

