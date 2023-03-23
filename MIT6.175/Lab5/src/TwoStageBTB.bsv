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
