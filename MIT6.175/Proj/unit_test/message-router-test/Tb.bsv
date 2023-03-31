import StmtFSM::*;
import Vector::*;

import MessageFifo::*;
import MessageRouter::*;
import CacheTypes::*;
import Types::*;

// This tests some things about the message router:
//  1) Messages get routed from children to the parent
//  2) Messages from the parent get sent to the right child
//  3) If the network is full of requests, responses can still pass through
//  4) If one of the r2c FIFOs is full but m2r is empty, messages can get sent to the other r2c FIFO

(* synthesize *)
module mkTb(Empty);
    // cache to router
    Vector#(CoreNum, MessageFifo#(2)) c2r <- replicateM(mkMessageFifo);
    // router to cache
    Vector#(CoreNum, MessageFifo#(2)) r2c <- replicateM(mkMessageFifo);
    // router to memory
    MessageFifo#(2) r2m <- mkMessageFifo;
    // memory to router
    MessageFifo#(2) m2r <- mkMessageFifo;

    let router <- mkMessageRouter(
		map(toMessageGet, c2r), 
		map(toMessagePut, r2c), 
		toMessageGet(m2r), 
		toMessagePut(r2m) 
	);

    function Action checkpoint(Integer i);
        return (action
					$display("Checkpoint %0d", i);
                endaction);
    endfunction

    // wait until message comes
    function Action getMessage(MessageFifo#(2) fifo, CacheMemMessage m);
        return (action
                    if( m == fifo.first ) begin
                        // all is good
                        fifo.deq();
                    end else begin
                        $fwrite(stderr, "ERROR: Expected message didn't match message_fifo.first\n");
                        $fwrite(stderr, "    Expected message   = ", fshow(m), "\n");
                        $fwrite(stderr, "    message_fifo.first = ", fshow(fifo.first), "\n");
                        $finish;
                    end
                endaction);
    endfunction

	// regs for temporarily storing data from fifos
	Reg#(CacheMemMessage) x <- mkRegU;
	Reg#(CacheMemMessage) y <- mkRegU;

	function Stmt getTwoMsg(MessageFifo#(2) fifo, CacheMemMessage m1, CacheMemMessage m2);
		return (seq
					action
						x <= fifo.first;
						fifo.deq;
					endaction
					action
						y <= fifo.first;
						fifo.deq;
					endaction
					action
						if(x == m1 && y == m2 || x == m2 && y == m1) begin
							// good
						end
						else begin
							$fwrite(stderr, "ERROR: Expected two messages didn't match messages received\n");
							$fwrite(stderr, "    Expected messages = ", fshow(m1), ", ", fshow(m2), "\n");
							$fwrite(stderr, "    Actually receive  = ", fshow(x), ", ", fshow(y), "\n");
							$finish;
						end
					endaction
				endseq);
	endfunction

    function Action wait_for_resp(MessageFifo#(2) fifo) = when( fifo.hasResp, noAction );

	function Stmt getTwoResp(MessageFifo#(2) fifo, CacheMemResp r1, CacheMemResp r2);
		return (seq
					action
						wait_for_resp(fifo);
						x <= fifo.first;
						fifo.deq;
					endaction
					action
						wait_for_resp(fifo);
						y <= fifo.first;
						fifo.deq;
					endaction
					action
						CacheMemMessage m1 = tagged Resp r1;
						CacheMemMessage m2 = tagged Resp r2;
						if(x == m1 && y == m2 || x == m2 && y == m1) begin
							// good
						end
						else begin
							$fwrite(stderr, "ERROR: Expected responses didn't match messages received\n");
							$fwrite(stderr, "    Expected responses = ", fshow(m1), ", ", fshow(m2), "\n");
							$fwrite(stderr, "    Actually receive   = ", fshow(x), ", ", fshow(y), "\n");
							$finish;
						end
					endaction
				endseq);
	endfunction

	function CacheMemReq genReq(CoreID id, Addr a, MSI s);
		return CacheMemReq {child: id, addr: a, state: s};
	endfunction
	function CacheMemResp genResp(CoreID id, Addr a, MSI s, Maybe#(CacheLine) d);
		return CacheMemResp {child: id, addr: a, state: s, data: d};
	endfunction


    // This uses StmtFSM to create an FSM for testing
    // See the bluespec reference guide for more info
    Stmt test = (seq
		checkpoint(0);
		c2r[0].enq_req( genReq(0, 10, S) );
		c2r[1].enq_req( genReq(1, 20, M) );
		getTwoMsg( r2m, tagged Req genReq(0, 10, S), tagged Req genReq(1, 20, M) );
		
		checkpoint(1);
		c2r[0].enq_resp( genResp(0, 30, I, tagged Valid unpack(31)) );
		c2r[1].enq_resp( genResp(1, 40, S, tagged Valid unpack(42)) );
		getTwoMsg( r2m, tagged Resp genResp(0, 30, I, tagged Valid unpack(31)), tagged Resp genResp(1, 40, S, tagged Valid unpack(42)) );

		checkpoint(2);
		c2r[0].enq_req( genReq(0, 50, M) );
		c2r[1].enq_resp( genResp(1, 60, I, tagged Valid unpack(63)) );
		wait_for_resp( r2m );
		getMessage( r2m, tagged Resp genResp(1, 60, I, tagged Valid unpack(63)) );
		getMessage( r2m, tagged Req genReq(0, 50, M) );

		checkpoint(3);
		c2r[1].enq_req( genReq(1, 70, S) );
		c2r[0].enq_resp( genResp(0, 80, S, tagged Valid unpack(84)) );
		wait_for_resp( r2m );
		getMessage( r2m, tagged Resp genResp(0, 80, S, tagged Valid unpack(84)) );
		getMessage( r2m, tagged Req genReq(1, 70, S) );

		checkpoint(4);
		// fill up the message network with requests form one core
		c2r[1].enq_req( genReq(1, 100, M) );
		c2r[1].enq_req( genReq(1, 110, M) );
		c2r[1].enq_req( genReq(1, 120, S) );
		c2r[1].enq_req( genReq(1, 130, S) );

		checkpoint(5);
		// send responses
		c2r[0].enq_resp( genResp(0, 140, I, tagged Valid unpack(14)) );
		c2r[1].enq_resp( genResp(1, 150, S, tagged Valid unpack(15)) );
		getTwoResp( r2m, genResp(0, 140, I, tagged Valid unpack(14)), genResp(1, 150, S, tagged Valid unpack(15)) );

		checkpoint(6);
		// dequeue requests
		getMessage( r2m, tagged Req genReq(1, 100, M) );
		getMessage( r2m, tagged Req genReq(1, 110, M) );
		getMessage( r2m, tagged Req genReq(1, 120, S) );
		getMessage( r2m, tagged Req genReq(1, 130, S) );

		checkpoint(7);
		// fill up the message netowrk with requests from two cores
		c2r[1].enq_req( genReq(1, 200, S) );
		c2r[1].enq_req( genReq(1, 210, S) );
		c2r[1].enq_req( genReq(1, 220, M) );
		c2r[1].enq_req( genReq(1, 230, M) );
		c2r[0].enq_req( genReq(0, 240, S) );
		c2r[0].enq_req( genReq(0, 250, S) );

		checkpoint(8);
		// send responses
		c2r[0].enq_resp( genResp(0, 260, I, tagged Valid unpack(26)) );
		c2r[1].enq_resp( genResp(1, 270, S, tagged Valid unpack(27)) );
		getTwoResp( r2m, genResp(0, 260, I, tagged Valid unpack(26)), genResp(1, 270, S, tagged Valid unpack(27)) );

		checkpoint(9);
		// dequeue requests
		r2m.deq;
		r2m.deq;
		r2m.deq;
		r2m.deq;
		r2m.deq;
		r2m.deq;

		// Now lets test child to parent

		checkpoint(10);
		m2r.enq_req( genReq(1, 300, I) );
		m2r.enq_req( genReq(0, 310, S) );
		getMessage( r2c[1], tagged Req genReq(1, 300, I) );
		getMessage( r2c[0], tagged Req genReq(0, 310, S) );

		checkpoint(11);
		m2r.enq_resp( genResp(0, 320, S, tagged Valid unpack(32)) );
		m2r.enq_resp( genResp(1, 330, M, tagged Valid unpack(33)) );
		getMessage( r2c[1], tagged Resp genResp(1, 330, M, tagged Valid unpack(33)) );
		getMessage( r2c[0], tagged Resp genResp(0, 320, S, tagged Valid unpack(32)) );

		checkpoint(12);
		// Fill up r2c[0]
		m2r.enq_req( genReq(0, 400, I) );
		m2r.enq_req( genReq(0, 410, S) );
		m2r.enq_resp( genResp(0, 420, M, tagged Valid unpack(42)) );
		m2r.enq_resp( genResp(0, 430, S, tagged Valid unpack(43)) );
		// Fill up r2c[1]
		m2r.enq_req( genReq(1, 440, I) );
		m2r.enq_req( genReq(1, 450, S) );
		m2r.enq_resp( genResp(1, 460, M, tagged Valid unpack(46)) );
		m2r.enq_resp( genResp(1, 470, S, tagged Valid unpack(47)) );
		// Drain r2c[1]
		wait_for_resp( r2c[1] );
		getMessage( r2c[1], tagged Resp genResp(1, 460, M, tagged Valid unpack(46)) );
		wait_for_resp( r2c[1]);
		getMessage( r2c[1], tagged Resp genResp(1, 470, S, tagged Valid unpack(47)) );
		getMessage( r2c[1], tagged Req genReq(1, 440, I) );
		getMessage( r2c[1], tagged Req genReq(1, 450, S) );
		// Drain r2c[0]
		wait_for_resp( r2c[0] );
		getMessage( r2c[0], tagged Resp genResp(0, 420, M, tagged Valid unpack(42)) );
		wait_for_resp( r2c[0] );
		getMessage( r2c[0], tagged Resp genResp(0, 430, S, tagged Valid unpack(43)) );
		getMessage( r2c[0], tagged Req genReq(0, 400, I) );
		getMessage( r2c[0], tagged Req genReq(0, 410, S) );

		$display("PASSED");
		$finish;
	endseq);
    mkAutoFSM(test);

    // Timeout FSM
    // If the test doesn't finish in 1000 cycles, this prints an error
    Stmt timeout = (seq
                        delay(1000);
                        (action
                            $fwrite(stderr, "ERROR: Testbench stalled.\n");
                            //if(!debug) $fwrite(stderr, "Set debug to true in mkMessageFifoTest and recompile to get more info\n");
                        endaction);
                        $finish;
                    endseq);
    mkAutoFSM(timeout);
endmodule
