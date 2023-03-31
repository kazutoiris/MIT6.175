import MemTypes::*;
import Vector::*;
import RegFile::*;
import Fifo::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

// simulate a memory with pipelined delay
typedef 10 MemDelay;

module mkSimMem(DDR3_Client proc, Empty ifc);
	Vector#(MemDelay, Fifo#(2, DDR3_Resp)) respQ <- replicateM(mkCFFifo);

	// always init using mem.vmh, never simulate initialization
	RegFile#(DDR3Addr, DDR3Data) mem <- mkRegFileFullLoad("mem.vmh");

	// construct new DDR3_Client
	DDR3_Client cli = (interface DDR3_Client;
		interface Get request = proc.request;
		interface Put response = toPut(respQ[0]);
	endinterface);
	// connect to mem
    mkConnection(cli, mem);

	// get delay path for resp
	for(Integer i = 0; i < valueOf(MemDelay) - 1; i = i+1) begin
		mkConnection(toGet(respQ[i]), toPut(respQ[i+1]));
	end

	// connect to response of proc
	mkConnection(proc.response, toGet(respQ[valueOf(MemDelay)-1]));
endmodule
