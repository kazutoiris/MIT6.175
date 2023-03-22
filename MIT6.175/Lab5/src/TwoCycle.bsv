// TwoCycle.bsv
//
// This is a two cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

typedef enum {
	Fetch,
	Execute
} Stage deriving(Bits, Eq, FShow);

(* synthesize *)
module mkProc(Proc);
    Reg#(Addr) pc <- mkRegU;
    RFile      rf <- mkRFile;
    DMemory   mem <- mkDMemory;
	let dummyInit <- mkDummyMemInit;
    CsrFile  csrf <- mkCsrFile;

    Bool memReady = mem.init.done && dummyInit.done;
    rule test (!memReady);
      let e = tagged InitDone;
      mem.init.request.put(e);
      dummyInit.request.put(e);
    endrule

    //stage tracker and instruction holder
    Reg#(Stage) state <- mkReg(Fetch); 
    Reg#(Data) f2d <- mkRegU; 

    rule doFetch(csrf.started && state == Fetch);

        //load instruction from mem
        Data inst <- mem.req(MemReq{op: Ld, addr: pc, data: ?});

        //store the instruction in f2d
        f2d <= inst;

        //change state to execute
        state <= Execute;

        // trace - print the instruction
        $display("pc: %h inst: (%h) expanded: ", pc, inst, showInst(inst));
        $fflush(stdout);

 
    endrule

    rule doExecute(csrf.started && state == Execute);

        //fetch the stored inst in f2d
        Data inst = f2d; 

        // decode
        DecodedInst dInst = decode(inst);

        // read general purpose register values 
        Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
        Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));

        // read CSR values (for CSRR inst)
        Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        // execute
        ExecInst eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);  
        // The fifth argument above is the predicted pc, to detect if it was mispredicted. 
        // Since there is no branch prediction, this field is sent with a random value

        // memory 
        if(eInst.iType == Ld) begin 
            eInst.data <- mem.req(MemReq{op: Ld, addr: eInst.addr, data: ?});
        end else if(eInst.iType == St) begin 
            let d <- mem.req(MemReq{op: St, addr: eInst.addr, data: eInst.data});
        end


        // check unsupported instruction at commit time. Exiting
        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end
     

        // write back to reg file
        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        // update the pc depending on whether the branch is taken or not
        pc <= eInst.brTaken ? eInst.addr : pc + 4;

        // CSR write for sending data to host & stats
        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);

        //switch state back to fetch
        state <= Fetch;
    endrule

    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started && memReady );
        csrf.start(0); // only 1 core, id = 0
        pc <= startpc;
    endmethod

	interface iMemInit = dummyInit;
    interface dMemInit = mem.init;
endmodule

