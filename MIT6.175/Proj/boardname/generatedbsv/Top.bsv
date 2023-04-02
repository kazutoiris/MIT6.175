
import ConnectalConfig::*;
import Vector::*;
import BuildVector::*;
import Portal::*;
import CtrlMux::*;
import HostInterface::*;
import Connectable::*;
import MemReadEngine::*;
import MemWriteEngine::*;
import ConnectalMemTypes::*;
import MemServer::*;
`include "ConnectalProjectConfig.bsv"
import IfcNames::*;
import `PinTypeInclude::*;
import ConnectalProcIndication::*;
import ConnectalWrapper::*;
import ConnectalProcRequest::*;
import ConnectalMemoryInitialization::*;



`ifndef IMPORT_HOSTIF
(* synthesize *)
`endif
module mkConnectalTop
`ifdef IMPORT_HOSTIF // no synthesis boundary
      #(HostInterface host)
`else
`ifdef IMPORT_HOST_CLOCKS // enables synthesis boundary
       #(Clock derivedClockIn, Reset derivedResetIn)
`else
// otherwise no params
`endif
`endif
       (ConnectalTop#(`PinType));
   Clock defaultClock <- exposeCurrentClock();
   Reset defaultReset <- exposeCurrentReset();
`ifdef IMPORT_HOST_CLOCKS // enables synthesis boundary
   HostInterface host = (interface HostInterface;
                           interface Clock derivedClock = derivedClockIn;
                           interface Reset derivedReset = derivedResetIn;
                         endinterface);
`endif
   ConnectalMemoryInitializationInput lConnectalMemoryInitializationInput <- mkConnectalMemoryInitializationInput;
   ConnectalProcIndicationOutput lConnectalProcIndicationOutput <- mkConnectalProcIndicationOutput;
   ConnectalProcRequestInput lConnectalProcRequestInput <- mkConnectalProcRequestInput;

   let lConnectalWrapper <- mkConnectalWrapper(lConnectalProcIndicationOutput.ifc);


   mkConnection(lConnectalMemoryInitializationInput.pipes, lConnectalWrapper.initProc);
   mkConnection(lConnectalProcRequestInput.pipes, lConnectalWrapper.connectProc);

   Vector#(3,StdPortal) portals;
   PortalCtrlMemSlave#(SlaveControlAddrWidth,SlaveDataBusWidth) ctrlPort_0 <- mkPortalCtrlMemSlave(extend(pack(IfcNames_ConnectalProcIndicationH2S)), lConnectalProcIndicationOutput.portalIfc.intr);
   let memslave_0 <- mkMemMethodMuxOut(ctrlPort_0.memSlave,lConnectalProcIndicationOutput.portalIfc.indications);
   portals[0] = (interface MemPortal;
       interface PhysMemSlave slave = memslave_0;
       interface ReadOnly interrupt = ctrlPort_0.interrupt;
       interface WriteOnly num_portals = ctrlPort_0.num_portals;
       endinterface);
   PortalCtrlMemSlave#(SlaveControlAddrWidth,SlaveDataBusWidth) ctrlPort_1 <- mkPortalCtrlMemSlave(extend(pack(IfcNames_ConnectalProcRequestS2H)), lConnectalProcRequestInput.portalIfc.intr);
   let memslave_1 <- mkMemMethodMuxIn(ctrlPort_1.memSlave,lConnectalProcRequestInput.portalIfc.requests);
   portals[1] = (interface MemPortal;
       interface PhysMemSlave slave = memslave_1;
       interface ReadOnly interrupt = ctrlPort_1.interrupt;
       interface WriteOnly num_portals = ctrlPort_1.num_portals;
       endinterface);
   PortalCtrlMemSlave#(SlaveControlAddrWidth,SlaveDataBusWidth) ctrlPort_2 <- mkPortalCtrlMemSlave(extend(pack(IfcNames_ConnectalMemoryInitializationS2H)), lConnectalMemoryInitializationInput.portalIfc.intr);
   let memslave_2 <- mkMemMethodMuxIn(ctrlPort_2.memSlave,lConnectalMemoryInitializationInput.portalIfc.requests);
   portals[2] = (interface MemPortal;
       interface PhysMemSlave slave = memslave_2;
       interface ReadOnly interrupt = ctrlPort_2.interrupt;
       interface WriteOnly num_portals = ctrlPort_2.num_portals;
       endinterface);
   let ctrl_mux <- mkSlaveMux(portals);
   Vector#(NumWriteClients,MemWriteClient#(DataBusWidth)) nullWriters = replicate(null_mem_write_client());
   Vector#(NumReadClients,MemReadClient#(DataBusWidth)) nullReaders = replicate(null_mem_read_client());
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface readers = take(nullReaders);
   interface writers = take(nullWriters);
`ifdef TOP_SOURCES_PORTAL_CLOCK
   interface portalClockSource = None;
`endif


endmodule : mkConnectalTop
export mkConnectalTop;
export `PinTypeInclude::*;
