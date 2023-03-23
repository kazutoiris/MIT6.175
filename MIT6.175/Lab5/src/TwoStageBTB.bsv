// TwoStageBTB.bsv
//
// This is a two stage pipelined (with BTB) implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DMemory::*;
import IMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import GetPut::*;

typedef struct {
	DecodedInst dInst;
	Addr pc;
	Addr predPc;
} Dec2Ex deriving (Bits, Eq);

(* synthesize *)
module mkProc(Proc);
    Ehr#(2, Addr) pc <- mkEhrU;
    RFile         rf <- mkRFile;
	IMemory     iMem <- mkIMemory;
    DMemory     dMem <- mkDMemory;
    CsrFile     csrf <- mkCsrFile;
    Btb#(6)      btb <- mkBtb;

    Bool memReady = iMem.init.done() && dMem.init.done();
    rule test (!memReady);
    let e = tagged InitDone;
    iMem.init.request.put(e);
    dMem.init.request.put(e);
    endrule

    Fifo#(2, Dec2Ex) d2e <- mkCFFifo;

    //doFetchDecode < doExecute
    rule doFetchDecode(csrf.started);
        let inst = iMem.req(pc[0]);
        let ppc = btb.predPc(pc[0]);
        pc[0] <= ppc;
        let dInst = decode(inst);
        d2e.enq(Dec2Ex{ pc: pc[0], predPc: ppc, dInst: dInst });
    endrule

    rule doExecute(csrf.started);
        let bundle = d2e.first;
        let inpc = bundle.pc;
        let dInst = bundle.dInst;
        let ppc = bundle.predPc;

        let rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
        let rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
        let csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        let eInst  = exec(dInst, rVal1, rVal2, inpc, ppc, csrVal);

        if(eInst.iType == Br || eInst.iType == J || eInst.iType == Jr) begin
            btb.update(inpc, eInst.addr);
        end

        if(eInst.iType == Ld) begin
            eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end else if(eInst.iType == St) begin
            let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end

        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", inpc);
            $finish;
        end

        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

        if (eInst.mispredict) begin
            pc[1] <= eInst.addr;
            d2e.clear;
        end
        else begin
            d2e.deq;
        end
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc[0] <= startpc;
    endmethod

	interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
