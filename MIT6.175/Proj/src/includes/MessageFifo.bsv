import CacheTypes::*;
import Fifo::*;

module mkMessageFifo(MessageFifo#(n));

    Fifo#(2, CacheMemResp) resp_fifo <- mkCFFifo;
    Fifo#(2, CacheMemReq)  req_fifo  <- mkCFFifo;

    method Action enq_resp(CacheMemResp d);
        resp_fifo.enq(d);
    endmethod

    method Action enq_req(CacheMemReq d);
        req_fifo.enq(d);
    endmethod

    method Bool hasResp = resp_fifo.notEmpty;

    method Bool hasReq = req_fifo.notEmpty;

    method Bool notEmpty = (resp_fifo.notEmpty || req_fifo.notEmpty);

    method CacheMemMessage first;
        if (resp_fifo.notEmpty) begin
            return tagged Resp resp_fifo.first;
        end
        else begin
            return tagged Req req_fifo.first;
        end
    endmethod

    method Action deq;
        if (resp_fifo.notEmpty) begin
            resp_fifo.deq;
        end
        else begin
            req_fifo.deq;
        end
    endmethod


endmodule
