import ProcTypes::*;

`ifdef ONECYCLE
import OneCycle::*;
`endif
`ifdef TWOCYCLE
import TwoCycle::*;
`endif
`ifdef TWOSTAGE
import TwoStage::*;
`endif
`ifdef TWOSTAGEBTB
import TwoStageBTB::*;
`endif
`ifdef FOURCYCLE
import FourCycle::*;
`endif

import Ifc::*;
import ProcTypes::*;
import Types::*;
import Ehr::*;

interface ConnectalWrapper;
   interface ConnectalProcRequest connectProc;
endinterface

module [Module] mkConnectalWrapper#(ConnectalProcIndication ind)(ConnectalWrapper);
   Proc m <- mkProc();

   rule relayMessage;
	let mess <- m.cpuToHost();
        ind.sendMessage(pack(mess));	
   endrule
   interface ConnectalProcRequest connectProc;
      method Action hostToCpu(Bit#(32) startpc);
        $display("Received software req to start pc\n");
        $fflush(stdout);
	m.hostToCpu(unpack(startpc));
      endmethod
   endinterface
endmodule
