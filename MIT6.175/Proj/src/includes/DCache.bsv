import CacheTypes::*;
import Vector::*;
import FShow::*;
import MemTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Ehr::*;
import RefTypes::*;

typedef enum { Rdy, StrtMiss, SndFillReq, WaitFillResp, Resp } CacheStatus
deriving(Eq, Bits);

function Bool isStateM(MSI s);
    return s == M;
endfunction

function Bool isStateS(MSI s);
    return s == S;
endfunction

function Bool isStateI(MSI s);
    return s == I;
endfunction

module mkDCache#(CoreID id)(
    MessageGet fromMem,
    MessagePut toMem,
    RefDMem refDMem,
    DCache ifc
);
    Vector#(CacheRows, Reg#(CacheLine)) dataVec <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(CacheTag))   tagVec <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(MSI))       privVec <- replicateM(mkReg(I));

    Reg#(CacheStatus) mshr <- mkReg(Rdy);

    Fifo#(8, Data)                  hitQ <- mkBypassFifo;
    Fifo#(8, MemReq)                reqQ <- mkBypassFifo;
    Reg#(MemReq)                  buffer <- mkRegU;
    Reg#(Maybe#(CacheLineAddr)) lineAddr <- mkReg(Invalid);

    rule doRdy (mshr == Rdy);
        MemReq r = reqQ.first;
        reqQ.deq;
        let     sel = getWordSelect(r.addr);
        let     idx = getIndex(r.addr);
        let     tag = getTag(r.addr);
        let     hit = tagVec[idx] == tag && privVec[idx] > I;
        let proceed = (r.op != Sc || (r.op == Sc && isValid(lineAddr) &&
                       fromMaybe(?, lineAddr) == getLineAddr(r.addr)));

        if (!proceed) begin
            hitQ.enq(scFail);
            refDMem.commit(r, Invalid, Valid(scFail));
            lineAddr <= Invalid;
        end
        else begin
            if (!hit) begin
                buffer <= r;
                mshr <= StrtMiss;
            end
            else begin
                if (r.op == Ld || r.op == Lr) begin
                    hitQ.enq(dataVec[idx][sel]);
                    refDMem.commit(r, Valid(dataVec[idx]), Valid(dataVec[idx][sel]));
                    if (r.op == Lr) begin
                        lineAddr <= tagged Valid getLineAddr(r.addr);
                    end
                end
                else begin
                    if (isStateM(privVec[idx])) begin
                        dataVec[idx][sel] <= r.data;
                        if (r.op == Sc) begin
                            hitQ.enq(scSucc);
                            refDMem.commit(r, Valid(dataVec[idx]), Valid(scSucc));
                            lineAddr <= Invalid;
                        end
                        else begin
                            refDMem.commit(r, Valid(dataVec[idx]), Invalid);
                        end
                    end
                    else begin
                        buffer <= r;
                        mshr <= SndFillReq;
                    end
                end
            end
        end
    endrule

    rule doStrtMiss (mshr == StrtMiss);
        let idx = getIndex(buffer.addr);
        let tag = tagVec[idx];
        let sel = getWordSelect(buffer.addr);

        if (!isStateI(privVec[idx])) begin
            privVec[idx] <= I;
            Maybe#(CacheLine) line = isStateM(privVec[idx]) ? Valid(dataVec[idx]) : Invalid;
            let addr = { tag, idx, sel, 2'b0 };
            toMem.enq_resp(CacheMemResp {
                child: id,
                addr: addr,
                state: I,
                data: line
            });
        end
        if (isValid(lineAddr) && fromMaybe(?, lineAddr) == getLineAddr(buffer.addr)) begin
            lineAddr <= Invalid;
        end
        mshr <= SndFillReq;
    endrule

    rule doSndFillReq (mshr == SndFillReq);
        let state = (buffer.op == Ld || buffer.op == Lr) ? S : M;
        toMem.enq_req(CacheMemReq { child: id, addr: buffer.addr, state: state });
        mshr <= WaitFillResp;
    endrule

    rule doWaitFillResp (mshr == WaitFillResp && fromMem.hasResp);
        let tag = getTag(buffer.addr);
        let idx = getIndex(buffer.addr);
        let sel = getWordSelect(buffer.addr);
        CacheMemResp x = ?;
        if (fromMem.first matches tagged Resp .r) begin
            x = r;
        end
        fromMem.deq;
        CacheLine line = isValid(x.data) ? fromMaybe(?, x.data) : dataVec[idx];
        if (buffer.op == St) begin
            let old_line = isValid(x.data) ? fromMaybe(?, x.data) : dataVec[idx];
            refDMem.commit(buffer, Valid(old_line), Invalid);
            line[sel] = buffer.data;
        end
        else if (buffer.op == Sc) begin
            if (isValid(lineAddr) && fromMaybe(?, lineAddr) == getLineAddr(buffer.addr)) begin
                let lastMod = isValid(x.data) ? fromMaybe(?, x.data) : dataVec[idx];
                refDMem.commit(buffer, Valid(lastMod), Valid(scSucc));
                line[sel] = buffer.data;
                hitQ.enq(scSucc);
            end
            else begin
                hitQ.enq(scFail);
                refDMem.commit(buffer, Invalid, Valid(scFail));
            end
            lineAddr <= Invalid;
        end
        dataVec[idx] <= line;
        tagVec[idx] <= tag;
        privVec[idx] <= x.state;
        mshr <= Resp;
    endrule

    rule doResp (mshr == Resp);
        let idx = getIndex(buffer.addr);
        let sel = getWordSelect(buffer.addr);
        if (buffer.op == Ld || buffer.op == Lr) begin
            hitQ.enq(dataVec[idx][sel]);
            refDMem.commit(buffer, Valid(dataVec[idx]), Valid(dataVec[idx][sel]));
            if (buffer.op == Lr) begin
                lineAddr <= tagged Valid getLineAddr(buffer.addr);
            end
        end
        mshr <= Rdy;
    endrule

    rule doDng (mshr != Resp && !fromMem.hasResp && fromMem.hasReq);
        CacheMemReq x = ?;
        if (fromMem.first matches tagged Req .r) begin
            x = r;
        end
        let sel = getWordSelect(x.addr);
        let idx = getIndex(x.addr);
        let tag = getTag(x.addr);
        if (privVec[idx] > x.state) begin
            Maybe#(CacheLine) line = (privVec[idx] == M) ? Valid(dataVec[idx]) : Invalid;
            let addr = { tag, idx, sel, 2'b0 };
            toMem.enq_resp(CacheMemResp {
                child: id,
                addr: addr,
                state: x.state,
                data: line
            });
            privVec[idx] <= x.state;
            if (x.state == I) begin
                lineAddr <= Invalid;
            end
        end
        fromMem.deq;
    endrule

    method Action req(MemReq r);
        reqQ.enq(r);
        refDMem.issue(r);
    endmethod

    method ActionValue#(Data) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
endmodule
