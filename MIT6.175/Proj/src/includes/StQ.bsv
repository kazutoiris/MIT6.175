import Types::*;
import Ehr::*;
import Vector::*;
import MemTypes::*;

typedef MemReq StQEntry;

interface StQ#(numeric type n);
	method Action enq(StQEntry e);
	method Action deq;
	method ActionValue#(StQEntry) issue;
	method Maybe#(Data) search(Addr a);
	method Bool notEmpty;
	method Bool notFull;
	method Bool isIssued;
endinterface

// isIssued < issue < deq
// all other CF
module mkStQ(StQ#(n));
	Vector#(n, Reg#(StQEntry))  val <- replicateM(mkRegU);
    Reg#(Bit#(TLog#(n)))       enqP <- mkReg(0);
    Reg#(Bit#(TLog#(n)))       deqP <- mkReg(0);
    Reg#(Bool)                empty <- mkReg(True);
    Reg#(Bool)                 full <- mkReg(False);
	Ehr#(2, Bool)            issued <- mkEhr(False); // oldest entry issued

	Ehr#(2, Maybe#(StQEntry)) enqEn <- mkEhr(Invalid);
	Ehr#(2, Bool)             deqEn <- mkEhr(False);


    Bit#(TLog#(n)) max_index = fromInteger(valueOf(n) - 1);

	function Bit#(TLog#(n)) nextPtr(Bit#(TLog#(n)) curPtr);
		return curPtr == max_index ? 0 : curPtr + 1;
	endfunction

	(* fire_when_enabled *)
	(* no_implicit_conditions *)
	rule cononicalize;
		let enqP_nxt = enqP;
		let deqP_nxt = deqP;
		// change ptr
		if(enqEn[1] matches tagged Valid .x) begin
			val[enqP] <= x;
			enqP_nxt = nextPtr(enqP);
		end
		if(deqEn[1]) begin
			deqP_nxt = nextPtr(deqP);
		end
		enqP <= enqP_nxt;
		deqP <= deqP_nxt;
		// change full, empty
		Bool isEnq = isValid(enqEn[1]);
		Bool isDeq = deqEn[1];
		Bool nextPtrEq = deqP_nxt == enqP_nxt;
		if(isEnq && !isDeq) begin
			empty <= False;
			full <= nextPtrEq;
		end
		else if(!isEnq && isDeq) begin
			full <= False;
			empty <= nextPtrEq;
		end
		// clear enables
		enqEn[1] <= Invalid;
		deqEn[1] <= False;
	endrule

	// we do 2 passes of search to get the youngest matching entry
    Bool deqP_lt_enqP = deqP < enqP;
    Bool valid_pass_one[valueOf(n)];
    Bool valid_pass_two[valueOf(n)];

    for( Integer i = 0 ; i < valueOf(n) ; i = i+1 ) begin
        valid_pass_one[i] = fromInteger(i) >= deqP && (deqP_lt_enqP ? fromInteger(i) < enqP : !empty);
        valid_pass_two[i] = fromInteger(i) < enqP && !deqP_lt_enqP && !empty;
    end

    method Maybe#(Data) search(Addr a);
        Maybe#(Data) ret = Invalid;
        // Get the youngest matching request
        for( Integer i = 0 ; i < valueOf(n) ; i = i+1 ) begin
            if( valid_pass_one[i] && a == val[i].addr ) begin
                ret = Valid (val[i].data);
            end
        end
        for( Integer i = 0 ; i < valueOf(n) ; i = i+1 ) begin
            if( valid_pass_two[i] && a == val[i].addr ) begin
                ret = Valid (val[i].data);
            end
        end
        return ret;
    endmethod

    method Bool notFull = !full;

    method Action enq(StQEntry x) if(!full);
		enqEn[0] <= Valid (x);
    endmethod

    method Bool notEmpty = !empty;

	// don't check issued[1] here, may lead to circular dep loop
    method Action deq if(!empty);
		deqEn[0] <= True;
		issued[1] <= False;
    endmethod

    method ActionValue#(StQEntry) issue if(!empty && !issued[0]);
		issued[0] <= True;
        return val[deqP];
    endmethod

	method Bool isIssued = issued[0];
endmodule
