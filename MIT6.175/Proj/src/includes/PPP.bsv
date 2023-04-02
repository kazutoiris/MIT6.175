import ProcTypes::*;
import MemTypes::*;
import Types::*;
import CacheTypes::*;
import MessageFifo::*;
import Vector::*;
import FShow::*;

function Bool isStateM(MSI s);
    return s == M;
endfunction

function Bool isStateS(MSI s);
    return s == S;
endfunction

function Bool isStateI(MSI s);
    return s == I;
endfunction

function Bool isCompatible(MSI a, MSI b);
    return a == I || b == I || (a == S && b == S);
endfunction

module mkPPP(MessageGet c2m, MessagePut m2c, WideMem mem, Empty ifc);
    Vector#(CoreNum, Vector#(CacheRows, Reg#(MSI)))      childState <- replicateM(replicateM(mkReg(I)));
    Vector#(CoreNum, Vector#(CacheRows, Reg#(CacheTag)))   childTag <- replicateM(replicateM(mkRegU));
    Vector#(CoreNum, Vector#(CacheRows, Reg#(Bool)))      waitState <- replicateM(replicateM(mkReg(False)));

    Reg#(Bool)  missReg <- mkReg(False);
    Reg#(Bool) readyReg <- mkReg(False);

    rule parentResp (!c2m.hasResp && !missReg && readyReg);
        let           req = c2m.first.Req;
        let           idx = getIndex(req.addr);
        let           tag = getTag(req.addr);
        let         child = req.child;
        Bool willConflict = False;
        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            if (fromInteger(i) != child) begin
                MSI s = (childTag[i][idx] == tag) ? childState[i][idx] : I;
                if (!isCompatible(s, req.state) || waitState[child][idx]) begin
                    willConflict = True;
                end
            end
        end
        if (!willConflict) begin
            MSI state = (childTag[child][idx] == tag) ? childState[child][idx] : I;
            if (!isStateI(state)) begin
                m2c.enq_resp(CacheMemResp {
                    child: child,
                    addr: req.addr,
                    state: req.state,
                    data: Invalid
                });
                childState[child][idx] <= req.state;
                childTag[child][idx] <= tag;
                c2m.deq;
            end
            else begin
                mem.req(WideMemReq {
                    write_en: '0,
                    addr: req.addr,
                    data: ?
                });
                missReg <= True;
            end
            readyReg <= False;
        end
    endrule

    rule dwn (!c2m.hasResp && !missReg && !readyReg);
        let   req = c2m.first.Req;
        let   idx = getIndex(req.addr);
        let   tag = getTag(req.addr);
        let child = req.child;

        Maybe#(Integer) sendCore = tagged Invalid;
        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            if (fromInteger(i) != child) begin
                MSI state = (childTag[i][idx] == tag)? childState[i][idx] : I;
                if (!isCompatible(state, req.state) && !waitState[i][idx]) begin
                    if (!isValid(sendCore)) begin
                        sendCore = tagged Valid i;
                    end
                end
            end
        end
        if (!isValid(sendCore)) begin
            readyReg <= True;
        end
        else begin
            waitState[fromMaybe(?, sendCore)][idx] <= True;
            m2c.enq_req(CacheMemReq {
                child: fromInteger(fromMaybe(?, sendCore)),
                addr:req.addr,
                state: (req.state == M ? I : S)
            });
        end
    endrule

    rule parentDataResp (!c2m.hasResp && missReg);
        let req = c2m.first.Req;
        let idx = getIndex(req.addr);
        let tag = getTag(req.addr);
        let child = req.child;
        let line <- mem.resp();
        m2c.enq_resp(CacheMemResp {
            child: child,
            addr: req.addr,
            state: req.state,
            data: Valid(line)
        });
        childState[child][idx] <= req.state;
        childTag[child][idx] <= tag;
        c2m.deq;
        missReg <= False;
    endrule

    rule dwnRsp (c2m.hasResp);
        let resp = c2m.first.Resp;
        c2m.deq;
        let idx = getIndex(resp.addr);
        let tag = getTag(resp.addr);
        let child = resp.child;
        MSI status = (childTag[child][idx] == tag) ? childState[child][idx] : I;
        if (isStateM(status)) begin
            mem.req(WideMemReq{
                write_en: '1,
                addr: resp.addr,
                data: fromMaybe(?, resp.data)
            });
        end
        childState[child][idx] <= resp.state;
        waitState[child][idx] <= False;
        childTag[child][idx] <= tag;
    endrule
endmodule
