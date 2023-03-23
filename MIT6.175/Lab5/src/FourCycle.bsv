// FourCycle.bsv
//
// This is a four cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DelayedMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import FIFO::*;
import Ehr::*;
import GetPut::*;

typedef enum {
    Fetch,
    Decode,
    Execute,
    WriteBack
} Stage deriving(Bits, Eq, FShow);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr)       pc <- mkRegU;
    RFile            rf <- mkRFile;
    DelayedMemory  iMem <- mkDelayedMemory;
    DMemory        dMem <- mkDMemory;
    CsrFile        csrf <- mkCsrFile;

    Reg#(DecodedInst) decodeStage <- mkRegU;
    Reg#(ExecInst) executeStage <- mkRegU;
    Reg#(Stage) stage <- mkReg(Fetch);

    Bool memReady = iMem.init.done && dMem.init.done;
    rule test (!memReady);
        let e = tagged InitDone;
        iMem.init.request.put(e);
        dMem.init.request.put(e);
    endrule

    rule doFetch if (csrf.started && stage == Fetch);
        iMem.req(MemReq{ op: Ld, addr: pc, data: ? });
        stage <= Decode;
    endrule

    rule doDecode if (csrf.started && stage == Decode);
        let inst <- iMem.resp;
        decodeStage <= decode(inst);
        stage <= Execute;
    endrule

    rule doExecute if (csrf.started && stage == Execute);
        let dInst = decodeStage;

        let rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
        let rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
        let csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        let eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);

        if (eInst.iType == Ld) begin
            iMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end else if (eInst.iType == St) begin
            iMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end

        if (eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end

        pc <= eInst.brTaken ? eInst.addr : pc + 4;
        executeStage <= eInst;
        stage <= WriteBack;
    endrule

    rule doWriteback if (csrf.started && stage == WriteBack);
        let eInst = executeStage;

        if (eInst.iType == Ld) begin
            eInst.data <- iMem.resp;
        end

        if (isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        csrf.wr(eInst.iType == Csrw? eInst.csr : Invalid, eInst.data);
        stage <= Fetch;
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started && memReady);
        csrf.start(0);
        $display("Start at pc %h\n", startpc);
	    $fflush(stdout);
        pc <= startpc;
    endmethod

    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
