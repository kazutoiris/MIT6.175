import Fifo::*;
import Vector::*;
import MemTypes::*;
import CacheTypes::*;
import MemUtil::*;
import Types::*;

module mkBypassCache(WideMem mem, Cache ifc);
    Fifo#(8, MemReq) buffer <- mkPipelineFifo();

    method Action req(MemReq r);
        if(r.op == Ld) begin
            buffer.enq(r);
        end
        mem.req(toWideMemReq(r));
    endmethod

    method ActionValue#(MemResp) resp;
        let request = buffer.first;
        buffer.deq;
		let data <- mem.resp();
        return data[getWordSelect(request.addr)]; // load 1 word (16 bits)
    endmethod
endmodule

typedef enum {
    Idle,
	WriteBack,
	ReadResp,
    WaitReadResp
} CacheStatus deriving (Bits,Eq);

module mkCache(WideMem mem, Cache ifc);
    Vector#(CacheRows,Reg#(CacheLine))        dataMem  <- replicateM(mkRegU);
    Vector#(CacheRows,Reg#(Maybe#(CacheTag))) tagMem   <- replicateM(mkReg(tagged Invalid));
    Vector#(CacheRows,Reg#(Bool))             dirtyMem <- replicateM(mkReg(False));

    Fifo#(8, Data)       respFifo <- mkBypassFifo;
    Reg#(MemReq)         buffer   <- mkRegU;
    Reg#(CacheStatus)    status   <- mkReg(Idle);

    rule writeBack if (status == WriteBack);
        let idx    = getIndex(buffer.addr);
        let tag    = tagMem[idx];
        let dirty  = dirtyMem[idx];

        if(isValid(tag) && dirty) begin
            let addr = { fromMaybe(?, tag), idx, 6'b0};
            let data = dataMem[idx];
            mem.req(WideMemReq {
                write_en: '1,
                addr: addr,
                data: data
            });
		end
		status <= ReadResp;
		$display("switch to read resp");
    endrule

	rule readResp if (status == ReadResp);
		let idx  =  getIndex(buffer.addr);
        let tag  =  getTag(buffer.addr);
		let addr =  { tag, idx, 6'b0 };
		let d = toWideMemReq(buffer);
		d.write_en = '0;
        mem.req(d);
        status <= WaitReadResp;
		$display("switch to wait read resp");
    endrule

    rule waitReadResp if (status == WaitReadResp);
        let idx       =  getIndex(buffer.addr);
        let tag       =  getTag(buffer.addr);
        let offset    =  getWordSelect(buffer.addr);
		let respData  <- mem.resp();
        tagMem[idx] <= tagged Valid tag;

        if(buffer.op == Ld) begin
            dirtyMem[idx] <= False;
            dataMem[idx]  <= respData;
            respFifo.enq(respData[offset]);
        end else begin
            dirtyMem[idx]  <= True;
            respData[offset] =  buffer.data;
            dataMem[idx]   <= respData;
        end

        status <= Idle;
		$display("switch to idle");
    endrule

    method Action req(MemReq r) if (status == Idle);
        let idx      = getIndex(r.addr);
        let offset   = getWordSelect(r.addr);
        let localTag = tagMem[idx];
        let tag      = getTag(r.addr);
        let hit      = isValid(localTag) && fromMaybe(?, localTag) == tag;

        if (hit) begin
            let cacheLine = dataMem[idx];
            if(r.op == Ld) begin
                respFifo.enq(cacheLine[offset]);
            end else begin
                cacheLine[offset] =  r.data;
                dataMem[idx]      <= cacheLine;
                dirtyMem[idx]     <= True;
            end
        end else begin
            buffer <= r;
			status <= WriteBack;
			$display("switch to write back");
        end

    endmethod

    method ActionValue#(Data) resp;
		let d = respFifo.first;
        respFifo.deq;
        return d;
    endmethod

endmodule
