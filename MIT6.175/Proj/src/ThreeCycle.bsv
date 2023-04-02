import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import ICache::*;
import DCache::*;
import DCacheStQ::*;
import DCacheLHUSM::*;
import MemReqIDGen::*;
import CacheTypes::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MessageFifo::*;
import RefTypes::*;


typedef enum {
    Fetch,
    Execute,
    Commit
} Stage deriving(Bits, Eq, FShow);

module mkCore#(CoreID id)(
    WideMem iMem,
    RefDMem refDMem,
    Core ifc
);
    Reg#(Addr)               pc <- mkRegU;
    CsrFile                csrf <- mkCsrFile(id);
    RFile                    rf <- mkRFile;
    Reg#(ExecInst)          e2c <- mkRegU;
    Reg#(Stage)           stage <- mkReg(Fetch);
    MemReqIDGen     memReqIDGen <- mkMemReqIDGen;
    ICache               iCache <- mkICache(iMem);
    MessageFifo#(8)   toParentQ <- mkMessageFifo;
    MessageFifo#(8) fromParentQ <- mkMessageFifo;
    DCache               dCache <- mkDCache(id, toMessageGet(fromParentQ), toMessagePut(toParentQ), refDMem);

    rule doFetch if (csrf.started && stage == Fetch);
        iCache.req(pc);
        stage <= Execute;
    endrule

    rule doExecute if (csrf.started && stage == Execute);
        let   inst <- iCache.resp;
        let  dInst = decode(inst);
        let  rVal1 = rf.rd1(validValue(dInst.src1));
        let  rVal2 = rf.rd2(validValue(dInst.src2));
        let csrVal = csrf.rd(validValue(dInst.csr));
        let  eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);
        if (eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction. Exiting\n");
            $finish;
        end
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
        e2c   <= eInst;
        stage <= Commit;
    endrule

    rule doCommit if (csrf.started && stage == Commit);
        let eInst = e2c;
		let willPrint = fromMaybe(?, eInst.csr) != csrMtohost || (fromMaybe(?, eInst.csr) == csrMtohost && id == 0);
        if (eInst.iType == Ld || eInst.iType == Lr || eInst.iType == Sc) begin
            eInst.data <- dCache.resp;
        end
        if (isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end
		csrf.wr(eInst.iType == Csrw && willPrint ? eInst.csr : Invalid, eInst.data);
        pc    <= eInst.brTaken ? eInst.addr : pc + 4;
        stage <= Fetch;
    endrule

    interface MessageGet toParent = toMessageGet(toParentQ);
    interface MessagePut fromParent = toMessagePut(fromParentQ);

    method ActionValue#(CpuToHostData) cpuToHost if (csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod

    method Bool cpuToHostValid = csrf.cpuToHostValid;

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
        csrf.start;
        pc <= startpc;
    endmethod
endmodule
