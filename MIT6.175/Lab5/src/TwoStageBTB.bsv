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
    RFile      rf <- mkRFile;
	IMemory  iMem <- mkIMemory;
    DMemory  dMem <- mkDMemory;
    CsrFile  csrf <- mkCsrFile;
    Btb#(6)   btb <- mkBtb; // 64-entry BTB

    Bool memReady = iMem.init.done() && dMem.init.done();
    rule test (!memReady);
    let e = tagged InitDone;
    iMem.init.request.put(e);
    dMem.init.request.put(e);
    endrule

    Fifo#(2, Dec2Ex) d2e <- mkCFFifo;


    //doFetchDecode < doExecute
    rule doFetchDecode(csrf.started);

        //fetch instruction from imem then make next pc prediction
        let inst = iMem.req(pc[0]);
        Addr ppc = btb.predPc(pc[0]); pc[0] <= ppc;

        //decode instruction
        let dInst = decode(inst);

        d2e.enq(Dec2Ex{pc: pc[0], predPc:ppc, dInst: dInst});

        $display("pc: %h inst: (%h) expanded: ", pc[0], inst, showInst(inst));

    endrule

    rule doExecute(csrf.started);

        //extract pc, ppc and dInst from d2e
        let bundle = d2e.first; let inpc = bundle.pc;
        let dInst = bundle.dInst; let ppc = bundle.predPc;


        // read general purpose register values 
        Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
        Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));

        // read CSR values (for CSRR inst)
        Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        // execute (branch prediction with ppc)
        ExecInst eInst = exec(dInst, rVal1, rVal2, inpc, ppc, csrVal);  

        // memory 
        if(eInst.iType == Ld) begin 
            eInst.data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end else if(eInst.iType == St) begin 
            let d <- dMem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end


        // check unsupported instruction at commit time. Exiting
        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", inpc);
            $finish;
        end

/*
        if(eInst.iType == Br || eInst.iType == J || eInst.iType == Jr) begin
            $display("Branch instruction here");
        end*/

     
        // write back to reg file
        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        // CSR write for sending data to host & stats
        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

        //If branch mispredicted, update btb and pc to correct value and clear d2e
        if (eInst.mispredict) begin
           // $display("missed_ppc: %h inst: (%h) branch mispredicted: ", ppc, eInst, fshow(eInst));
            btb.update(inpc, eInst.addr);
            pc[1] <= eInst.addr; 
            d2e.clear; end
        //else deq bundle from d2e
        else begin d2e.deq; end
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

