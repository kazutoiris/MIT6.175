interface ConnectalProcIndication;
	method Action sendMessage(Bit#(18) mess);
endinterface
interface ConnectalProcRequest;
   method Action hostToCpu(Bit#(32) startpc);
endinterface


