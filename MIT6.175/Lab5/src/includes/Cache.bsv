
import CacheTypes::*;
import MemUtil::*;
import Fifo::*;
import Vector::*;
import Types::*;
import MemTypes::*;

module mkTranslator(WideMem mem, Cache ifc);

	function CacheWordSelect getOffset(Addr addr) = truncate(addr >> 2);
	Fifo#(2,MemReq) pendLdReq <- mkCFFifo;

	method Action req(MemReq r);
		if(r.op==Ld) begin
			pendLdReq.enq(r);
		end
		mem.req(toWideMemReq(r));
	endmethod

	method ActionValue#(MemResp) resp;
		let request = pendLdReq.first;
		pendLdReq.deq;

		let cacheLine <-mem.resp;
		let offset = getOffset(request.addr);
		return cacheLine[offset];
	endmethod
endmodule

typedef enum{
	Ready,
	StartMiss,
	SendFillReq,
	WaitFillResp
} ReqStatus deriving (Bits,Eq);

module mkCache(WideMem mem, Cache ifc);

	Vector#(CacheRows,Reg#(CacheLine))			dataArray	<- replicateM(mkRegU);
	Vector#(CacheRows,Reg#(Maybe#(CacheTag)))	tagArray	<- replicateM(mkReg(tagged Invalid));
	Vector#(CacheRows,Reg#(Bool))				dirtyArray	<- replicateM(mkReg(False));

	Fifo#(1,Data)	hitQ	<-mkBypassFifo;
	Reg#(MemReq)	missReq	<-mkRegU;
	Reg#(ReqStatus)	mshr	<-mkReg(Ready);

	function CacheIndex			getIndex(Addr addr)		= truncate(addr >> 6);
	function CacheWordSelect	getOffset(Addr addr)	= truncate(addr >> 2);
	function CacheTag			getTag(Addr addr)		= truncateLSB(addr);

	// write back if necessary
	rule startMiss(mshr == StartMiss);

		let idx		= getIndex(missReq.addr);
		let tag		= tagArray[idx];
		let dirty	= dirtyArray[idx];

		if(isValid(tag) && dirty) begin
			let addr = { fromMaybe(?, tag), idx, 6'b0};
			let data = dataArray[idx];
			mem.req(WideMemReq{
				write_en:'1,
				addr:addr,
				data:data
			});
		end

		mshr <= SendFillReq;

	endrule

	// issue Ld or St request
	rule sendFillReq(mshr == SendFillReq);

		WideMemReq request = toWideMemReq(missReq);
		Bit#(CacheLineWords) write_en = 0;
		request.write_en = write_en;
		mem.req(request);

		mshr <= WaitFillResp;

	endrule

	// get mem response
	rule waitFillResp(mshr == WaitFillResp);

		let idx			= getIndex(missReq.addr);
		let tag			= getTag(missReq.addr);
		let offset		= getOffset(missReq.addr);
		let data		<- mem.resp;

		tagArray[idx]	<= tagged Valid tag;

		if(missReq.op==Ld) begin

			dirtyArray[idx]	<=False;
			dataArray[idx]	<=data;
			hitQ.enq(data[offset]);

		end else begin

			data[offset]	= missReq.data;
			dirtyArray[idx]	<= True;
			dataArray[idx]	<= data;

		end

		mshr <= Ready;

	endrule

	method Action req(MemReq r) if(mshr == Ready);

		let idx			= getIndex(r.addr);
		let offset		= getOffset(r.addr);
		let localTag	= tagArray[idx];
		let tag 		= getTag(r.addr);
		let hit			= isValid(localTag)?fromMaybe(?,localTag)==tag:False;

		if(hit) begin

			let cacheLine = dataArray[idx];
			if(r.op==Ld) begin
				hitQ.enq(cacheLine[offset]);
			end else begin
				cacheLine[offset]	=  r.data;
				dataArray[idx]		<= cacheLine;
				dirtyArray[idx]		<= True;
			end

		end else begin

			missReq <= r;
			mshr<=StartMiss;

		end

	endmethod

	method ActionValue#(Data) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod

endmodule
