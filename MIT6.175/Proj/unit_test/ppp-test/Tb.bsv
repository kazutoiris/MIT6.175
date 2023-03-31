import RegFile::*;
import StmtFSM::*;
import Vector::*;

import Fifo::*;
import Types::*;
import MemTypes::*;
import CacheTypes::*;
import MessageFifo::*;
import PPP::*;

// Dummy WideMem module for testing, only has address 0
// init mem value is 0
module mkWideMemRegFile(WideMem);
    Reg#(CacheLine) rf <- mkReg(unpack(0));
    Fifo#(2, CacheLine) respQ <- mkCFFifo;

    method Action req(WideMemReq r);
        // All the requests in this program are to address 0, so if this is a request to some other address, throw an error
        if( r.addr != 0 ) begin
            $fwrite(stderr, "ERROR: main memory got a request for an address other than 0.\n");
            $finish;
        end
        if( r.write_en == 0 ) begin
            respQ.enq(rf);
        end else if( r.write_en == maxBound ) begin
            rf <= r.data;
        end else begin
            // This shouldn't be used
            $fwrite(stderr, "ERROR: write_en in mkWideMemRegFile.req() is trying to write only some of the words in a cache line\n");
            $finish;
        end
    endmethod
    method ActionValue#(CacheLine) resp;
        respQ.deq;
        return respQ.first;
    endmethod
	method Bool respValid = respQ.notEmpty;
endmodule

// This tests the cache hierarchy parent with requests and responses for a single address
(* synthesize *)
module mkTb(Empty);
    // Set this to true to see more messages displayed to stdout
    Bool debug = True;

    MessageFifo#(2) c2pQ <- mkMessageFifo;
    MessageFifo#(2) p2cQ <- mkMessageFifo;
    WideMem widemem <- mkWideMemRegFile;

    Empty dut <- mkPPP(toMessageGet(c2pQ), toMessagePut(p2cQ), widemem);
	let toParent = toMessagePut(c2pQ);
	let fromParent = toMessageGet(p2cQ);

    function Action checkpoint(Integer i);
        return (action
					$display("Checkpoint %0d", i);
                endaction);
    endfunction

    function CacheMemReq c2p_upgradeToY(CoreID child, MSI y);
        return CacheMemReq{ child: child, addr: 0, state: y };
    endfunction

    function CacheMemResp c2p_downgradeToY(CoreID child, MSI y, Maybe#(CacheLine) d);
        return CacheMemResp{ child: child, addr: 0, state: y, data: d };
    endfunction

    function CacheMemReq p2c_downgradeToY(CoreID child, MSI y);
        return CacheMemReq{ child: child, addr: 0, state: y };
    endfunction

    function CacheMemResp p2c_upgradeToY(CoreID child, MSI y, Maybe#(CacheLine) d);
        return CacheMemResp{ child: child, addr: 0, state: y, data: d };
    endfunction

    function Action dequeue( CacheMemMessage m );
        return (action
			let incoming = fromParent.first;
			if( debug ) $display("Dequeuing ", fshow(incoming));
			case( m ) matches
				tagged Req .req: begin
					// waiting for a downgrade request
					// if we find a response or a wrong request, there was a problem
					case( incoming ) matches
						tagged Req .ireq: begin
							if( req.child == ireq.child && 
								req.state == ireq.state && 
								getLineAddr(req.addr) == getLineAddr(ireq.addr) ) begin
								// match
								fromParent.deq;
							end else begin
								// mismatch
								$fwrite(stderr, "ERROR: incoming request does not match expeted request\n");
								$fwrite(stderr, "    expected: ", fshow(req), "\n");
								$fwrite(stderr, "    incoming: ", fshow(ireq), "\n");
								$finish;
							end
						end
						tagged Resp .iresp: begin
							$fwrite(stderr, "ERROR: expected incoming request, found incoming response\n");
							$finish;
						end
						default: begin
							$fwrite(stderr, "ERROR: message should be either a Req or a Resp\n");
							$finish;
						end
					endcase
				end
				tagged Resp .resp: begin
					// waiting for an upgrade response
					// if we find a wrong response there was a problem
					case( incoming ) matches
						tagged Req .ireq: begin
							// keep waiting, maybe a response will overtake a request
							when(False, noAction);
						end
						tagged Resp .iresp: begin
							if( resp.child == iresp.child && 
								resp.state == iresp.state && 
								getLineAddr(resp.addr) == getLineAddr(iresp.addr) &&
								resp.data == iresp.data ) begin
								// match
								fromParent.deq;
							end else begin
								// mismatch
								$fwrite(stderr, "ERROR: incoming response does not match expeted response\n");
								$fwrite(stderr, "    expected: ", fshow(resp), "\n");
								$fwrite(stderr, "    incoming: ", fshow(iresp), "\n");
								$finish;
							end
						end
						default: begin
							$fwrite(stderr, "ERROR: message should be either a Req or a Resp\n");
							$finish;
						end
					endcase
				end
			endcase
		endaction);
    endfunction

	// temp regs for recording output
	Reg#(CacheMemMessage) x <- mkRegU;
	Reg#(CacheMemMessage) y <- mkRegU;

	function Bool msgEq(CacheMemMessage a, CacheMemMessage b);
		case(a) matches 
			tagged Req .ra: begin
				if( b matches tagged Req .rb &&&
					ra.child == rb.child &&&
					getLineAddr(ra.addr) == getLineAddr(rb.addr) &&&
					ra.state == rb.state ) begin
					return True;
				end 
				else begin
					return False;
				end
			end
			tagged Resp .ra: begin
				if( b matches tagged Resp. rb &&&
					ra.child == rb.child &&&
					getLineAddr(ra.addr) == getLineAddr(rb.addr) &&&
					ra.state == rb.state &&&
					ra.data == rb.data ) begin
					return True;
				end 
				else begin
					return False;
				end
			end
			default: return False;
		endcase
	endfunction

    // This uses StmtFSM to create an FSM for testing
    // See the bluespec reference guide for more info
    Stmt test = (seq
		// Current state:
		//  Core 0: I
		//  Core 1: I
		//  memory: 0

		// Test 1: core 0 upgrade to S, upgrade to M, downgrade to S, downgrade to I
		checkpoint(0);
		toParent.enq_req( c2p_upgradeToY(0, S) );
		dequeue( tagged Resp p2c_upgradeToY(0, S, Valid (unpack(0))) );
		checkpoint(1);
		toParent.enq_req( c2p_upgradeToY(0, M) );
		dequeue( tagged Resp p2c_upgradeToY(0, M, Invalid) );
		checkpoint(2);
		// This will write 17 to main memory
		toParent.enq_resp( c2p_downgradeToY(0, S, Valid (unpack(17))) );
		checkpoint(3);
		// This should not write to main memory
		toParent.enq_resp( c2p_downgradeToY(0, I, Invalid) );

		// Current state:
		//  Core 0: I
		//  Core 1: I
		//  memory: 17

		// Test 2: core 1 upgrade to M, check data from previous downgrade responses
		checkpoint(4);
		toParent.enq_req( c2p_upgradeToY(1, M) );
		// Make sure the data in the upgrade response is 17
		dequeue( tagged Resp p2c_upgradeToY(1, M, Valid (unpack(17))) );

		// Current state:
		//  Core 0: I
		//  Core 1: M
		//  memory: 17

		// Test 3: core 0 upgrade to S while other core is in M
		checkpoint(5);
		toParent.enq_req( c2p_upgradeToY(0, S) );
		// cache 1 is in M, so it will need to downgrade
		dequeue( tagged Req p2c_downgradeToY(1, S) );
		checkpoint(6);
		// 22 will get written to main memory
		toParent.enq_resp( c2p_downgradeToY(1, S, Valid (unpack(22))) );
		// now cache 0 can get upgraded to Y
		dequeue( tagged Resp p2c_upgradeToY(0, S, Valid (unpack(22))) );

		// Current state:
		//  Core 0: S
		//  Core 1: S
		//  memory: 22
		
		// Test 4: core 0 upgrade S to M
		checkpoint(7);
		toParent.enq_req( c2p_upgradeToY(0, M) );
		dequeue( tagged Req p2c_downgradeToY(1, I) );
		checkpoint(8);
		toParent.enq_resp( c2p_downgradeToY(1, I, Invalid) );
		dequeue( tagged Resp p2c_upgradeToY(0, M, Invalid) );

		// Current state:
		//  Core 0: M
		//  Core 1: I
		//  memory: 22

		// Test 5: voluntary downgrade
		checkpoint(9);
		// 200 will get written to main memory
		toParent.enq_resp( c2p_downgradeToY(0, I, Valid (unpack(200))) );

		// Current state:
		//  Core 0: I
		//  Core 1: I
		//  memory: 200

		// Test 6: both upgrade to S
		checkpoint(10);
		toParent.enq_req( c2p_upgradeToY(0, S) );
		toParent.enq_req( c2p_upgradeToY(1, S) );
		checkpoint(11);
		// in a more complicated implementation, these two could be reordered
		seq
			action
				x <= fromParent.first;
				fromParent.deq;
			endaction
			action
				y <= fromParent.first;
				fromParent.deq;
			endaction
			action
				CacheMemMessage m0 = Resp (p2c_upgradeToY(0, S, Valid (unpack(200))));
				CacheMemMessage m1 = Resp (p2c_upgradeToY(1, S, Valid (unpack(200))));
				if(msgEq(x, m0) && msgEq(y, m1) || msgEq(x, m1) && msgEq(y, m0)) begin
					// good
				end
				else begin
					$fwrite(stderr, "ERROR: incoming responses do not match expeted responses\n");
					$fwrite(stderr, "    expected: ", fshow(m0), ", ", fshow(m1), "\n");
					$fwrite(stderr, "    incoming: ", fshow(x), ", ", fshow(y), "\n");
					$finish;
				end
			endaction
		endseq

		// Current state:
		//  Core 0: S
		//  Core 1: S
		//  memory: 200

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
                            if(!debug) $fwrite(stderr, "Set debug to true in mkCacheParentTest and recompile to get more info\n");
                        endaction);
                        $finish;
                    endseq);
    mkAutoFSM(timeout);
endmodule
