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

    Reg#(CoreID) start_core <- mkReg(0);
    CoreID max_core = fromInteger(valueOf(CoreNum) - 1);

    rule core2mem;

        CoreID core_select = 0;
        Bool found_msg = False;
        Bool found_resp = False;
        for (Integer i=0; i<valueOf(CoreNum); i=i+1) begin

            CoreID core_iter;
            if (start_core <= max_core - fromInteger(i))
                core_iter = start_core + fromInteger(i);
            else
                core_iter = start_core - fromInteger(valueOf(CoreNum) - i);


            if (c2r[core_iter].notEmpty) begin
                CacheMemMessage x = c2r[core_iter].first;
                if (x matches tagged Resp .r &&& !found_resp) begin
                    core_select = core_iter;
                    found_resp = True;
                    found_msg = True;
                end
                else if (!found_msg) begin
                    core_select = core_iter;
                    found_msg = True;
                end
            end
        end

        if (found_msg) begin
            CacheMemMessage x = c2r[core_select].first;
            case (x) matches
                tagged Resp .resp : r2m.enq_resp(resp);
                tagged Req .req : r2m.enq_req(req);
            endcase
            c2r[core_select].deq;
        end

        if (start_core == max_core) start_core <= 0;
        else start_core <= start_core + 1;
    endrule

    rule mem2core;

        let x = m2r.first;
        m2r.deq;

        case (x) matches
            tagged Resp .resp : r2c[resp.child].enq_resp(resp);
            tagged Req .req : r2c[req.child].enq_req(req);
        endcase

    endrule

endmodule

