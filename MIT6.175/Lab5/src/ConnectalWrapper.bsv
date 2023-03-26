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
`ifdef SIXSTAGE
import SixStage::*;
`endif

`ifdef SIXSTAGEBHT
import SixStageBHT::*;
`endif

`ifdef SIXSTAGERAS
import SixStageRAS::*;
`endif

`ifdef SIXSTAGEBONUS
import SixStageBonus::*;
`endif

`ifdef WITHCACHE
import WithCache::*;
`endif

`ifdef WITHOUTCACHE
import WithoutCache::*;
`endif

import Ifc::*;
import ProcTypes::*;
import Types::*;
import Ehr::*;
import Fifo::*;
import MemUtil::*;
import MemTypes::*;
import Memory::*;
import SimMem::*;
import ClientServer::*;
import Clocks::*;

interface ConnectalWrapper;
   interface ConnectalProcRequest connectProc;
endinterface

module [Module] mkConnectalWrapper#(ConnectalProcIndication ind)(ConnectalWrapper);

   `ifdef WITHCACHE
      Fifo#(2, DDR3_Req)  ddr3ReqFifo <- mkCFFifo();
      Fifo#(2, DDR3_Resp) ddr3RespFifo <- mkCFFifo();
      DDR3_Client ddrclient = toGPClient( ddr3ReqFifo, ddr3RespFifo );
      mkSimMem(ddrclient);
      Proc m <- mkProc(ddr3ReqFifo, ddr3RespFifo);
   `else
      Proc m <- mkProc();
   `endif

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
