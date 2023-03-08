import TestBenchTemplates::*;
import MyFifo::*;

//////////////////////////
// Functional Testbenches

// These testbenches compare the outputs of the fifo against a reference fifo.
// If there is any mismatch in the outputs, the simulator will print out an
// error message.

(* synthesize *)
module mkTbConflictFunctional();
    Fifo#(3, Bit#(8)) fifo <- mkMyConflictFifo();
    Bool has_clear = True;
    let m <- mkTbFunctionalTemplate( fifo, Conflict, has_clear );
endmodule

(* synthesize *)
module mkTbPipelineFunctional();
    Fifo#(3, Bit#(8)) fifo <- mkMyPipelineFifo();
    Bool has_clear = True;
    let m <- mkTbFunctionalTemplate( fifo, Pipeline, has_clear );
endmodule

(* synthesize *)
module mkTbBypassFunctional();
    Fifo#(3, Bit#(8)) fifo <- mkMyBypassFifo();
    Bool has_clear = True;
    let m <- mkTbFunctionalTemplate( fifo, Bypass, has_clear );
endmodule

(* synthesize *)
module mkTbCFNCFunctional();
    Fifo#(3, Bit#(8)) fifo <- mkMyCFFifo();
    Bool has_clear = False; // CF but no clear method
    let m <- mkTbFunctionalTemplate( fifo, CF, has_clear );
endmodule

(* synthesize *)
module mkTbCFFunctional();
    Fifo#(3, Bit#(8)) fifo <- mkMyCFFifo();
    Bool has_clear = True; // CF with clear method
    let m <- mkTbFunctionalTemplate( fifo, CF, has_clear );
endmodule

//////////////////////////
// Scheduling Testbenches

// These testbenches force the scheduling constraints that should be valid for
// each FIFO. These constraints include:
//
//  if the FIFO has an implemented clear method:
//      Bypass, CF:   {notFull, enq} < {notEmpty, first, deq} < clear
//      Pipeline, CF: {notEmpty, first, deq} < {notFull, enq} < clear
//  if the FIFO doesn't have an implemented clear method:
//      Bypass, CF:   {notFull, enq} < {notEmpty, first, deq}
//      Pipeline, CF: {notEmpty, first, deq} < {notFull, enq}
//
// If you get a compiler error while compiling any of these testbenches, then
// the FIFO does not meet the required scheduling constraints.

// Why don't you have to instantiate mkMyCFFifo before passing it to
// mkTbSchedulingTemplate? This testbench template takes a module constructor,
// not an interface. This testbench uses the module constructor to construct
// two copies of the same fifo for scheduling tests.

(* synthesize *)
module mkTbPipelineScheduling();
    Bool has_clear = True;
    let m <- mkTbSchedulingTemplate( mkMyPipelineFifo, Pipeline, has_clear );
endmodule

(* synthesize *)
module mkTbBypassScheduling();
    Bool has_clear = True;
    let m <- mkTbSchedulingTemplate( mkMyBypassFifo, Bypass, has_clear );
endmodule

(* synthesize *)
module mkTbCFNCScheduling();
    Bool has_clear = False; // CF but no clear method
    let m <- mkTbSchedulingTemplate( mkMyCFFifo, CF, has_clear );
endmodule

(* synthesize *)
module mkTbCFScheduling();
    Bool has_clear = True; // CF with clear method
    let m <- mkTbSchedulingTemplate( mkMyCFFifo, CF, has_clear );
endmodule
