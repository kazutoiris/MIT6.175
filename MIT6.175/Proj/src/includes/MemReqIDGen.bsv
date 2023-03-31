import MemTypes::*;

interface MemReqIDGen;
	method ActionValue#(MemReqID) getID;
endinterface

module mkMemReqIDGen(MemReqIDGen);
	Reg#(MemReqID) data <- mkReg(0);

	method ActionValue#(MemReqID) getID;
		data <= data + 1;
		return data;
	endmethod
endmodule
