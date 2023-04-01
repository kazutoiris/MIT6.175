import Vector::*;
import CacheTypes::*;
import MessageFifo::*;
import Types::*;


module mkMessageRouter(
    Vector#(CoreNum, MessageGet) c2r,
    Vector#(CoreNum, MessagePut) r2c,
    MessageGet m2r,
    MessagePut r2m,
    Empty ifc
);
    rule core2mem;
        CoreID core_id = 0;
        Bool hasResp = False;
        Bool hasMsg = False;
        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            if (c2r[fromInteger(i)].notEmpty) begin
                let x = c2r[fromInteger(i)].first;
                if (x matches tagged Resp .r) begin
                    if (!hasResp) begin
                        core_id = fromInteger(i);
                        hasResp = True;
                        hasMsg = True;
                    end
                end
                else if (x matches tagged Req .r) begin
                    if (!hasMsg && !hasResp) begin
                        core_id = fromInteger(i);
                        hasMsg = True;
                    end
                end
            end
        end
        if (hasMsg || hasResp) begin
            let x = c2r[core_id].first;
            case (x) matches
                tagged Resp .resp : r2m.enq_resp(resp);
                tagged Req .req : r2m.enq_req(req);
            endcase
            c2r[core_id].deq;
        end
    endrule

    rule mem2core;
        let x = m2r.first;
        case (x) matches
            tagged Resp .resp : r2c[resp.child].enq_resp(resp);
            tagged Req .req : r2c[req.child].enq_req(req);
        endcase
        m2r.deq;
    endrule
endmodule
