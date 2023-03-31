import CacheTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Vector::*;
import MemTypes::*;
import MemUtil::*;
import SimMem::*;


typedef enum{Ready, StartMiss, SendFillReq, WaitFillResp} CacheStatus 
    deriving(Eq, Bits);
module mkICache(WideMem mem, ICache ifc);

    // Track the cache state
    Reg#(CacheStatus) status <- mkReg(Ready);

    // The cache memory
    Vector#(CacheRows, Reg#(CacheLine)) dataArray <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(Maybe#(CacheTag))) 
            tagArray <- replicateM(mkReg(Invalid));
    Vector#(CacheRows, Reg#(Bool)) dirtyArray <- replicateM(mkReg(False));

    // Book keeping
    Fifo#(2, Data) hitQ <- mkBypassFifo;
    Reg#(Addr) missAddr <- mkRegU;
    Fifo#(2, MemReq) memReqQ <- mkCFFifo;
    Fifo#(2, CacheLine) memRespQ <- mkCFFifo;


    function CacheWordSelect getWord(Addr addr) = truncate(addr >> 2);
    function CacheIndex getIndex(Addr addr) = truncate(addr >> 6);
    function CacheTag getTag(Addr addr) = truncateLSB(addr);

    rule sendFillReq (status == StartMiss);

        memReqQ.enq(MemReq {op: Ld, addr: missAddr, data:?});
        status <= WaitFillResp;

    endrule


    rule waitFillResp (status == WaitFillResp);
        
        // calculate cache index and tag
        CacheWordSelect sel = getWord(missAddr);
        CacheIndex idx = getIndex(missAddr);
        let tag = getTag(missAddr);
        
        // set cache line with data
        let line = memRespQ.first;
        tagArray[idx] <= Valid(tag);
        
        // enqueue result into hit queue
        hitQ.enq(line[sel]);
        dataArray[idx] <= line;
        
        // dequeue response queue
        memRespQ.deq;

        // reset status
        status <= Ready;
    endrule


    rule sendToMemory;

        // dequeue to get DRAM request
        memReqQ.deq;
        let r = memReqQ.first;

        // translate data to cache line
        CacheIndex idx = getIndex(r.addr);
        CacheLine line = dataArray[idx];
        
        // create enable signal
        Bit#(CacheLineWords) en;
        if (r.op == St) en = '1;
        else en = '0; 

        mem.req(WideMemReq{
            write_en: en,
            addr: r.addr,
            data: line
        } );

    endrule


    rule getFromMemory;

        // get DRAM response
        let line <- mem.resp();
        memRespQ.enq(line);
    
    endrule


    method Action req(Addr a) if (status == Ready);
    
        // calculate cache index and tag
        CacheWordSelect sel = getWord(a);
        CacheIndex idx = getIndex(a);
        CacheTag tag = getTag(a);

        // check if in cache
        let hit = False;
        if (tagArray[idx] matches tagged Valid .currTag 
            &&& currTag == tag) hit = True;

        // check load
        if (hit) begin
            hitQ.enq(dataArray[idx][sel]);
        end
        else begin
            missAddr <= a;
            status <= StartMiss;
        end
    endmethod


    method ActionValue#(Data) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod


endmodule


