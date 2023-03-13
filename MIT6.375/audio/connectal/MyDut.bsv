`include "ConnectalProjectConfig.bsv"
import FIFO::*;
import Vector::*;
import DefaultValue::*;
import ClientServer::*;
import GetPut::*;
import Clocks::*;
import FShow::*;

import AudioPipeline::*;
import AudioProcessorTypes::*;

// interface used by software
interface MyDutRequest;
    // Bit#(n) is the only supported argument type for request methods
    method Action putSampleInput (Bit#(16) in);
    method Action reset_dut();
endinterface

// interface used by hardware to send a message back to software
interface MyDutIndication;
    // Bit#(n) is the only supported argument type for indication methods
    method Action returnOutput (Bit#(16) out);
endinterface

// interface of the connectal wrapper (mkMyDut) of your design
interface MyDut;
    interface MyDutRequest request;
    // More sub-interface will be added to support DMA to host memory (if needed in the final project)
endinterface

module mkMyDut#(MyDutIndication indication) (MyDut);
    // Soft reset generator
    Reg#(Bool) isResetting <- mkReg(False);
    Reg#(Bit#(2)) resetCnt <- mkReg(0);
    Clock connectal_clk <- exposeCurrentClock;
    MakeResetIfc my_rst <- mkReset(1, True, connectal_clk); // inherits parent's reset (hidden) and introduce extra reset method (OR condition)
    rule clearResetting if (isResetting);
        resetCnt <= resetCnt + 1;
        if (resetCnt == 3) isResetting <= False;
    endrule

    // Your design
    AudioProcessor ap <- mkAudioPipeline(reset_by my_rst.new_rst);

    // Send a message back to sofware whenever the response is ready
    rule indicationToSoftware;
        let d <- ap.getSampleOutput;
        $display("out: %d", d);
        indication.returnOutput(pack(d)); // pack casts the "type" of non-Bit#(n) variable into Bit#(n). Physical bits do not change. Just type conversion.
    endrule

    Reg#(Bit#(32)) cnt <- mkReg(0);
    // Interface used by software (MyDutRequest)
    interface MyDutRequest request;
        method Action putSampleInput (Bit#(16) in) if (!isResetting);
            $display("in: %d %d", in, cnt);
            cnt <= cnt + 1;
            ap.putSampleInput(unpack(in)); // unpack casts the type of a Bit#(n) value into a different type, i.e., Sample, which is Int#(16)
        endmethod

        method Action reset_dut;
            my_rst.assertReset; // assert my_rst.new_rst signal
            isResetting <= True;
        endmethod
    endinterface
endmodule
