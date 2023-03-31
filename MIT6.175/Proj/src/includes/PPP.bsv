import ProcTypes::*;
import MemTypes::*;
import Types::*;
import CacheTypes::*;
import MessageFifo::*;
import Vector::*;
import FShow::*;


module mkPPP(MessageGet c2m, MessagePut m2c, WideMem mem, Empty ifc);

    Vector#(CoreNum, Vector#(CacheRows, Reg#(MSI))) childState <- replicateM(replicateM(mkReg(I)));
    Vector#(CoreNum, Vector#(CacheRows, Reg#(CacheTag))) childTag <- replicateM(replicateM(mkRegU));
    Vector#(CoreNum, Vector#(CacheRows, Reg#(Bool))) waitc <- replicateM(replicateM(mkReg(False)));

    Reg#(Bool) missReg <- mkReg(False);
    Reg#(Bool) readyReg <- mkReg(False);

    function Bool isCompatible(MSI a, MSI b) =
        ((a == I || b == I) || (a == S && b == S));


    rule parentResp (!c2m.hasResp && !missReg  && readyReg);

        let req = c2m.first.Req;
        let idx = getIndex(req.addr);
        let tag = getTag(req.addr);
        let c = req.child;

        Bool safe = True;
        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            if (fromInteger(i) != c) begin
                MSI s = (childTag[i][idx] == tag)? childState[i][idx] : I;
                if (!isCompatible(s, req.state) || waitc[c][idx]) begin
                    safe = False;
                end
            end
        end

        if (safe) begin
            MSI s = (childTag[c][idx] == tag) ? childState[c][idx] : I;
            if (s != I) begin
                m2c.enq_resp(CacheMemResp {
                    child: c,
                    addr:req.addr,
                    state:req.state,
                    data:Invalid
                } );

                childState[c][idx] <= req.state;
                childTag[c][idx] <= tag;
                c2m.deq;
                readyReg <= False;

            end
            else begin
                mem.req(WideMemReq{
                        write_en: '0,
                        addr: req.addr,
                        data: ? } );
                missReg <= True;
                readyReg <= False;
            end

        end

    endrule


    rule dwn (!c2m.hasResp && !missReg && !readyReg);

        let req = c2m.first.Req;
        let idx = getIndex(req.addr);
        let tag = getTag(req.addr);
        let c = req.child;

        Integer send_req = -1;
        for (Integer i=0; i < valueOf(CoreNum); i=i+1) begin
            if (fromInteger(i) != c) begin
                MSI s = (childTag[i][idx] == tag)? childState[i][idx] : I;
                if (!isCompatible(s, req.state) && !waitc[i][idx]) begin
                    if (send_req == -1) begin
                        send_req = i;
                    end
                end
            end
        end

        if (send_req > -1) begin

            waitc[send_req][idx] <= True;
            m2c.enq_req(CacheMemReq
                        {child: fromInteger(send_req),
                         addr:req.addr,
                         state: (req.state == M? I:S) } );
        end
        else begin
            readyReg <= True;
        end
    endrule

    rule parentDataResp (!c2m.hasResp && missReg);

        let req = c2m.first.Req;
        let idx = getIndex(req.addr);
        let tag = getTag(req.addr);
        let c = req.child;
        let line <- mem.resp();

        m2c.enq_resp(CacheMemResp {child: c,
                                   addr:req.addr,
                                   state:req.state,
                                   data:Valid(line)} );

        childState[c][idx] <= req.state;
        childTag[c][idx] <= tag;

        c2m.deq;
        missReg <= False;

    endrule


    rule dwnRsp (c2m.hasResp);

        let resp = c2m.first.Resp;
        c2m.deq;

        let idx = getIndex(resp.addr);
        let tag = getTag(resp.addr);

        let c = resp.child;

        MSI s = (childTag[c][idx] == tag)? childState[c][idx] : I;
        if (s == M) begin

            Bit#(CacheLineWords) en = '1;

            mem.req(WideMemReq{
                write_en: en,
                addr: resp.addr,
                data: fromMaybe(?, resp.data) } );

        end

        childState[c][idx] <= resp.state;
        waitc[c][idx] <= False;
        childTag[c][idx] <= tag;

    endrule


endmodule

