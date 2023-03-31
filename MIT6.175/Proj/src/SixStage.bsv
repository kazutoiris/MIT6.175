import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import Scoreboard::*;
import Bht::*;
import GetPut::*;
import ClientServer::*;
import Memory::*;
import ICache::*;
import DCache::*;
import DCacheStQ::*;
import DCacheLHUSM::*;
import CacheTypes::*;
import WideMemInit::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MemReqIDGen::*;
import RefTypes::*;
import MessageFifo::*;


// Data structure for Instruction Fetch to Decode stage
typedef struct {
    Addr pc;
    Addr predPc;
    Bool ieEp;
    Bool idEp;
} Fetch2Decode deriving (Bits, Eq);

// Data structure for Decode to Register Fetch stage
typedef struct {
    Addr pc;
    Addr predPc;
    Bool ieEp;
    Bool idEp;
    DecodedInst dInst;
} Decode2RegisterFetch deriving (Bits, Eq);

// Data structure for Register Fetch to Execute stage
typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
    Bool ieEp;
    Bool idEp;
} Fetch2Execute deriving (Bits, Eq);

// Data structure for Execute to Write Back stage
typedef struct {
    Addr pc;
    Addr predPc;
    Maybe#(ExecInst) eInst;
} Execute2WriteBack deriving (Bits, Eq);

// redirect msg from Execute stage
typedef struct {
	Addr pc;
	Addr nextPc;
} Redirect deriving (Bits, Eq);


//(* synthesize *)
module mkCore(
                CoreID id,
                WideMem iMem,
                RefDMem refDMem,
                Core ifc
);
    Ehr#(2, Addr) pcReg <- mkEhr(?);
    RFile            rf <- mkRFile;
    CsrFile        csrf <- mkCsrFile(id);


	// Memory initialization
    ICache iCache <- mkICache(iMem);

    MessageFifo#(2) toParentQ <- mkMessageFifo;
    MessageFifo#(2) fromParentQ <- mkMessageFifo;
 `ifdef LHUSM
    DCache dCache <- mkDCacheLHUSM(
`elsif STQ
    DCache dCache <- mkDCacheStQ(
`else
    DCache dCache <- mkDCache(
`endif
    id,
    toMessageGet(fromParentQ),
    toMessagePut(toParentQ),
    refDMem
    );

  
    // mem req id
    MemReqIDGen memReqIDGen <- mkMemReqIDGen;
    
    // Branch prediction structures 
    Scoreboard#(6)   sb <- mkCFScoreboard;
    Btb#(6)         btb <- mkBtb; // 64-entry BTB
    Bht#(8)         bht <- mkBht; // 256-entry BHT

	// global epoch for redirection from Execute stage
    Reg#(Bool) exeEpoch <- mkReg(False);
    Reg#(Bool) decEpoch <- mkReg(False);

	// EHR for redirection
	Ehr#(2, Maybe#(Redirect)) exeRedirect <- mkEhr(Invalid);
	Ehr#(2, Maybe#(Redirect)) decRedirect <- mkEhr(Invalid);

	// FIFO between six stages
	Fifo#(2, Fetch2Decode) if2d <- mkCFFifo;
	Fifo#(2, Decode2RegisterFetch) d2rf <- mkCFFifo;
	Fifo#(2, Fetch2Execute) rf2e <- mkCFFifo;
	Fifo#(2, Execute2WriteBack) e2m <- mkCFFifo;
	Fifo#(2, Execute2WriteBack) m2wb <- mkCFFifo;


    rule doInstructionFetch(csrf.started);
		
        // fetch
		iCache.req(pcReg[0]);
		
        // make pc prediction
        Addr predPc = btb.predPc(pcReg[0]);

        // enque data into fifo
        Fetch2Decode eMsg = Fetch2Decode {
            pc: pcReg[0],
            predPc: predPc,
            ieEp: exeEpoch,
            idEp: decEpoch
        };
        if2d.enq(eMsg);
        
        // update pc
        pcReg[0] <= predPc;
        
        $display("Fetch: PC = %x, pred PC = %x", pcReg[0], predPc);

    endrule
   
    
    rule doDecode(csrf.started);

        // deque from fetch
        let dMsg = if2d.first;
        if2d.deq;

        // get instruction
        $display("Getting response from instruction fetch");
        let inst <- iCache.resp();
        
        // check for correct epochs
        if (dMsg.ieEp == exeEpoch && dMsg.idEp == decEpoch) begin
            
            // decode instruction
            DecodedInst dInst = decode(inst);
            
            $display("Decoded: PC = %x, Inst = %x, full = ", dMsg.pc, inst, 
                    showInst(inst));

            // check BHT for branch instructions, redirect pc if necessary
            if (dInst.iType == Br || dInst.iType == J) begin
                Addr bht_ppc;
                if (bht.predict(dMsg.pc) || dInst.iType == J)
                    bht_ppc = dMsg.pc + fromMaybe(?, dInst.imm);
                else bht_ppc = dMsg.pc + 4;
                if (bht_ppc != dMsg.predPc) begin
                    
                    $display("BHT Redirect: PC = %x, old ppc = %x, new ppc = ", 
                        dMsg.pc, dMsg.predPc, bht_ppc);
                    dMsg.predPc = bht_ppc;
                    decRedirect[0] <= Valid (Redirect {pc: dMsg.pc, 
                        nextPc: dMsg.predPc});

                end
            end
            
            // enque decoded instruction
            Decode2RegisterFetch eMsg = Decode2RegisterFetch {
                pc: dMsg.pc,
                predPc: dMsg.predPc,
                ieEp: dMsg.ieEp,
                idEp: dMsg.idEp,
                dInst: dInst
            };
                
            // enq
            d2rf.enq(eMsg);
        end

	endrule

    rule doRegisterFetch(csrf.started);
       
        // get data from decode
        let dMsg = d2rf.first;
        let dInst = dMsg.dInst;
                    
        // search scoreboard to determine stall
		if(!sb.search1(dInst.src1) && !sb.search2(dInst.src2)) begin
            
            // deque from decode
            d2rf.deq;
            
            // read register file
            Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
            Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
            Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));
            
            // data to enq to FIFO
            Fetch2Execute eMsg = Fetch2Execute {
                pc: dMsg.pc,
                predPc: dMsg.predPc,
                dInst: dInst,
                rVal1: rVal1,
                rVal2: rVal2,
                csrVal: csrVal,
                ieEp: dMsg.ieEp,
                idEp: dMsg.idEp
            };

            // enq & update sb
            rf2e.enq(eMsg);
			sb.insert(dInst.dst);
			$display("Fetch at PC = %x success", dMsg.pc);
		end
        else begin
			$display("Register Fetch Stalled: PC = %x", dMsg.pc);
		end

    endrule
	
    rule doExecute(csrf.started);
		
        // deque
        let dMsg = rf2e.first;
		rf2e.deq;

        // Executed instruction
        Maybe#(ExecInst) eInst;

        // check message epoch        
		if(dMsg.ieEp != exeEpoch) begin
			
            // kill wrong-path inst, enque instruction as invalid
			$display("Execute: Kill instruction at PC = %x", dMsg.pc);
            eInst = Invalid;
		end
		else begin
			// execute
			ExecInst eInst_calc = exec(dMsg.dInst, dMsg.rVal1, dMsg.rVal2, dMsg.pc, 
                                  dMsg.predPc, dMsg.csrVal);
            eInst = Valid(eInst_calc);
           	$display("Execute: Exec instruction at PC = %x", dMsg.pc);
            
            // check mispred
            if(eInst_calc.mispredict) begin
                $display("Execute finds misprediction: PC = %x", dMsg.pc);
                exeRedirect[0] <= Valid (Redirect {
                    pc: dMsg.pc,
                    nextPc: eInst_calc.addr
                });
            end
            // train BHT
            if (eInst_calc.iType == Br) begin
                $display("Training BHT: PC = %x, Exe PC = %x, br taken = ", 
                    dMsg.pc, eInst_calc.addr, eInst_calc.brTaken);
                bht.train(dMsg.pc, eInst_calc.brTaken);
            end
        end 
        
        // data to enq to FIFO
        Execute2WriteBack eMsg = Execute2WriteBack {
            pc: dMsg.pc,
            predPc: dMsg.predPc,
            eInst: eInst
        };
        e2m.enq(eMsg);

    endrule

    rule doMemory(csrf.started);

        $display("Memory");
        
        // deque data
        let dMsg = e2m.first;
        e2m.deq;

        // check to ensure valid executed instruction
        if (isValid(dMsg.eInst)) begin
            
            // get executed instruction
            let eInst = fromMaybe(?, dMsg.eInst);

            // memory requests
            if(eInst.iType == Ld) begin
                let rid <- memReqIDGen.getID;
                dCache.req(MemReq{op: Ld, addr: eInst.addr, data: ?, rid: rid});
                $display("Memory: At pc %x, loading %x", dMsg.pc, eInst.addr);
            end else if(eInst.iType == St) begin
                let rid <- memReqIDGen.getID;
                dCache.req(MemReq{op: St, addr: eInst.addr, data: eInst.data, rid: rid});
                $display("Memory: At pc %x, storing %x", dMsg.pc, eInst.addr);
            end else if(eInst.iType == Lr) begin
                let rid <- memReqIDGen.getID;
                dCache.req(MemReq{op: Lr, addr: eInst.addr, data: ?, rid: rid});
                $display("Memory: At pc %x, LR %x", dMsg.pc, eInst.addr);
            end else if(eInst.iType == Sc) begin
                let rid <- memReqIDGen.getID;
                dCache.req(MemReq{op: Sc, addr: eInst.addr, data: eInst.data, rid: rid});
                $display("Memory: At pc %x, SR %x", dMsg.pc, eInst.addr);
            end else if(eInst.iType == Fence) begin
                let rid <- memReqIDGen.getID;
                dCache.req(MemReq{op: Fence, addr: ?, data: ?, rid: rid});
                $display("Memory: at pc %x, Fence issued", dMsg.pc);
            end else begin
                $display("Memory: no memory op.");
            end
        end

        // enque data
        m2wb.enq(dMsg);

    endrule

    rule doWriteBack(csrf.started);

        $display("Writeback");
        
        // deque data
        let dMsg = m2wb.first;
        m2wb.deq;

        // check to ensure valid executed instruction
        if (isValid(dMsg.eInst)) begin
            
            // get executed instruction
            let eInst = fromMaybe(?, dMsg.eInst);

            // get memory response if applicable
            if(eInst.iType == Ld) begin
                eInst.data <- dCache.resp();
            end else if(eInst.iType == Lr) begin
                eInst.data <- dCache.resp();
            end else if(eInst.iType == Sc) begin
                eInst.data <- dCache.resp();
            end
            
            // check unsupported instruction at commit time. Exiting
            if(eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", dMsg.pc);
                $finish;
            end
            
            // write back to reg file
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
            end
            csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
        end
            
        // remove from scoreboard
        sb.remove;
        
	endrule

	(* fire_when_enabled *)
	(* no_implicit_conditions *)
	rule cononicalizeRedirect(csrf.started);
		if(exeRedirect[1] matches tagged Valid .r) begin
			
            // fix mispred
			pcReg[1] <= r.nextPc;
			exeEpoch <= !exeEpoch; // flip epoch
			btb.update(r.pc, r.nextPc); // train BTB
			$display("Fetch: Mispredict, redirected by Execute");
		end
        else if (decRedirect[1] matches tagged Valid .r) begin

            // fix mispred
			pcReg[1] <= r.nextPc;
			decEpoch <= !decEpoch; // flip epoch
			btb.update(r.pc, r.nextPc); // train BTB
			$display("Fetch: Mispredict, redirected by Decode");
        end

		// reset EHRs
		exeRedirect[1] <= Invalid;
		decRedirect[1] <= Invalid;
	endrule

    interface MessageGet toParent = toMessageGet(toParentQ);
    interface MessagePut fromParent = toMessagePut(fromParentQ);

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Bool cpuToHostValid = csrf.cpuToHostValid;

    method Action hostToCpu(Bit#(32) startpc) if ( !csrf.started );
        csrf.start(); // only 1 core, id = 0
        pcReg[0] <= startpc;
    endmethod
endmodule

