// FourCycle.bsv
//
// This is a four cycle implementation of the RISC-V processor.

import Types::*;
import ProcTypes::*;
import CMemTypes::*;
import MemInit::*;
import RFile::*;
import DelayedMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
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
    Reg#(Addr)    pc <- mkRegU;
    RFile         rf <- mkRFile;
    DelayedMemory mem <- mkDelayedMemory;
	let dummyInit     <- mkDummyMemInit;
    CsrFile       csrf <- mkCsrFile;

    Bool memReady = mem.init.done && dummyInit.done;
    rule test (!memReady);
       let e = tagged InitDone;
       mem.init.request.put(e);
       dummyInit.request.put(e);
    endrule

    //state tracker and intermediate value regs
    Reg#(Stage) state <- mkReg(Fetch); 
    Reg#(DecodedInst) dInst <- mkRegU;
    Reg#(ExecInst) eInst <- mkRegU;

    rule doFetch(csrf.started && state == Fetch);

        // request load of pc from mem (no response)
        mem.req(MemReq{op: Ld, addr: pc, data: ?});

        //change state to decode
        state <= Decode;
 
    endrule

    rule doDecode(csrf.started && state == Decode);

        //fetch requested pc from mem
        Data inst <- mem.resp(); 

        // decode
        dInst <= decode(inst);

        //switch state to Execute
        state <= Execute;
    endrule

    rule doExecute(csrf.started && state == Execute);

        // read general purpose register values 
        Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
        Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));

        // read CSR values (for CSRR inst)
        Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));


        // execute
        ExecInst e_Inst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);
        eInst <= e_Inst;  
        
        // memory 
        if(e_Inst.iType == Ld) begin 
            mem.req(MemReq{op: Ld, addr: e_Inst.addr, data: ?});
        end else if(e_Inst.iType == St) begin 
            mem.req(MemReq{op: St, addr: e_Inst.addr, data: e_Inst.data});
        end


        // check unsupported instruction at commit time. Exiting
        if(e_Inst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end

        //switch state to write back
        state <= WriteBack;

    endrule

    rule doWriteBack(csrf.started && state == WriteBack);

        //if the instruction is a load, get requested data from mem
        Data e_data = eInst.data;
        if (eInst.iType == Ld) begin
            e_data <- mem.resp();
        end

        // write back to reg file
        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), e_data);
        end

        // update the pc depending on whether the branch is taken or not
        pc <= eInst.brTaken ? eInst.addr : pc + 4;

        // CSR write for sending data to host & stats
        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, e_data);

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

