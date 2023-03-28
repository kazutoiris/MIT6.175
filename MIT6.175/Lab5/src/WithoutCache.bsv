import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import GetPut::*;
import FPGAMemory::*;
import Scoreboard::*;
import Bht::*;
import MemUtil::*;
import Memory::*;
import Cache::*;
import FIFO::*;
import SimMem::*;
import CacheTypes::*;
import MemInit::*;
import ClientServer::*;

typedef struct {
    Addr pc;
    Addr predPc;
    Bool canary;
} Fetch2Decode deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
    Bool canary;
} Decode2Register deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
    Bool canary;
} Register2Execute deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Maybe#(ExecInst) eInst;
} Execute2Memory deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Maybe#(ExecInst) eInst;
} Memory2WriteBack deriving (Bits, Eq);


module mkProc#(Fifo#(2, DDR3_Req) ddr3ReqFifo, Fifo#(2, DDR3_Resp) ddr3RespFifo)(Proc);
    Ehr#(3, Addr)                pcReg <- mkEhr(?);
    RFile                           rf <- mkBypassRFile;
	Scoreboard#(6)                  sb <- mkPipelineScoreboard;
    CsrFile                       csrf <- mkCsrFile;
    Btb#(6)                        btb <- mkBtb;
    Bht#(8)                        bht <- mkBht;
    Reg#(Bool)                  canary <- mkReg(False);
    Reg#(Int#(64))              cycles <- mkReg(0);

    Fifo#(8, Fetch2Decode)     f2dFifo <- mkPipelineFifo;
	Fifo#(8, Decode2Register)  d2rFifo <- mkPipelineFifo;
	Fifo#(8, Register2Execute) r2eFifo <- mkPipelineFifo;
	Fifo#(8, Execute2Memory)   e2mFifo <- mkPipelineFifo;
	Fifo#(8, Memory2WriteBack) m2wFifo <- mkPipelineFifo;

    Bool                      memReady =  True;
    let                        wideMem <- mkWideMemFromDDR3(ddr3ReqFifo,ddr3RespFifo);
    Vector#(2, WideMem)       splitMem <- mkSplitWideMem(memReady && csrf.started, wideMem);

    Cache iMem <- mkBypassCache(splitMem[1]);
    Cache dMem <- mkBypassCache(splitMem[0]);

    rule drainMemResponses(!csrf.started);
        $display("drain!");
        ddr3RespFifo.deq;
    endrule

    rule forceStop (csrf.started);
        cycles <= cycles + 1;
        if (cycles == 100000) begin
            $display("force stop: cycle = %d", cycles);
            $finish;
        end
    endrule

    rule doFetch(csrf.started);
		iMem.req(MemReq { op: Ld, addr: pcReg[0], data: ? });
		Addr predPc = btb.predPc(pcReg[0]);
        pcReg[0] <= predPc;
        let f2d = Fetch2Decode {
            pc: pcReg[0],
            predPc: predPc,
            canary: canary
        };
        f2dFifo.enq(f2d);
        $display("[fetch] PC = %x", f2d.pc);
    endrule

    rule doDecode (csrf.started);
        let f2d = f2dFifo.first;
        f2dFifo.deq;
        let inst <- iMem.resp;
		let dInst = decode(inst);
        let d2r = Decode2Register{
            pc: f2d.pc,
            predPc: f2d.predPc,
            dInst: dInst,
            canary: f2d.canary
        };
        d2rFifo.enq(d2r);
        $display("[decode] PC = %x", f2d.pc);
    endrule

    rule doRegisterFetch (csrf.started);
        let d2r = d2rFifo.first;
        let dInst = d2r.dInst;
		Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
		Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
		Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));
		let r2e = Register2Execute {
			pc: d2r.pc,
			predPc: d2r.predPc,
			dInst: d2r.dInst,
			rVal1: rVal1,
			rVal2: rVal2,
			csrVal: csrVal,
			canary: d2r.canary
		};
		if(!sb.search1(dInst.src1) && !sb.search2(dInst.src2)) begin
			r2eFifo.enq(r2e);
			sb.insert(dInst.dst);
            d2rFifo.deq;
			$display("[register] PC = %x", d2r.pc);
		end else begin
			$display("[register] PC = %x (stalled)", d2r.pc);
		end
	endrule

	rule doExecute (csrf.started);
		let r2e = r2eFifo.first;
		r2eFifo.deq;
        Maybe#(ExecInst) newEInst = Invalid;
		if(r2e.canary != canary) begin
			$display("[execute] canary mismatch. PC = %x", r2e.pc);
		end else begin
            $display("[execute] PC = %x", r2e.pc);
			let eInst = exec(r2e.dInst, r2e.rVal1, r2e.rVal2, r2e.pc, r2e.predPc, r2e.csrVal);
            if (eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", r2e.pc);
                $finish;
            end
            newEInst = Valid(eInst);
            if (eInst.iType == J || eInst.iType == Jr || eInst.iType == Br) begin
                btb.update(r2e.pc, eInst.addr);
            end
            if (eInst.mispredict) begin
                pcReg[1] <= eInst.addr;
                canary <= !canary;
            end
        end
        let e2m = Execute2Memory{
            pc: r2e.pc,
            eInst: newEInst
        };
        e2mFifo.enq(e2m);
    endrule

    rule doMemory (csrf.started);
        let e2m = e2mFifo.first;
        e2mFifo.deq;

        if (isValid(e2m.eInst)) begin
            let eInst = fromMaybe(?, e2m.eInst);
            if(eInst.iType == Ld) begin
                dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
            end else if(eInst.iType == St) begin
                dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
            end
            $display("[memory] PC = %x", e2m.pc);
        end else begin
            $display("[memory] canary mismatch. PC = %x", e2m.pc);
        end
        let m2w = Memory2WriteBack{
            pc: e2m.pc,
            eInst: e2m.eInst
        };
        m2wFifo.enq(m2w);
    endrule

    rule doWriteBack (csrf.started);
        let m2w = m2wFifo.first;
        m2wFifo.deq;
        if (isValid(m2w.eInst)) begin
            let eInst = fromMaybe(?, m2w.eInst);
            if(eInst.iType == Ld) begin
                eInst.data <- dMem.resp;
            end
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
            end
            csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
            $display("[writeback] PC = %x", m2w.pc);
        end else begin
            $display("[writeback] canary mismatch. PC = %x", m2w.pc);
        end
        sb.remove;
	endrule

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
	$display("Start cpu");
        csrf.start(0); // only 1 core, id = 0
        pcReg[0] <= startpc;
    endmethod


endmodule
