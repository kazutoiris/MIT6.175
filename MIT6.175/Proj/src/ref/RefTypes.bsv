import ProcTypes::*;
import Types::*;
import CacheTypes::*;
import MemTypes::*;
import GetPut::*;
import Vector::*;

// imported C function to handle monolithic memory
import "BDPI" function ActionValue#(Bit#(64)) c_createMem(Bit#(32) addrWidth);
import "BDPI" function ActionValue#(Data) c_readMem(Bit#(64) memPtr, Bit#(32) wordAddr);
import "BDPI" function Action c_writeMem(Bit#(64) memPtr, Bit#(32) wordAddr, Data d);

// reference memory
interface RefIMem;
	method Action fetch(Addr pc, Instruction inst);
endinterface

interface RefDMem;
	method Action issue(MemReq req);
	method Action commit(MemReq req, Maybe#(CacheLine) line, Maybe#(MemResp) resp);
	// line is the original cache line (before write is done)
	// set it to invalid if you don't want to check the value 
	// or you don't know the value (e.g. when you bypass from stq or when store-cond fail)
endinterface

interface RefMem;
	interface Vector#(CoreNum, RefIMem) iMem;
	interface Vector#(CoreNum, RefDMem) dMem;
endinterface

// in debugging, only simulate 4MB memory
typedef 22 RefAddrSz;

function Bool refAddrOverflow(Addr a);
	Bit#(TSub#(AddrSz, RefAddrSz)) hi = truncateLSB(a);
	return hi != 0;
endfunction

function Action checkRefAddrOverflow(CoreID cid, Addr a);
	return (action
		if(refAddrOverflow(a)) begin
			$fwrite(stderr, "%0t: ERROR: Referce model: core %d access addr = %h overflow, try to increase RefAddrSz in RefTypes.bsv\n", $time, cid, a);
			$finish;
		end
	endaction);
endfunction

// wrap up imported C functions
function ActionValue#(Bit#(64)) createMem = c_createMem(fromInteger(valueOf(RefAddrSz)));

function ActionValue#(Data) readMemWord(Bit#(64) memPtr, Addr a) = c_readMem(memPtr, a >> 2);

function Action writeMemWord(Bit#(64) memPtr, Addr a, Data d) = c_writeMem(memPtr, a >> 2, d);

function ActionValue#(CacheLine) readMemLine(Bit#(64) memPtr, CacheLineAddr la);
	return (actionvalue
		CacheLine line = ?;
		for(Integer i = 0; i < valueOf(CacheLineWords); i = i+1) begin
			CacheWordSelect sel = fromInteger(i);
			line[i] <- readMemWord(memPtr, {la, sel, 2'b0});
		end
		return line;
	endactionvalue);
endfunction

// helper function to compare two mem req
function Bool memReqEq(MemReq a, MemReq b);
	Bool eq = a.rid == b.rid && a.op == b.op;
	Bool addrEq = a.addr == b.addr;
	Bool dataEq = a.data == b.data;
	
	eq = eq && (case(a.op)
		Ld, Lr: addrEq;
		St, Sc: (addrEq && dataEq);
		Fence: True;
		default: False;
	endcase);

	return eq;
endfunction

// useful types
typedef struct {
	Addr pc;
	Instruction inst;
} RefFetchReq deriving(Bits, Eq, FShow);

typedef struct {
	MemReq req;
	Maybe#(CacheLine) line;
	Maybe#(MemResp) resp;
} RefCommitReq deriving(Bits, Eq, FShow);

typedef 8 MaxReqNum;

