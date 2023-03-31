import StmtFSM::*;
import Vector::*;

import MessageFifo::*;
import CacheTypes::*;
import Types::*;

// This tests two things about the message FIFO:
//  1) can you enq and deq with this fifo?
//  2) do responses overtake requests?

(* synthesize *)
module mkTb(Empty);
    // Set this to true to see more messages displayed to stdout
    Bool debug = False;

    MessageFifo#(2) message_fifo <- mkMessageFifo;

    Action display_debug_message = 
        (action
            $display("message_fifo state:");
            $display("    notEmpty = ", fshow(message_fifo.notEmpty));
            $display("    hasResp = ", fshow(message_fifo.hasResp));
            $display("    hasReq = ", fshow(message_fifo.hasReq));
            if( message_fifo.notEmpty ) begin
                $display("    first = ", fshow(message_fifo.first));
            end else begin
                $display("    first = (empty)");
            end
        endaction);

    Action check_state =
        (action
            if( message_fifo.notEmpty != (message_fifo.hasResp || message_fifo.hasReq) ) begin
                $fwrite(stderr, "ERROR: message_fifo.notEmpty doesn't match hasResp and hasReq.\n");
                $finish;
            end
            if( message_fifo.notEmpty ) begin
                if( message_fifo.first matches tagged Req .req ) begin
                    // first is a request
                    if( message_fifo.hasResp ) begin
                        // but there is a response in the message fifo
                        $fwrite(stderr, "ERROR: There is a response in the fifo, but first returns a request.\n");
                        $finish;
                    end
                end
            end
        endaction);

    function Action checkpoint(Integer i);
        return (action
					$display("Checkpoint %0d", i);
                    if( debug ) begin
                        display_debug_message;
                    end
                    check_state;
                endaction);
    endfunction

    function Action dequeue(CacheMemMessage m);
        return (action
                    if( message_fifo.notEmpty ) begin
                        if( m == message_fifo.first ) begin
                            // all is good
                            message_fifo.deq();
                        end else begin
                            $fwrite(stderr, "ERROR: Expected message didn't match message_fifo.first\n");
                            $fwrite(stderr, "    Expected message = ", fshow(m), "\n");
                            $fwrite(stderr, "    message_fifo.first = ", fshow(message_fifo.first), "\n");
                            $finish;
                        end
                    end else begin
                        $fwrite(stderr, "ERROR: Expected message in fifo, but message_fifo was empty\n");
                        $finish;
                    end
                endaction);
    endfunction

    Action wait_for_message = when( message_fifo.notEmpty, noAction );

	function CacheMemReq genReq(CoreID id, Addr a, MSI s);
		return CacheMemReq {child: id, addr: a, state: s};
	endfunction
	function CacheMemResp genResp(CoreID id, Addr a, MSI s, Maybe#(CacheLine) d);
		return CacheMemResp {child: id, addr: a, state: s, data: d};
	endfunction

    // This uses StmtFSM to create an FSM for testing
    // See the bluespec reference guide for more info
    Stmt test = (seq
                    // Test 1: enqueue/dequeue one request
                    checkpoint(0);
                    message_fifo.enq_req(genReq(0, 1, I));
                    checkpoint(1);
                    dequeue(tagged Req genReq(0, 1, I));
                    // Test 2: enqueue/dequeue one response
                    checkpoint(2);
                    message_fifo.enq_resp(genResp(1, 2, S, tagged Valid unpack(100)));
                    checkpoint(3);
                    dequeue(tagged Resp genResp(1, 2, S, tagged Valid unpack(100)));
                    // Test 3: enqueue response then request, dequeue response then request
                    checkpoint(4);
                    message_fifo.enq_resp(genResp(0, 3, M, tagged Valid unpack(200)));
                    checkpoint(5);
                    message_fifo.enq_req(genReq(1, 4, I));
                    checkpoint(6);
                    dequeue(tagged Resp genResp(0, 3, M, tagged Valid unpack(200)));
                    checkpoint(7);
                    dequeue(tagged Req genReq(1, 4, I));
                    // Test 4: enqueue request then response, dequeue response then request
                    checkpoint(8);
                    message_fifo.enq_req(genReq(0, 5, S));
                    checkpoint(9);
                    message_fifo.enq_resp(genResp(1, 6, M, tagged Valid unpack(300)));
                    checkpoint(10);
                    dequeue(tagged Resp genResp(1, 6, M, tagged Valid unpack(300)));
                    checkpoint(11);
                    dequeue(tagged Req genReq(0, 5, S));
                    checkpoint(12);
                    $display("PASSED");
                    $finish;
                endseq);
    mkAutoFSM(test);

    // Timeout FSM
    // If the test doesn't finish in 100 cycles, this prints an error
    Stmt timeout = (seq
                        delay(100);
                        (action
                            $fwrite(stderr, "ERROR: Testbench stalled.\n");
                            if(!debug) $fwrite(stderr, "Set debug to true in mkMessageFifoTest and recompile to get more info\n");
                        endaction);
                        $finish;
                    endseq);
    mkAutoFSM(timeout);
endmodule
