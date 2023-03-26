import MemTypes::*;
import Types::*;
import Vector::*;

typedef 16 CacheLineWords; // to match DDR3 width
typedef TMul#(CacheLineWords, 4) CacheLineBytes;
typedef 16 CacheRows;

typedef Bit#( TSub#(TSub#(TSub#(AddrSz, 2), TLog#(CacheRows)), TLog#(CacheLineWords)) ) CacheTag;
typedef Bit#( TLog#(CacheRows) ) CacheIndex;
typedef Bit#( TLog#(CacheLineWords) ) CacheWordSelect;
typedef Vector#(CacheLineWords, Data) CacheLine;

// useful functions for cache
function CacheWordSelect getWordSelect(Addr a);
	return truncate(a >> 2);
endfunction

function CacheIndex getIndex(Addr a);
	return truncate(a >> (2 + valueOf(TLog#(CacheLineWords))));
endfunction

function CacheTag getTag(Addr a);
	return truncateLSB(a);
endfunction


// Wide memory interface
// This is defined here since it depends on the CacheLine type
typedef struct{
    Bit#(CacheLineWords) write_en;  // Word write enable
    Addr                 addr;
    CacheLine            data;      // Vector#(CacheLineWords, Data)
} WideMemReq deriving(Eq,Bits);

typedef CacheLine WideMemResp;
interface WideMem;
    method Action req(WideMemReq r);
    method ActionValue#(CacheLine) resp;
	method Bool respValid;
endinterface


// Interface for caches
interface ICache;
	method Action req(Addr a);
	method ActionValue#(MemResp) resp;
endinterface
interface DCache;
    method Action req(MemReq r);
    method ActionValue#(MemResp) resp;
endinterface

// Interface just like FPGAMemory (except no MemInit)
interface Cache;
    method Action req(MemReq r);
    method ActionValue#(MemResp) resp;
endinterface


// store queue size
typedef 16 StQSize;
