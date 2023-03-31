import MemTypes::*;
import Types::*;
import Vector::*;

typedef 16 CacheLineWords; // to match DDR3 width
typedef TMul#(CacheLineWords, 4) CacheLineBytes;
typedef 16 CacheRows;

typedef Bit#( TSub#(TSub#(AddrSz, 2), TLog#(CacheLineWords)) ) CacheLineAddr;
typedef Bit#( TSub#(TSub#(TSub#(AddrSz, 2), TLog#(CacheRows)), TLog#(CacheLineWords)) ) CacheTag;
typedef Bit#( TLog#(CacheRows) ) CacheIndex;
typedef Bit#( TLog#(CacheLineWords) ) CacheWordSelect;
typedef Vector#(CacheLineWords, Data) CacheLine;

// some useful functions about cache
function CacheWordSelect getWordSelect(Addr a);
	return truncate(a >> 2);
endfunction

function CacheIndex getIndex(Addr a);
	return truncate(a >> (2 + valueOf(TLog#(CacheLineWords))));
endfunction

function CacheTag getTag(Addr a);
	return truncateLSB(a);
endfunction

function CacheLineAddr getLineAddr(Addr a);
	return truncateLSB(a);
endfunction

// Wide memory interface
// This is defined here since it depends on the CacheLine type
typedef struct{
    Bit#(CacheLineWords) write_en;  // Word write enable
    Addr                 addr;
    CacheLine            data;      // Vector#(CacheLineWords, Data)
} WideMemReq deriving(Eq,Bits,FShow);

typedef CacheLine WideMemResp;
interface WideMem;
    method Action req(WideMemReq r);
    method ActionValue#(CacheLine) resp;
	method Bool respValid;
endinterface

// Interface for Cache
interface ICache;
	method Action req(Addr a);
	method ActionValue#(MemResp) resp;
endinterface
interface DCache;
    method Action req(MemReq r);
    method ActionValue#(MemResp) resp;
endinterface

// store queue size
typedef 16 StQSize;

// MSI state
typedef enum { M, S, I } MSI deriving( Bits, Eq, FShow );
instance Ord#(MSI);
    function Bool \< ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT);
    endfunction
    function Bool \<= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT) || (c == EQ);
    endfunction
    function Bool \> ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT);
    endfunction
    function Bool \>= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT) || (c == EQ);
    endfunction

    // This should implement M > S > I
    function Ordering compare( MSI x, MSI y );
        if( x == y ) begin
            // MM SS II
            return EQ;
        end else if( x == M || y == I) begin
            // MS MI SI
            return GT;
        end else begin
            // SM IM IS
            return LT;
        end
    endfunction

    function MSI min( MSI x, MSI y );
        if( x < y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
    function MSI max( MSI x, MSI y );
        if( x > y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
endinstance

// cache <-> mem message
typedef struct{
    CoreID            child;
    Addr              addr;
    MSI               state;
    Maybe#(CacheLine) data;
} CacheMemResp deriving(Eq, Bits, FShow);
typedef struct{
    CoreID      child;
    Addr        addr;
    MSI         state;
} CacheMemReq deriving(Eq, Bits, FShow);
typedef union tagged {
    CacheMemReq     Req;
    CacheMemResp    Resp;
} CacheMemMessage deriving(Eq, Bits, FShow);

// Interfaces for message FIFO connecting cache and mem
interface MessageFifo#( numeric type n );
    method Action enq_resp( CacheMemResp d );
    method Action enq_req( CacheMemReq d );
    method Bool hasResp;
    method Bool hasReq;
    method Bool notEmpty;
    method CacheMemMessage first;
    method Action deq;
endinterface

// some restricted views of message FIFO interfaces
interface MessagePut;
	method Action enq_resp(CacheMemResp d);
    method Action enq_req( CacheMemReq d );
endinterface

function MessagePut toMessagePut(MessageFifo#(n) ifc);
	return (interface MessagePut;
		method enq_resp = ifc.enq_resp;
		method enq_req = ifc.enq_req;
	endinterface);
endfunction

interface MessageGet;
    method Bool hasResp;
    method Bool hasReq;
    method Bool notEmpty;
    method CacheMemMessage first;
    method Action deq;
endinterface

function MessageGet toMessageGet(MessageFifo#(n) ifc);
	return (interface MessageGet;
		method hasResp = ifc.hasResp;
		method hasReq = ifc.hasReq;
		method notEmpty = ifc.notEmpty;
		method first = ifc.first;
		method deq = ifc.deq;
	endinterface);
endfunction
