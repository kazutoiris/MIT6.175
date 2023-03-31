import CacheTypes::*;
import Vector::*;
import FShow::*;
import MemTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Ehr::*;
import RefTypes::*;
import StQ::*;


typedef enum{Ready, StartMiss, SendFillReq, WaitFillResp, Resp} CacheStatus
    deriving(Eq, Bits);
module mkDCacheLHUSM#(CoreID id)(
        MessageGet fromMem,
        MessagePut toMem,
        RefDMem refDMem,
        DCache ifc
	);

    Reg#(CacheStatus) status <- mkReg(Ready);

    Vector#(CacheRows, Reg#(CacheLine)) dataArray <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(CacheTag)) tagArray <- replicateM(mkRegU);
    Vector#(CacheRows, Reg#(MSI)) privArray <- replicateM(mkReg(I));

    Fifo#(2, Data) hitQ <- mkBypassFifo;
    Fifo#(1, MemReq) reqQ <- mkBypassFifo;
    Reg#(MemReq) missReq <- mkRegU;

    Reg#(Maybe#(CacheLineAddr)) linkAddr <- mkReg(Invalid);

    StQ#(StQSize) stq <-mkStQ;

    Reg#(Maybe#(Data)) scResp <- mkReg(Invalid);

    Reg#(Bool) loadMiss <- mkReg(False);

    rule doStore (reqQ.first.op == St);

        MemReq r = reqQ.first;
        reqQ.deq;
        stq.enq(r);

    endrule


    rule doSc (status == Ready && reqQ.first.op == Sc && !stq.notEmpty);

        MemReq r = reqQ.first;
        reqQ.deq;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        if (linkAddr matches tagged Valid .la &&& la == getLineAddr(r.addr)) begin

            if (tagArray[idx] == tag && privArray[idx] > I) begin

                if (privArray[idx] == M) begin
                    hitQ.enq(scSucc);
                    dataArray[idx][sel] <= r.data;
                    refDMem.commit(r, Valid(dataArray[idx]), Valid(scSucc));
                    linkAddr <= Invalid;
                end
                else begin
                    missReq <= r;
                    status <= SendFillReq;
                end
            end
            else begin
                missReq <= r;
                status <= StartMiss;
            end
        end
        else begin
            hitQ.enq(scFail);
            refDMem.commit(r, Invalid, Valid(scFail));
            linkAddr <= Invalid;
        end

    endrule


    rule doFence (status == Ready && reqQ.first.op == Fence && !stq.notEmpty);
        reqQ.deq;
        refDMem.commit(reqQ.first, Invalid, Invalid);
    endrule


    rule startMiss (status == StartMiss);

        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = tagArray[idx];

        if (privArray[idx] != I) begin

           privArray[idx] <= I;

           Maybe#(CacheLine) line;
           if (privArray[idx] == M)
                line = Valid(dataArray[idx]);
           else
                line = Invalid;

           let addr = {tag, idx, sel, 2'b0};
           toMem.enq_resp( CacheMemResp {child: id,
                                  addr: addr,
                                  state: I,
                                  data: line});
        end
        status <= SendFillReq;
        if (isValid(linkAddr) &&
            fromMaybe(?, linkAddr) == getLineAddr(missReq.addr)) begin
               linkAddr <= Invalid;
        end

    endrule


    rule sendFillReq (status == SendFillReq);

        let upg = (missReq.op == Ld || missReq.op == Lr)? S : M;
        toMem.enq_req( CacheMemReq {child: id, addr:missReq.addr, state: upg});
        status <= WaitFillResp;

    endrule


    rule waitFillResp (status == WaitFillResp && fromMem.hasResp);

        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);

        CacheMemResp x = fromMem.first.Resp;

        CacheLine line;
        if (isValid(x.data)) line = fromMaybe(?, x.data);
        else line = dataArray[idx];

        Bool check = False;
        if (missReq.op == St) begin
            let old_line = isValid(x.data) ? fromMaybe(?, x.data) : dataArray[idx];
            refDMem.commit(missReq, Valid(old_line), Invalid);
            line[sel] = missReq.data;
            stq.deq;
        end
        else if (missReq.op == Sc) begin
            if (isValid(linkAddr) &&
                fromMaybe(?, linkAddr) == getLineAddr(missReq.addr)) begin

                let old_line = dataArray[idx];
                if (isValid(x.data)) old_line = fromMaybe(?, x.data);
                line[sel] = missReq.data;
                scResp <= Valid(scSucc);
            end
            else begin
                scResp <= Valid(scFail);
            end
            linkAddr <= Invalid;
        end

        dataArray[idx] <= line;
        tagArray[idx] <= tag;
        privArray[idx] <= x.state;
        fromMem.deq;
        status <= Resp;

    endrule


    rule sendCore (status == Resp);

        CacheIndex idx = getIndex(missReq.addr);
        CacheWordSelect sel = getWordSelect(missReq.addr);

        if (missReq.op == Ld || missReq.op == Lr) begin
            hitQ.enq(dataArray[idx][sel]);
            refDMem.commit(missReq, Valid(dataArray[idx]),
                            Valid(dataArray[idx][sel]));

            if (missReq.op == Lr) begin
                linkAddr <= tagged Valid getLineAddr(missReq.addr);
            end
        end
        else if (missReq.op == Sc) begin
            if (isValid(scResp)) hitQ.enq(fromMaybe(?, scResp));
            refDMem.commit(missReq, Invalid, scResp);
            scResp <= Invalid;
        end

        status <= Ready;
        loadMiss <= False;

    endrule


    rule doLoad (
                status == Ready &&
                (reqQ.first.op == Ld || (reqQ.first.op == Lr && !stq.notEmpty)) &&
                !loadMiss
                );

        MemReq r = reqQ.first;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        let hit = False;

        reqQ.deq;

        let x = stq.search(r.addr);
        if (isValid(x)) begin
            hitQ.enq(fromMaybe(?, x));
            refDMem.commit(r, Invalid, x);
            hit = True;
        end
        else begin

            if (tagArray[idx] == tag && privArray[idx] > I) begin

                hitQ.enq(dataArray[idx][sel]);
                refDMem.commit(r, Valid(dataArray[idx]),
                                Valid(dataArray[idx][sel]));
                hit = True;

            end
            else begin
                missReq <= r;
                status <= StartMiss;
                loadMiss <= True;
            end
        end

        if (hit && r.op == Lr)
            linkAddr <= tagged Valid getLineAddr(r.addr);
    endrule

    rule doLHUSM (
                status != Ready &&
                !fromMem.hasResp && !fromMem.hasReq &&
                missReq.op == St &&
                (reqQ.first.op == Ld || (reqQ.first.op == Lr && !stq.notEmpty)) &&
                !loadMiss
                );

        MemReq r = reqQ.first;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        let hit = False;

        let x = stq.search(r.addr);
        if (isValid(x)) begin

            hitQ.enq(fromMaybe(?, x));
            refDMem.commit(r, Invalid, x);
            hit = True;
            reqQ.deq;
        end

        else if (tagArray[idx] == tag && privArray[idx] > I) begin

            hitQ.enq(dataArray[idx][sel]);
            refDMem.commit(r, Valid(dataArray[idx]),
                            Valid(dataArray[idx][sel]));
            hit = True;
            reqQ.deq;

        end


        if (hit && r.op == Lr)
            linkAddr <= tagged Valid getLineAddr(r.addr);
    endrule

    rule dng (status != Resp && !fromMem.hasResp);

        CacheMemReq x = fromMem.first.Req;

        CacheWordSelect sel = getWordSelect(x.addr);
        CacheIndex idx = getIndex(x.addr);
        let tag = getTag(x.addr);


        if (privArray[idx] > x.state) begin

           Maybe#(CacheLine) line;
           if (privArray[idx] == M) line = Valid(dataArray[idx]);
           else line = Invalid;

           let addr = {tag, idx, sel, 2'b0};
           toMem.enq_resp( CacheMemResp {child: id,
                                  addr: addr,
                                  state: x.state,
                                  data: line});

            privArray[idx] <= x.state;
            if (linkAddr matches tagged Valid .la &&& la == getLineAddr(x.addr)
                && x.state == I) linkAddr <= Invalid;
        end

        fromMem.deq;
    endrule


    rule mvStqToCache (status == Ready && stq.notEmpty &&
        (!reqQ.notEmpty || reqQ.first.op != Ld));

        MemReq r <- stq.issue;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        if (tagArray[idx] == tag && privArray[idx] > I) begin
            if (privArray[idx] == M) begin

                dataArray[idx][sel] <= r.data;
                refDMem.commit(r, Valid(dataArray[idx]), Invalid);
                stq.deq;
                if (linkAddr matches tagged Valid .la &&& la == getLineAddr(r.addr))
                    linkAddr <= Invalid;
            end
            else begin

                missReq <= r;
                status <= SendFillReq;
            end
        end
        else begin

            missReq <= r;
            status <= StartMiss;
        end
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
