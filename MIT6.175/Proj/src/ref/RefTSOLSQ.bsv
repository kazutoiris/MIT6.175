import Types::*;
import MemTypes::*;
import CacheTypes::*;
import RefTypes::*;
import Vector::*;
import Ehr::*;
import FShow::*;

// here we assume rid is a unique ID for each mem req
// this only holds when DEBUG is defined

import "BDPI" function ActionValue#(Bit#(64)) lsq_create(Bit#(32) size);
import "BDPI" function ActionValue#(Bit#(8)) lsq_insert(Bit#(64) ptr, Bit#(8) op, Data addr, Data data, Data rid);
import "BDPI" function ActionValue#(Bit#(64)) lsq_remove(Bit#(64) ptr, Bit#(8) op, Data addr, Data data, Data rid);

// insert < commit
interface RefTSOLSQ#(numeric type n);
	method Action insert(MemReq r); // return False if insert fail
	method ActionValue#(Maybe#(Data)) remove(RefCommitReq c); // if c.req is load and hit on store, return bypassed value
endinterface

typedef TAdd#(MaxReqNum, StQSize) LSQSize;

module mkRefTSOLSQ#(CoreID cid)(RefTSOLSQ#(n));
	Reg#(Bit#(64)) lsq <- mkReg(0);
	Reg#(Bool) initDone <- mkReg(False);

	rule doInit(!initDone);
		let p <- lsq_create(fromInteger(valueOf(n)));
		if(p == 0) begin
			$fwrite(stderr, "%0t: RefTSOLSQ: core %d creation fail\n", $time, cid);
			$finish;
		end
		else begin
			lsq <= p;
			initDone <= True;
		end
	endrule

	method Action insert(MemReq r) if(initDone);
		let ret <- lsq_insert(lsq, zeroExtend(pack(r.op)), r.addr, r.data, zeroExtend(r.rid));
		if(ret == 0) begin
			$fwrite(stderr, "%0t: RefTSOLSQ: ERROR: core %d issues ", $time, cid, fshow(r), " \n");
			$fwrite(stderr, "there are already %d pending req\n", valueOf(n));
			$finish;
		end
	endmethod

	method ActionValue#(Maybe#(Data)) remove(RefCommitReq c) if(initDone);
		let r = c.req;
		let ret <- lsq_remove(lsq, zeroExtend(pack(r.op)), r.addr, r.data, zeroExtend(r.rid));
		// check high 8 bits for removal correctness
		Bit#(8) err = truncateLSB(ret);
		if(err > 0) begin
			$fwrite(stderr, "%0t: RefTSOLSQ: ERROR: core %d commits ", $time, cid, fshow(c), " \n");
			case(err)
				1: $fwrite(stderr, "no such req has been issued\n");
				2: begin
					if(r.op == Ld) begin
						$fwrite(stderr, "there is older non-St req, should not commit this Ld req\n");
					end
					else begin
						$fwrite(stderr, "there is older req, should not commit this non-Ld req\n");
					end
				end
				default: $fwrite(stderr, "internal error: unknown failure code %d\n", err);
			endcase
			$finish;
		end
		// return bypass
		return (ret[32] == 1) ? (Valid (ret[31:0])) : Invalid;
	endmethod
endmodule
