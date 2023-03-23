// TwoCycle.bsv
//
// This is a two cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

typedef enum{
    Fetch,
    Execute
} State deriving(Bits,Eq,FShow);

(*synthesize*)
module mkProc(Proc);
    Reg#(Addr) pc <- mkRegU;
    RFile      rf <- mkRFile;
    IMemory  iMem <- mkIMemory;
    DMemory  dMem <- mkDMemory;
    CsrFile  csrf <- mkCsrFile;

    Reg#(State) stage <- mkRegU;
    Reg#(DecodedInst) fetchStage <- mkRegU;

    Bool memReady = iMem.init.done() && dMem.init.done();
    rule test (!memReady);
        let e = tagged InitDone;
        iMem.init.request.put(e);
        dMem.init.request.put(e);
    endrule

    rule doFetch if (csrf.started && stage == Fetch);
        let inst = iMem.req(pc);
        fetchStage <= decode(inst);
        stage <= Execute;
    endrule

    rule doExecute if (csrf.started && stage == Execute);
        let dInst = fetchStage;
        let rVal1 = rf.rd1(fromMaybe(?,dInst.src1));
        let rVal2 = rf.rd2(fromMaybe(?,dInst.src2));
        let csrVal = csrf.rd(fromMaybe(?,dInst.csr));
        let eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);

        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end

        if(eInst.iType == Ld) begin
            eInst.data <- dMem.req(MemReq{ op:Ld, addr:eInst.addr, data:? });
        end else if(eInst.iType == St) begin
            let d <- dMem.req(MemReq{ op:St, addr:eInst.addr, data:eInst.data });
        end

        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
        pc <= eInst.brTaken ? eInst.addr : pc + 4;
        stage <= Fetch;
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if(!csrf.started && memReady);
        csrf.start(0);
        pc <= startpc;
    endmethod

    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
