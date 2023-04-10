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
import CacheTypes::*;
import WideMemInit::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MemReqIDGen::*;
import RefTypes::*;
import MessageFifo::*;

typedef struct {
    Addr pc;
    Addr predPc;
    Bool ieCanary;
    Bool idCanary;
} Fetch2Decode deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    Bool ieCanary;
    Bool idCanary;
    DecodedInst dInst;
} Decode2RegisterFetch deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
    Bool ieCanary;
    Bool idCanary;
} Fetch2Execute deriving (Bits, Eq);

typedef struct {
    Addr pc;
    Addr predPc;
    Maybe#(ExecInst) eInst;
} Execute2WriteBack deriving (Bits, Eq);

typedef struct {
	Addr pc;
	Addr nextPc;
} Redirect deriving (Bits, Eq);

module mkCore(
    CoreID id,
    WideMem iMem,
    RefDMem refDMem,
    Core ifc
);
    Ehr#(2, Addr)                   pcReg <- mkEhr(?);
    RFile                              rf <- mkRFile;
    CsrFile                          csrf <- mkCsrFile(id);
    ICache                         iCache <- mkICache(iMem);
    MessageFifo#(2)             toParentQ <- mkMessageFifo;
    MessageFifo#(2)           fromParentQ <- mkMessageFifo;
    DCache                         dCache <- mkDCache(id, toMessageGet(fromParentQ), toMessagePut(toParentQ), refDMem);
    MemReqIDGen               memReqIDGen <- mkMemReqIDGen;
    Scoreboard#(6)                     sb <- mkCFScoreboard;
    Btb#(6)                           btb <- mkBtb;
    Bht#(8)                           bht <- mkBht;
    Reg#(Bool)                   exeCanary <- mkReg(False);
    Reg#(Bool)                   decCanary <- mkReg(False);
	Ehr#(2, Maybe#(Redirect)) exeRedirect <- mkEhr(Invalid);
	Ehr#(2, Maybe#(Redirect)) decRedirect <- mkEhr(Invalid);
	Fifo#(2, Fetch2Decode)            i2d <- mkCFFifo;
	Fifo#(2, Decode2RegisterFetch)    d2r <- mkCFFifo;
	Fifo#(2, Fetch2Execute)           r2e <- mkCFFifo;
	Fifo#(2, Execute2WriteBack)       e2m <- mkCFFifo;
	Fifo#(2, Execute2WriteBack)       m2w <- mkCFFifo;


    rule doFetch(csrf.started);
		iCache.req(pcReg[0]);
        let predPc = btb.predPc(pcReg[0]);
        i2d.enq(Fetch2Decode {
            pc: pcReg[0],
            predPc: predPc,
            ieCanary: exeCanary,
            idCanary: decCanary
        });
        pcReg[0] <= predPc;
    endrule


    rule doDecode(csrf.started);
        let dMsg = i2d.first;
        i2d.deq;
        let inst <- iCache.resp();
        if (dMsg.ieCanary == exeCanary && dMsg.idCanary == decCanary) begin
            let dInst = decode(inst);
            if (dInst.iType == Br || dInst.iType == J) begin
                let bht_ppc = dMsg.pc + 4;
                if (bht.predict(dMsg.pc) || dInst.iType == J) begin
                    bht_ppc = dMsg.pc + fromMaybe(?, dInst.imm);
                end
                if (bht_ppc != dMsg.predPc) begin
                    dMsg.predPc = bht_ppc;
                    decRedirect[0] <= Valid (Redirect {
                        pc: dMsg.pc,
                        nextPc: dMsg.predPc
                    });
                end
            end
            d2r.enq(Decode2RegisterFetch {
                pc:       dMsg.pc,
                predPc:   dMsg.predPc,
                ieCanary: dMsg.ieCanary,
                idCanary: dMsg.idCanary,
                dInst:    dInst
            });
        end
	endrule

    rule doRegisterFetch(csrf.started);
        let dMsg = d2r.first;
        let dInst = dMsg.dInst;
		if(!sb.search1(dInst.src1) && !sb.search2(dInst.src2)) begin
            d2r.deq;
            Data rVal1 = rf.rd1(fromMaybe(?, dInst.src1));
            Data rVal2 = rf.rd2(fromMaybe(?, dInst.src2));
            Data csrVal = csrf.rd(fromMaybe(?, dInst.csr));
            Fetch2Execute eMsg = Fetch2Execute {
                pc:       dMsg.pc,
                predPc:   dMsg.predPc,
                dInst:    dInst,
                rVal1:    rVal1,
                rVal2:    rVal2,
                csrVal:   csrVal,
                ieCanary: dMsg.ieCanary,
                idCanary: dMsg.idCanary
            };
            r2e.enq(eMsg);
			sb.insert(dInst.dst);
		end
    endrule

    rule doExecute(csrf.started);
        let dMsg = r2e.first;
		r2e.deq;
        Maybe#(ExecInst) eInstValid;
		if(dMsg.ieCanary != exeCanary) begin
            eInstValid = Invalid;
		end
		else begin
			let eInst = exec(
                dMsg.dInst,
                dMsg.rVal1,
                dMsg.rVal2,
                dMsg.pc,
                dMsg.predPc,
                dMsg.csrVal
            );
            eInstValid = Valid(eInst);
            if(eInst.mispredict) begin
                exeRedirect[0] <= Valid (Redirect {
                    pc:     dMsg.pc,
                    nextPc: eInst.addr
                });
            end
            if (eInst.iType == Br) begin
                bht.train(dMsg.pc, eInst.brTaken);
            end
        end

        let eMsg = Execute2WriteBack {
            pc: dMsg.pc,
            predPc: dMsg.predPc,
            eInst: eInstValid
        };
        e2m.enq(eMsg);

    endrule

    rule doMemory(csrf.started);
        let dMsg = e2m.first;
        e2m.deq;
        if (isValid(dMsg.eInst)) begin
            let eInst = fromMaybe(?, dMsg.eInst);
            case (eInst.iType)
                Ld: begin
                    let rid <- memReqIDGen.getID;
                    let req = MemReq { op: Ld, addr: eInst.addr, data: ?, rid: rid };
                    dCache.req(req);
                end
                St: begin
                    let rid <- memReqIDGen.getID;
                    let req = MemReq { op: St, addr: eInst.addr, data: eInst.data, rid: rid };
                    dCache.req(req);
                end
                Lr: begin
                    let rid <- memReqIDGen.getID;
                    let req = MemReq { op: Lr, addr: eInst.addr, data: ?, rid: rid };
                    dCache.req(req);
                end
                Sc: begin
                    let rid <- memReqIDGen.getID;
                    let req = MemReq { op: Sc, addr: eInst.addr, data: eInst.data, rid: rid };
                    dCache.req(req);
                end
                Fence: begin
                    let rid <- memReqIDGen.getID;
                    let req = MemReq { op: Fence, addr: ?, data: ?, rid: rid };
                    dCache.req(req);
                end
                default: begin
                end
            endcase
        end
        m2w.enq(dMsg);
    endrule

    rule doWriteBack(csrf.started);
        let dMsg = m2w.first;
        m2w.deq;
        if (isValid(dMsg.eInst)) begin
            let eInst = fromMaybe(?, dMsg.eInst);
            if(eInst.iType == Ld || eInst.iType == Lr || eInst.iType == Sc) begin
                eInst.data <- dCache.resp();
            end

            // check unsupported instruction at commit time. Exiting
            if(eInst.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", dMsg.pc);
                $finish;
            end
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?, eInst.dst), eInst.data);
            end
		    let willPrint = fromMaybe(?, eInst.csr) != csrMtohost || (fromMaybe(?, eInst.csr) == csrMtohost && id == 0);
		    csrf.wr(eInst.iType == Csrw && willPrint ? eInst.csr : Invalid, eInst.data);
        end
        sb.remove;
	endrule

	(* fire_when_enabled *)
	(* no_implicit_conditions *)
	rule cononicalizeRedirect(csrf.started);
		if(exeRedirect[1] matches tagged Valid .r) begin
			pcReg[1] <= r.nextPc;
			exeCanary <= !exeCanary;
			btb.update(r.pc, r.nextPc);
		end
        else if (decRedirect[1] matches tagged Valid .r) begin
			pcReg[1] <= r.nextPc;
			decCanary <= !decCanary;
			btb.update(r.pc, r.nextPc);
        end
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
        csrf.start();
        pcReg[0] <= startpc;
    endmethod
endmodule
