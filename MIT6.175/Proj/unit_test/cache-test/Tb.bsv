import StmtFSM::*;
import Vector::*;

import Types::*;
import MemTypes::*;
import CacheTypes::*;
import RefTypes::*;
import RefDummyMem::*;
import MessageFifo::*;
import DCache::*;

(* synthesize *)
module mkTb(Empty);
    MessageFifo#(2) p2cQ <- mkMessageFifo; // parent -> cache
    MessageFifo#(2) c2pQ <- mkMessageFifo; // cache -> parent
	
	RefMem refMem <- mkRefDummyMem;

    DCache cache <- mkDCache(
		0, 
		toMessageGet(p2cQ), 
		toMessagePut(c2pQ),
		refMem.dMem[0]
	);
	let p2c = toMessagePut(p2cQ);
	let c2p = toMessageGet(c2pQ);

    function Addr address( CacheTag tag, CacheIndex index, CacheWordSelect sel );
        return {tag, index, sel, 0};
    endfunction

    function CacheMemReq c2p_upgradeToY(Addr a, MSI y);
        return CacheMemReq{ child: 0, addr: a, state: y };
    endfunction

    function CacheMemResp c2p_downgradeToY(Addr a, MSI y, Maybe#(CacheLine) d);
        return CacheMemResp{ child: 0, addr: a, state: y, data: d };
    endfunction

    function CacheMemReq p2c_downgradeToY(Addr a, MSI y);
        return CacheMemReq{ child: 0, addr: a, state: y };
    endfunction

    function CacheMemResp p2c_upgradeToY(Addr a, MSI y, Maybe#(CacheLine) d);
        return CacheMemResp{ child: 0, addr: a, state: y, data: d };
    endfunction

    function Action getResp( MemResp data );
        return (action
			let resp <- cache.resp;
			if(resp == data) begin
				// correct
                $fwrite(stderr, "Correct : got response %d\n", resp);
			end
			else begin
				// no match!
				$fwrite(stderr, "ERROR : got response %d != expected response %d\n", resp, data);
			end
		endaction);
    endfunction

    function Action reqLd( Addr a, MemReqID rid );
        return (action
			cache.req( MemReq{ addr: a, data: ?, op: Ld, rid: rid } );
		endaction);
    endfunction

    function Action reqSt( Addr a, Data d, MemReqID rid );
        return (action
			cache.req( MemReq{ addr: a, data: d, op: St, rid: rid } );
		endaction);
    endfunction

    function Action dequeue( CacheMemMessage m );
        return (action
			let incoming = c2p.first;
			case( m ) matches
				tagged Req .req: begin
					// waiting for a upgrade request
					// if we find a response or a wrong request, there was a problem
					case( incoming ) matches
						tagged Req .ireq: begin
							if( req.child == ireq.child && 
								req.state == ireq.state &&
								getLineAddr(req.addr) == getLineAddr(ireq.addr) ) begin
								// match
								c2p.deq;
							end else begin
								// mismatch
								$fwrite(stderr, "ERROR : incoming request does not match expeted request\n");
								$fwrite(stderr, "    expected: ", fshow(req), "\n");
								$fwrite(stderr, "    incoming: ", fshow(ireq), "\n");
								$finish;
							end
						end
						tagged Resp .iresp: begin
							$fwrite(stderr, "ERROR : expected incoming request, found incoming response\n");
							$finish;
						end
					endcase
				end
				tagged Resp .resp: begin
					// waiting for an downgrade response
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
								c2p.deq;
							end else begin
								// mismatch
								$fwrite(stderr, "ERROR : incoming response does not match expeted response\n");
								$fwrite(stderr, "    expected: ", fshow(resp), "\n");
								$fwrite(stderr, "    incoming: ", fshow(iresp), "\n");
								$finish;
							end
						end
					endcase
				end
			endcase
		endaction);
    endfunction


    // This uses StmtFSM to create an FSM for testing
    // See the bluespec reference guide for more info
    Stmt load_mini_tests = (seq
		$display("Load mini test 1: load miss");
		$display("  Requesting load to cache");
		reqLd( address(0,0,1), 0 );
		$display("  Looking for upgrade to S request to main memory");
		dequeue( tagged Req c2p_upgradeToY( address(0,0,0), S ) );
		$display("  Found upgrade to S request, sending upgrade to S response");
		p2c.enq_resp( p2c_upgradeToY( address(0,0,0), S, tagged Valid unpack({0, 32'd20, 32'd10, 32'd0}) ) );
		$display("  Looking for response for load");
		getResp(10);
		$display("  Found response, test passed\n");

		$display("Load mini test 2: load hit");
		$display("  Requesting load to cache");
		reqLd( address(0,0,2), 1 );
		$display("  Looking for response for load");
		getResp(20);
		$display("  Found response, test passed\n");
	endseq);

    Stmt store_mini_tests = (seq
		$display("Store mini test 1: store miss (S -> M)");
		$display("  Requesting store to cache");
		reqSt( address(0,0,3), 300, 2 );
		$display("  Looking for upgrade to M request to main memory");
		dequeue( tagged Req c2p_upgradeToY( address(0,0,0), M ) );
		$display("  Found upgrade to M request, sending upgrade to M response");
		p2c.enq_resp( p2c_upgradeToY( address(0,0,0), M, Invalid ) );
		delay(10); // wait for store to perform
		$display("  Sending downgrade to I request to check data");
		p2c.enq_req( p2c_downgradeToY( address(0,0,0), I ) );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY( address(0,0,0), I, tagged Valid unpack({0, 32'd300, 32'd20, 32'd10, 32'd0}) ) );
		$display("  Found correct data, test passed\n");

		// assuming 64B = 16 word cache line
		$display("Store mini test 2: store miss (I -> M)");
		$display("  Requesting store to cache");
		reqSt( address(0,0,14), 400, 3 );
		$display("  Looking for upgrade to M request to main memory");
		dequeue( tagged Req c2p_upgradeToY( address(0,0,0), M ) );
		$display("  Found upgrade to M request, sending upgrade to M response");
		p2c.enq_resp( p2c_upgradeToY( address(0,0,0), M, tagged Valid unpack({32'd15, 32'd14, 32'd13, 0}) ) );
		$display("  Data will be checked in the next test\n");

		$display("Store mini test 3: store hit");
		$display("  Requesting store to cache");
		reqSt( address(0,0,13), 300, 4 );
		delay(10); // wait for store to perform
		$display("  Sending downgrade to I request to check data");
		p2c.enq_req( p2c_downgradeToY( address(0,0,0), I ) );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY(address(0,0,0), I, tagged Valid unpack({32'd15, 32'd400, 32'd300, 0})) );
		$display("  Data matches, test passed\n");
	endseq);

	Stmt downgrade_mini_tests = (seq
		$display("Downgrade mini test 4: downgrade req interleaved with upgrade req");
		$display("  Requesting load to cache");
		reqLd(address(0,1,0), 5);
		$display("  Looking for upgrade to S request to main memory");
		dequeue( tagged Req c2p_upgradeToY( address(0,1,0), S ) );
		$display("  Found upgrade to S request, sending upgrade to S response");
		p2c.enq_resp( p2c_upgradeToY( address(0,1,0), S, tagged Valid unpack({0, 32'd999}) ) );
		$display("  Looking for response for load");
		getResp(999);

		$display("  Found correct data, requesting store to cache");
		reqSt(address(0,1,1), 111, 6);
		$display("  Sending dwongrade to I request to cache");
		p2c.enq_req( p2c_downgradeToY( address(0,1,0), I ) );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY(address(0,1,0), I, Invalid) );
		$display("  Found downgrade to I respondse, looking for upgrade request");
		dequeue( tagged Req c2p_upgradeToY( address(0,1,0), M ) );
		$display("  Found upgrade to M request, sending upgrade to M response");
		p2c.enq_resp( p2c_upgradeToY( address(0,1,0), M, tagged Valid unpack({0, 32'd666, 32'd777, 32'd888}) ) );
		delay(10); // wait for store to perform

		$display("  Sending downgrade to S request to check data");
		p2c.enq_req( p2c_downgradeToY( address(0,1,0), S ) );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY(address(0,1,0), S, tagged Valid unpack({0, 32'd666, 32'd111, 32'd888})) );
		$display("  Data matches, test passed\n");
	endseq);

    Stmt replace_mini_tests = (seq
		$display("Replacement mini test 5: replacement and rule 7");
		$display("  Requesting load to cache line (0,2)");
		reqLd( address(0,2,0), 7 );
		$display("  Looking for upgrade request");
		dequeue( tagged Req c2p_upgradeToY( address(0,2,0), S ) );
		$display("  Found upgrade to S request, sending upgrade to S response");
		p2c.enq_resp( p2c_upgradeToY( address(0,2,0), S, tagged Valid unpack({0, 32'd77}) ) );
		$display("  Looking for response for load");
		getResp( 77 );

		$display("  Found correct data, requesting store to cache line (1,2), evicting (0,2) first");
		reqSt( address(1,2,1), 88, 8 );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY( address(0,2,0), I, Invalid ) );
		$display("  Cache send downgrade to I response, sending downgrade request to cache again, cache should ignore it");
		p2c.enq_req( p2c_downgradeToY( address(0,2,0), I ) );
		$display("  Make sure the cache didn't send another response");
		delay(10);
		action
			if( c2p.hasResp == True ) begin
				$fwrite(stderr, "ERROR : Cache sent another response\n");
				$finish;
			end
		endaction
		$display("  No downgrade response sent, looking for upgrade request");
		dequeue( tagged Req c2p_upgradeToY( address(1,2,0), M ) );
		$display("  Found upgrade to M request, sending upgrade to M response");
		p2c.enq_resp( p2c_upgradeToY( address(1,2,0), M, tagged Valid unpack({0, 32'd66}) ) );
		
		$display("  Requesting store to cache line (2,2), evicting (1,2) first");
		reqLd( address(2,2,2), 9 );
		$display("  Looking for downgrade response");
		dequeue( tagged Resp c2p_downgradeToY( address(1,2,0), I, tagged Valid unpack({0, 32'd88, 32'd66}) ) );
		$display("  Cache send downgrade to I response, sending downgrade request to cache again, cache should ignore it");
		p2c.enq_req( p2c_downgradeToY( address(1,2,0), I ) );
		$display("  Make sure the cache didn't send another response");
		delay(10);
		action
			if( c2p.hasResp == True ) begin
				$fwrite(stderr, "ERROR : Cache sent another response\n");
				$finish;
			end
		endaction
		$display("  No downgrade response sent, looking for upgrade request");
		dequeue( tagged Req c2p_upgradeToY( address(2,2,0), S ) );
		$display("  Found upgrade to S request, send upgrade to S response to cache");
		p2c.enq_resp( p2c_upgradeToY( address(2,2,0), S, tagged Valid unpack({0, 32'd99, 32'd0, 32'd0}) ) );
		$display("  Looking for response for load");
		getResp(99);
		$display("  Found correct data, test passed\n");
	endseq);

    Stmt test = (seq
		load_mini_tests;
		store_mini_tests;
		downgrade_mini_tests;
		replace_mini_tests;
		$display("All tests PASSED");
		$finish(0);
	endseq);
    mkAutoFSM(test);

    // Timeout FSM
    // If the test doesn't finish in 10000 cycles, this prints an error
    Stmt timeout = (seq
		delay(10000);
		(action
			$fwrite(stderr, "ERROR: Testbench stalled.\n");
		endaction);
		$finish(1);
	endseq);
    mkAutoFSM(timeout);
endmodule
