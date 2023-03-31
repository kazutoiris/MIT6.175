import Types::*;
import MemTypes::*;
import CacheTypes::*;
import RefTypes::*;
import MemUtil::*;
import SimMem::*;
import MemReqIDGen::*;
import DCache::*;
import MessageFifo::*;
import MessageRouter::*;
import PPP::*;
import RefSCMem::*;
import Fifo::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;
import Printf::*;
import FShow::*;
import Randomizable::*;
import Ehr::*;

typedef 1000 TestReqNum;

typedef 2 IndexNum;
typedef 2 TagNum;
typedef 2 WordSelNum;

typedef Bit#(TLog#(IndexNum)) IndexSel;
typedef Bit#(TLog#(TagNum)) TagSel;

interface TestDone;
	method Action done;
endinterface

module mkTestDriver(
		CoreID id, 
		DCache cache, 
		TestDone testDone, 
		Empty ifc
	);
	Randomize#(CacheIndex)    indexRand <- mkConstrainedRandomizer(0, fromInteger(valueOf(IndexNum) - 1));
	Randomize#(CacheTag)        tagRand <- mkConstrainedRandomizer(0, fromInteger(valueOf(TagNum) - 1));
	Randomize#(CacheWordSelect) selRand <- mkConstrainedRandomizer(0, fromInteger(valueOf(WordSelNum) - 1));
	Randomize#(Data)           dataRand <- mkGenericRandomizer;
	Randomize#(Bit#(1))          opRand <- mkGenericRandomizer;

	MemReqIDGen idGen <- mkMemReqIDGen;

	Reg#(Bool) initDone <- mkReg(False);
	// log file
	Reg#(File) file <- mkReg(InvalidFile);

	Fifo#(2, MemReq) reqQ <- mkCFFifo;

	// monitor processing time to detect deadlock
	Ehr#(2, Data) procTime <- mkEhr(0); 
	Data maxProcTime = 1000;

	// req counter
	Reg#(Data) reqNum <- mkReg(0);

	rule doInit(!initDone);
		indexRand.cntrl.init;
		tagRand.cntrl.init;
		selRand.cntrl.init;
		dataRand.cntrl.init;
		opRand.cntrl.init;

		// open log file
		String name = sprintf("driver_%d_trace.out", id);
		let f <- $fopen(name, "w");
		if(f == InvalidFile) begin
			$fwrite(stderr, "ERROR: fail to open %s\n", name);
			$finish;
		end
		file <= f;

		initDone <= True;
	endrule

	rule doReq(initDone);
		let index <- indexRand.next;
		let tag <- tagRand.next;
		let sel <- selRand.next;
		let data <- dataRand.next;
		let op <- opRand.next;
		let rid <- idGen.getID;

		MemReq req = MemReq {
			op: op == 0 ? Ld : St,
			addr: {tag, index, sel, 2'b0},
			data: data,
			rid: rid
		};

		reqQ.enq(req);
		cache.req(req);

		$fwrite(file, "%0t: send req ", $time, fshow(req), "\n\n");
	endrule

	rule doResp(initDone);
		// we do not check resp value, let RefMem to check
		reqQ.deq;
		let req = reqQ.first;
		if(req.op == Ld) begin
			let d <- cache.resp;
		end
		// reset proc time
		procTime[1] <= 0;
		// incr processed req num
		reqNum <= reqNum + 1;
		if(reqNum >= fromInteger(valueOf(TestReqNum) - 1)) begin
			testDone.done;
		end

		$fwrite(file, "%0t: finish req ", $time, fshow(req), "\n\n");
	endrule

	(* fire_when_enabled *)
	(* no_implicit_conditions *)
	rule waitResp(initDone);
		if(reqQ.notEmpty) begin
			procTime[0] <= procTime[0] + 1;
			if(procTime[0] >= maxProcTime) begin
				$fwrite(stderr, "%0t: ERROR: TestDriver %d: waiting resp from cache for %d cycles, probably deadlock\n", $time, id, procTime[0]);
				$finish;
			end
		end
	endrule
endmodule

(* synthesize *)
module mkTb(Empty);
	// reference memory
	RefMem refMem <- mkRefSCMem;

	// main memory
    Fifo#(2, DDR3_Req)  ddr3ReqFifo  <- mkCFFifo;
    Fifo#(2, DDR3_Resp) ddr3RespFifo <- mkCFFifo;
	mkSimMem(toGPClient(ddr3ReqFifo, ddr3RespFifo));
    WideMem wideMem <- mkWideMemFromDDR3(ddr3ReqFifo, ddr3RespFifo);
	
	// caches
	Vector#(CoreNum, MessageFifo#(2)) c2rQ <- replicateM(mkMessageFifo); // cache -> router
	Vector#(CoreNum, MessageFifo#(2)) r2cQ <- replicateM(mkMessageFifo); // router -> cache
	Vector#(CoreNum, DCache) cache = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		cache[i] <- mkDCache(
			fromInteger(i),
			toMessageGet(r2cQ[i]),
			toMessagePut(c2rQ[i]),
			refMem.dMem[i]
		);
	end

	// message router
	MessageFifo#(2) p2rQ <- mkMessageFifo;
	MessageFifo#(2) r2pQ <- mkMessageFifo;
	mkMessageRouter(
		map(toMessageGet, c2rQ), 
		map(toMessagePut, r2cQ), 
		toMessageGet(p2rQ), 
		toMessagePut(r2pQ)
	);

	// parent protocol processor
	mkPPP(toMessageGet(r2pQ), toMessagePut(p2rQ), wideMem);

	// test driver
	Vector#(CoreNum, Reg#(Bool)) doneVec <- replicateM(mkReg(False));
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		TestDone td = (interface TestDone;
			method Action done;
				doneVec[i] <= True;
				if(!doneVec[i]) begin
					$fwrite(stderr, "TestDriver %d done\n", i);
				end
			endmethod
		endinterface);
		mkTestDriver(fromInteger(i), cache[i], td);
	end

	rule passTest;
		Bool pass = True;
		for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
			pass = pass && doneVec[i];
		end
		if(pass) begin
			$fwrite(stderr, "PASSED\n");
			$finish;
		end
	endrule
endmodule
