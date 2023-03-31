import ProcTypes::*;
import Types::*;
import MemTypes::*;
import CacheTypes::*;
import RefTypes::*;
import Vector::*;
import FShow::*;
import Ehr::*;
import Fifo::*;
import GetPut::*;
import RevertingVirtualReg::*;
import RefTSOLSQ::*;

(* synthesize *)
module mkRefTSOMem(RefMem);
	// mem
	Reg#(Bit#(64))  mem <- mkReg(0);
	Reg#(Bool) initDone <- mkReg(False);
	
	// links
	Vector#(CoreNum, Ehr#(CoreNum, Maybe#(CacheLineAddr))) link <- replicateM(mkEhr(Invalid));
	
	// LSQs of mem ops: allow issue & commit of same op at one cycle
	Vector#(CoreNum, RefTSOLSQ#(TAdd#(MaxReqNum, StQSize))) reqQ = ?;
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		reqQ[i] <- mkRefTSOLSQ(fromInteger(i));
	end
	
	// EHRs for req
	Vector#(CoreNum, Ehr#(2, Maybe#(RefFetchReq)))   fetchEn <- replicateM(mkEhr(Invalid));
	Vector#(CoreNum, Ehr#(2, Maybe#(MemReq)))        issueEn <- replicateM(mkEhr(Invalid));
	Vector#(CoreNum, Ehr#(2, Maybe#(RefCommitReq))) commitEn <- replicateM(mkEhr(Invalid));
	
	// EHRs to record read/write set of each core in every cycle
	Vector#(CoreNum, Ehr#(2, Maybe#(CacheLineAddr))) ldAddr <- replicateM(mkEhr(Invalid));
	Vector#(CoreNum, Ehr#(2, Maybe#(CacheLineAddr))) stAddr <- replicateM(mkEhr(Invalid));

	// EHR for ordering: we process core 0 req --> core N req sequentially
	Vector#(TAdd#(CoreNum, 2), Reg#(Bool)) order <- replicateM(mkRevertingVirtualReg(True));

	// init mem
	rule doInit(!initDone);
		let ptr <- createMem;
		if(ptr == 0) begin
			$fwrite(stderr, "%0t: RefTSOMem: ERROR: fail to create memory\n", $time);
			$finish;
		end
		$display("%0t: RefTSOMem: allocate memory ptr = %h", $time, ptr);
		mem <= ptr;
		initDone <= True;
	endrule

	// do fetch
	rule doFetch(initDone && order[0]); // order: doFetch < doIssue
		for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
			if(fetchEn[i][1] matches tagged Valid .f) begin
				checkRefAddrOverflow(fromInteger(i), f.pc); // check addr overflow
				let inst <- readMemWord(mem, f.pc);
				if(inst == f.inst) begin
					// good
				end else begin
					$fwrite(stderr, "%0t: RefTSOMem: ERROR: core %d fetches ", $time, i, fshow(f), " \n");
					$fwrite(stderr, "inst should be %h\n", inst);
					$finish;
				end
			end
			// reset EHR
			fetchEn[i][1] <= Invalid;
		end
	endrule

	// do issue
	rule doIssue(initDone && order[1]); // order: doIssue < doCommit_0
		// order: doFetch < doIssue
		order[0] <= False;

		// real work starts
		for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
			if(issueEn[i][1] matches tagged Valid .r) begin
				if(r.op != Fence) begin
					checkRefAddrOverflow(fromInteger(i), r.addr); // check addr overflow
				end
				reqQ[i].insert(r); // insert to LSQ
			end
			// reset EHR
			issueEn[i][1] <= Invalid;
		end
	endrule

	// do commit: sequentially process commit req from core 0, 1, 2...
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		rule doCommit(initDone && order[i+2]); // order: doCommit_i < doCommit_(i+1) or doRWConflict
			// order: doIssue or doCommit_(i-1) < doCommit_i
			order[i+1] <= False;

			// real work starts
			if(commitEn[i][1] matches tagged Valid .c) begin
				if(c.req.op != Fence) begin
					checkRefAddrOverflow(fromInteger(i), c.req.addr); // check addr overflow
				end

				// try to remove the req from LSQ
				Maybe#(Data) bypassVal <- reqQ[i].remove(c);
					
				// check orig cache line value
				let req = c.req;
				let addr = getLineAddr(req.addr);
				if(!isValid(c.line)) begin
					// good: we don't check line value
				end
				else begin
					if(req.op == Fence) begin
						$fwrite(stderr, "%0t: RefTSOMem: ERROR: core %d commits ", $time, i, fshow(c), " \n");
						$fwrite(stderr, "%Fence req should not check cache line value, line should be Invalid\n");
						$finish;
					end
					let line <- readMemLine(mem, addr);
					if(fromMaybe(?, c.line) == line) begin
						// good: line match
					end
					else begin
						$fwrite(stderr, "%0t: RefTSOMem: ERROR: core %d commits ", $time, i, fshow(c), " \n");
						$fwrite(stderr, "the original cache line should be ", fshow(line), "\n");
						$finish;
					end
				end
				
				// execute req & check resp
				Maybe#(MemResp) resp = ?;
				let sel = getWordSelect(req.addr);
				case(req.op)
					Ld: begin
						if(isValid(bypassVal)) begin
							resp = bypassVal; // bypass from store
						end
						else begin
							let line <- readMemLine(mem, addr);
							resp = Valid (line[sel]);
							ldAddr[i][0] <= Valid (addr);
						end
					end
					Lr: begin
						let line <- readMemLine(mem, addr);
						resp = Valid (line[sel]);
						link[i][i] <= Valid (addr); // create link
						ldAddr[i][0] <= Valid (addr);
					end
					St: begin
						resp = Invalid;
						writeMemWord(mem, req.addr, req.data);
						stAddr[i][0] <= Valid (addr);
						// clear others' link
						for(Integer j = 0; j < valueOf(CoreNum); j = j+1) begin
							if(j != i &&& link[j][i] matches tagged Valid .a &&& a == addr) begin
								link[j][i] <= Invalid;
							end
						end
					end
					Sc: begin
						if(c.resp matches tagged Valid .x &&& x == scFail) begin
							// it is always fine to return fail for store-cond
							resp = Valid (zeroExtend(scFail));
						end
						else begin
							// we follow this model to determin succ or fail
							if(link[i][i] matches tagged Valid .a &&& a == addr) begin
								resp = Valid (zeroExtend(scSucc));
								writeMemWord(mem, req.addr, req.data);
								stAddr[i][0] <= Valid (addr);
								// clear others' link
								for(Integer j = 0; j < valueOf(CoreNum); j = j+1) begin
									if(j != i &&& link[j][i] matches tagged Valid .a &&& a == addr) begin
										link[j][i] <= Invalid;
									end
								end
							end
							else begin
								// actually this branch is already an error
								resp = Valid (zeroExtend(scFail));
							end
						end
						link[i][i] <= Invalid; // clear link
					end
					Fence: begin
						resp = Invalid;
					end
				endcase
				if(resp == c.resp) begin
					// good
				end
				else begin
					$fwrite(stderr, "%0t: RefTSOMem: ERROR: core %d commits ", $time, i, fshow(c), " \n");
					$fwrite(stderr, "resp should be ", fshow(resp), "\n");
					$finish;
				end
			end
		endrule
	end

	// check r/w conflicts
	rule doRWConflict(initDone);
		// order: doCommit_(CoreNum-1) < doRWConflict
		order[valueOf(CoreNum) + 1] <= False;

		// real work starts
		for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
			for(Integer j = i+1; j < valueOf(CoreNum); j = j+1) begin
				let ld_i = validValue(ldAddr[i][1]);
				let st_i = validValue(stAddr[i][1]);
				let ld_j = validValue(ldAddr[j][1]);
				let st_j = validValue(stAddr[j][1]);
				if(isValid(ldAddr[i][1]) && isValid(stAddr[j][1]) && ld_i == st_j) begin
					$fwrite(stderr, "%0t: RefTSOMem: ERROR: commits conflict\n", $time);
					$fwrite(stderr, "core %d commits ", i, fshow(validValue(commitEn[i][1])), ", reads line %h\n", ld_i);
					$fwrite(stderr, "core %d commits ", j, fshow(validValue(commitEn[j][1])), ", writes line %h\n", st_j);
					$finish;
				end
				if(isValid(stAddr[i][1]) && isValid(stAddr[j][1]) && st_i == st_j) begin 
					$fwrite(stderr, "%0t: RefTSOMem: ERROR: commits conflict\n", $time);
					$fwrite(stderr, "core %d commits ", i, fshow(validValue(commitEn[i][1])), ", writes line %h\n", st_i);
					$fwrite(stderr, "core %d commits ", j, fshow(validValue(commitEn[j][1])), ", writes line %h\n", st_j);
				end
				if(isValid(stAddr[i][1]) && isValid(ldAddr[j][1]) && st_i == ld_j) begin 
					$fwrite(stderr, "%0t: RefTSOMem: ERROR: commits conflict\n", $time);
					$fwrite(stderr, "core %d commits ", i, fshow(validValue(commitEn[i][1])), ", writes line %h\n", st_i);
					$fwrite(stderr, "core %d commits ", j, fshow(validValue(commitEn[j][1])), ", reads line %h\n", ld_j);
				end
			end
		end
		// reset EHRs
		for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
			ldAddr[i][1] <= Invalid;
			stAddr[i][1] <= Invalid;
			commitEn[i][1] <= Invalid;
		end
	endrule

	Vector#(CoreNum, RefIMem) iVec = ?;
	Vector#(CoreNum, RefDMem) dVec = ?;
	
	for(Integer i = 0; i < valueOf(CoreNum); i = i+1) begin
		iVec[i] = (interface RefIMem;
			method Action fetch(Addr pc, Instruction inst) if(initDone);
				fetchEn[i][0] <= Valid (RefFetchReq {
					pc: pc,
					inst: inst
				});
			endmethod
		endinterface);

		dVec[i] = (interface RefDMem;
			method Action issue(MemReq req) if(initDone);
				issueEn[i][0] <= Valid (req);
			endmethod

			method Action commit(MemReq req, Maybe#(CacheLine) line, Maybe#(MemResp) resp) if(initDone);
				commitEn[i][0] <= Valid (RefCommitReq {
					req: req,
					line: line,
					resp: resp
				});
			endmethod
		endinterface);
	end

	interface iMem = iVec;
	interface dMem = dVec;
endmodule
