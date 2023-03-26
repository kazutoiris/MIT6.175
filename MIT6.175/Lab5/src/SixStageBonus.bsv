import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import Scoreboard::*;
import DelayedMemory::*;
import GetPut::*;
import Bht::*;

typedef struct {
    Addr pc;
    Addr predPc;
    Bool canary;
    Bool canary2;
    Bool canary3;
} Fetch2Decode deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
    Bool canary;
    Bool canary3;
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

typedef struct{
    Addr nextPc;
} DecRedirect deriving (Bits,Eq);


(* synthesize *)
module mkProc(Proc);
    Ehr#(2, Addr)   pcReg <- mkEhr(?);
    RFile              rf <- mkBypassRFile;
	Scoreboard#(6)     sb <- mkPipelineScoreboard;
	DelayedMemory    iMem <- mkDelayedMemory;
    DelayedMemory    dMem <- mkDelayedMemory;
    CsrFile          csrf <- mkCsrFile;
    Btb#(6)           btb <- mkBtb;
    Bht#(8)           bht <- mkBht;
    Ehr#(2,Bool)   canary <- mkEhr(False);
    Ehr#(2,Bool)  canary2 <- mkEhr(False);
    Ehr#(2,Bool)  canary3 <- mkEhr(False);
    Reg#(Int#(64)) cycles <- mkReg(0);

    Fifo#(8, Fetch2Decode)     f2dFifo <- mkPipelineFifo;
	Fifo#(8, Decode2Register)  d2rFifo <- mkPipelineFifo;
	Fifo#(8, Register2Execute) r2eFifo <- mkPipelineFifo;
	Fifo#(8, Execute2Memory)   e2mFifo <- mkPipelineFifo;
	Fifo#(8, Memory2WriteBack) m2wFifo <- mkPipelineFifo;

    function Addr getTargetPc(Data val, Maybe#(Data) imm) = { truncateLSB(val + fromMaybe(?, imm)), 1'b0 };

    Bool memReady = iMem.init.done && dMem.init.done;
    rule test (!memReady);
        let e = tagged InitDone;
        iMem.init.request.put(e);
        dMem.init.request.put(e);
        $display("Initializing memory");
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
            canary: canary[1],
            canary2: canary2[1],
            canary3: canary3[1]
        };
        f2dFifo.enq(f2d);
        $display("[fetch] PC = %x", f2d.pc);
    endrule

    rule doDecode (csrf.started);
        let f2d = f2dFifo.first;
        f2dFifo.deq;
        let inst <- iMem.resp;
        if (f2d.canary2 == canary2[0]) begin
            $display("[decode] PC = %x", f2d.pc);
            let dInst = decode(inst);
            let predPc = f2d.predPc;
            if(dInst.iType == J || dInst.iType == Br) begin
                let bhtPred = bht.predPc(f2d.pc,f2d.predPc);
                if(bhtPred != f2d.predPc) begin
                    canary2[0] <= !canary2[0];
                    pcReg[1] <= bhtPred;
                    predPc = bhtPred;
                    $display("[decode] PC = %x %x -> %x (misprediction)", f2d.pc, f2d.predPc, bhtPred);
                end
            end
            let d2r = Decode2Register{
                pc: f2d.pc,
                predPc: predPc,
                dInst: dInst,
                canary: f2d.canary,
                canary3: f2d.canary3
            };
            d2rFifo.enq(d2r);
        end
        else begin
            $display("[decode] canary mismatch. PC = %x", f2d.pc);
        end
    endrule

    rule doRegisterFetch (csrf.started);
        let d2r = d2rFifo.first;
        let dInst = d2r.dInst;
		let rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
		let rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
		let csrVal = csrf.rd(fromMaybe(?, dInst.csr));
        if (d2r.canary3 == canary3[0]) begin
            if(!sb.search1(dInst.src1) && !sb.search2(dInst.src2)) begin
                let r2e = Register2Execute {
                    pc: d2r.pc,
                    predPc: d2r.predPc,
                    dInst: d2r.dInst,
                    rVal1: rVal1,
                    rVal2: rVal2,
                    csrVal: csrVal,
                    canary: d2r.canary
                };
                r2eFifo.enq(r2e);
                sb.insert(dInst.dst);
                d2rFifo.deq;
                $display("[register] PC = %x", d2r.pc);
                let ppc = (d2r.dInst.iType == Jr) ? bht.predPc(d2r.pc, getTargetPc(rVal1, dInst.imm)) : d2r.predPc;
                if (ppc != d2r.predPc) begin
                    $display("[register] PC = %x %x -> %x (misprediction)", d2r.pc, d2r.predPc, ppc);
                    canary3[0] <= !canary3[0];
                    pcReg[1] <= ppc;
                end
            end else begin
                $display("[register] PC = %x (stalled)", d2r.pc);
            end
        end
	endrule

	rule doExecute (csrf.started);
		let r2e = r2eFifo.first;
		r2eFifo.deq;
        Maybe#(ExecInst) newEInst = Invalid;
		if(r2e.canary != canary[0]) begin
			$display("[execute] canary mismatch. PC = %x", r2e.pc);
		end else begin
			let eInst = exec(r2e.dInst, r2e.rVal1, r2e.rVal2, r2e.pc, r2e.predPc, r2e.csrVal);
            $display("[execute] PC = %x -> %x", r2e.pc, eInst.addr);
            if (eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", r2e.pc);
                $finish;
            end
            newEInst = Valid(eInst);
            if (eInst.iType == J || eInst.iType == Jr || eInst.iType == Br) begin
                btb.update(r2e.pc, eInst.addr);
                bht.update(r2e.pc, eInst.brTaken);
            end
            if (eInst.mispredict) begin
                pcReg[1] <= eInst.addr;
                canary[0] <= !canary[0];
                $display("[execute] PC = %x -> %x (mispredict)", r2e.pc, eInst.addr);
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

	interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
