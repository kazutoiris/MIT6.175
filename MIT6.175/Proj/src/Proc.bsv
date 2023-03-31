import Vector::*;
import GetPut::*;
import ClientServer::*;
import ProcTypes::*;
import Types::*;
import MemTypes::*;
import CacheTypes::*;
import MemUtil::*;
import WideMemInit::*;
import Fifo::*;
import MessageFifo::*;
import MessageRouter::*;
import PPP::*;
import RefTypes::*;
import RefSCMem::*;
import RefTSOMem::*;
import RefDummyMem::*;


`ifdef THREECYCLE
import ThreeCycle::*;
`endif

`ifdef SIXSTAGE
import SixStage::*;
`endif


module mkProc#(Fifo#(2, DDR3_Req) ddr3ReqFifo, Fifo#(2, DDR3_Resp) ddr3RespFifo)(Proc);

	Reg#(Bool) started <- mkReg(False); // start reg

	/////////////////////////////////
	// reference model for coherent memory
	/////////////////////////////////

    //RefMem refMem <- mkRefTSOMem;
    //RefMem refMem <- mkRefTSOMem;
    //RefMem refMem <- mkRefSCMem;
	RefMem refMem <- mkRefDummyMem;

	/////////////////////////////////
	// main memory
	/////////////////////////////////

    WideMemInitIfc       ddr3InitIfc <- mkWideMemInitDDR3(ddr3ReqFifo);

    Bool memReady = True;
	
	// wrap DDR3 to widemem
    WideMem           wideMemWrapper <- mkWideMemFromDDR3(ddr3ReqFifo, ddr3RespFifo);
	
	// split widemem to D + I * n : only take action after reset
	// otherwise the guard may fail, and we get garbage resp
    Vector#(TAdd#(1, CoreNum), WideMem) wideMems <- mkSplitWideMemRR(memReady && started, wideMemWrapper);

	// Data mem use port 0 with priority
	WideMem dMem = wideMems[0];
	// Inst mem use port 1 ~ CoreNum, roundrobin
	Vector#(CoreNum, WideMem) iMems = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		iMems[i] = wideMems[i+1];
	end
	
	// some garbage may get into ddr3RespFifo during soft reset
    rule drainMemResponses(!started);
        ddr3RespFifo.deq;
    endrule

	/////////////////////////////////
	// cores
	/////////////////////////////////
	Vector#(CoreNum, Core) cores = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		cores[i] <- mkCore(fromInteger(i), iMems[i], refMem.dMem[i]);
	end

	// multiplex cpu to host
	Fifo#(2, CpuToHost) toHostQ <- mkCFFifo; 
	
	rule multiplexToHost(started);
		Maybe#(CoreID) sel = Invalid;
		for(Integer i = valueOf(CoreNum)-1; i >= 0; i = i-1) begin
			if(cores[i].cpuToHostValid) begin
				sel = Valid (fromInteger(i));
			end
		end
		if(sel matches tagged Valid .id) begin
			let d <- cores[id].cpuToHost;
			toHostQ.enq(CpuToHost {
				id: id,
				data: d
			});
		end
	endrule

	/////////////////////////////////
	// message router
	/////////////////////////////////
	// interface with core
	Vector#(CoreNum, MessageGet) c2r = ?;
	Vector#(CoreNum, MessagePut) r2c = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		c2r[i] = cores[i].toParent;
		r2c[i] = cores[i].fromParent;
	end
	// interface with PPP
	MessageFifo#(2) p2rQ <- mkMessageFifo;
	MessageFifo#(2) r2pQ <- mkMessageFifo;
	// instance
	mkMessageRouter(c2r, r2c, toMessageGet(p2rQ), toMessagePut(r2pQ));

	/////////////////////////////////
	// parent protocol processor
	/////////////////////////////////
	mkPPP(toMessageGet(r2pQ), toMessagePut(p2rQ), dMem);

	/////////////////////////////////
	// interface & methods
	/////////////////////////////////
	interface cpuToHost = toGet(toHostQ);

	interface Put hostToCpu;
		method Action put(Addr startpc) if(!started && memReady && !ddr3RespFifo.notEmpty);
			started <= True;
			for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
				cores[i].hostToCpu(startpc);
			end
		endmethod
	endinterface

endmodule
