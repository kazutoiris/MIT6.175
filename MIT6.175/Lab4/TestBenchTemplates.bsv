import Randomizable::*;
import FIFOF::*;
import MyFifo::*;
import Ehr::*;

typedef enum { Conflict, Pipeline, Bypass, CF } FifoType deriving(Eq);

//////////////////////////
// Various Reference FIFO

// These FIFO implementations are hacks to get similar functionality to the
// FIFOs you will make in lab. These are used as reference FIFOs in the
// mkTbFunctionalTemplate test bench.

// This is a conflict-free wrapper for BSV's built in FIFOF
module mkTestCFFifo(Fifo#(n,t)) provisos(Bits#(t,tSz));
    // Built-in FIFO with slightly different scheduling annotations
    FIFOF#(t) ref_noncf_fifo <- mkSizedFIFOF(valueOf(n));
    Ehr#(3, Maybe#(t)) _enq <- mkEhr(tagged Invalid);
    Ehr#(3, Maybe#(Bool)) _deq <- mkEhr(tagged Invalid);
    Ehr#(2, t) _first <- mkEhr(?);
    Ehr#(2, Bool) _not_full <- mkEhr(True);
    Ehr#(2, Bool) _not_empty <- mkEhr(False);

    // These attributes are statically checked by the compiler
    (* fire_when_enabled *)         // WILL_FIRE == CAN_FIRE
    (* no_implicit_conditions *)    // CAN_FIRE == guard (True)
    rule pre_canonicalize_one;
        _not_full[0] <= ref_noncf_fifo.notFull;
        _not_empty[0] <= ref_noncf_fifo.notEmpty;
    endrule

    (* fire_when_enabled *)
    rule pre_canonicalize_two;
        _first[0] <= ref_noncf_fifo.first;
    endrule

    (* fire_when_enabled *)
    // (* no_implicit_conditions *) // The compiler can't figure this one out
    rule post_canonicalize;
        if( isValid(_enq[1]) ) begin
            ref_noncf_fifo.enq( fromMaybe(?,_enq[1]) );
        end
        if( isValid(_deq[1]) ) begin
            ref_noncf_fifo.deq;
        end
        _enq[1] <= tagged Invalid;
        _deq[1] <= tagged Invalid;
    endrule

    method Bool notFull;
        return _not_full[1];
    endmethod

    method Action enq(t x) if(_not_full[1]);
        _enq[0] <= tagged Valid x;
    endmethod

    method Bool notEmpty;
        return _not_empty[1];
    endmethod

    method Action deq if(_not_empty[1]);
        _deq[0] <= tagged Valid False;
    endmethod

    method t first if(_not_empty[1]);
        return _first[1];
    endmethod

    method Action clear;
        ref_noncf_fifo.clear;
    endmethod
endmodule

// This is a fake pipeline wrapper for the reference CFFifo
module mkTestPipelineFifo(Fifo#(n,t)) provisos(Bits#(t,tSz));
    Fifo#(TAdd#(n,1), t) fake_pipeline_fifo <- mkTestCFFifo;
    Ehr#(3, Bit#(TLog#(TAdd#(n,1)))) elem_count <- mkEhr(0);

    method Bool notFull = elem_count[1] != fromInteger(valueOf(n));
    method Action enq(t x) if(elem_count[1] != fromInteger(valueOf(n)));
        fake_pipeline_fifo.enq(x);
        elem_count[1] <= elem_count[1] + 1;
    endmethod
    method Bool notEmpty = elem_count[0] != 0;
    method Action deq if(elem_count[0] != 0);
        fake_pipeline_fifo.deq;
        elem_count[0] <= elem_count[0] - 1;
    endmethod
    method t first if(elem_count[0] != 0);
        return fake_pipeline_fifo.first;
    endmethod
    method Action clear;
        fake_pipeline_fifo.clear;
        elem_count[2] <= 0;
    endmethod
endmodule

// This is a fake bypass wrapper for the reference CFFifo
module mkTestBypassFifo(Fifo#(n,t)) provisos(Bits#(t,tSz));
    Fifo#(n, t) fake_bypass_fifo <- mkTestCFFifo;
    Ehr#(3, Bit#(TLog#(TAdd#(n,1)))) elem_count <- mkEhr(0);
    Ehr#(3, Maybe#(t)) enq_req <- mkEhr(tagged Invalid);

    rule canonicalize;
        if( isValid(enq_req[2]) ) begin
            fake_bypass_fifo.enq(fromMaybe(?,enq_req[2]));
        end
        enq_req[2] <= tagged Invalid;
    endrule

    method Bool notFull = elem_count[0] != fromInteger(valueOf(n));
    method Action enq(t x) if(elem_count[0] != fromInteger(valueOf(n)));
        enq_req[0] <= tagged Valid x;
        elem_count[0] <= elem_count[0] + 1;
    endmethod
    method Bool notEmpty = elem_count[1] != 0;
    method Action deq if(elem_count[1] != 0);
        if( fake_bypass_fifo.notEmpty ) begin
            fake_bypass_fifo.deq;
        end else begin
            enq_req[1] <= tagged Invalid;
        end
        elem_count[1] <= elem_count[1] - 1;
    endmethod
    method t first if(elem_count[1] != 0);
        if( fake_bypass_fifo.notEmpty ) begin
            return fake_bypass_fifo.first;
        end else begin
            return fromMaybe(?, enq_req[1]);
        end
    endmethod
    method Action clear;
        fake_bypass_fifo.clear;
        elem_count[2] <= 0;
    endmethod
endmodule

////////////////////////
// Test Bench Templates

// This tests the functionality of the fifo considering enq, deq, and clear
module mkTbFunctionalTemplate( Fifo#(n, Bit#(m)) fifo, FifoType fifo_type, Bool has_clear, Empty ifc );
    Fifo#(n, Bit#(m)) ref_fifo;
    if( fifo_type == Pipeline ) begin
        ref_fifo <- mkTestPipelineFifo();
    end else if( fifo_type == Bypass ) begin
        ref_fifo <- mkTestBypassFifo();
    end else begin
        ref_fifo <- mkTestCFFifo();
    end
    // Various Counters
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Reg#(Bit#(32)) input_count <- mkReg(0);
    Reg#(Bit#(32)) output_count <- mkReg(0);
    // Random Number Generators
    Randomize#(Bit#(2)) randomA <- mkGenericRandomizer;
    Randomize#(Bit#(2)) randomB <- mkGenericRandomizer;
    Randomize#(Bit#(4)) randomC <- mkGenericRandomizer;
    Randomize#(Bit#(m)) randomData <- mkGenericRandomizer;

    // Forces the order of the rules so the cycle boundary is printed first.
    // It is really confusing when the cycle_print rule fires in the middle of
    // the clock cycle.
    (* execution_order = "cycle_print, init" *)
    (* execution_order = "cycle_print, feed_inputs" *)
    (* execution_order = "cycle_print, check_outputs" *)
    (* execution_order = "cycle_print, maybe_clear" *)
    (* execution_order = "cycle_print, check_fifos_not_empty" *)
    (* execution_order = "cycle_print, check_fifos_not_full" *)
    (* execution_order = "cycle_print, check_fifos_first" *)
    (* execution_order = "cycle_print, stop_tb" *)
    (* execution_order = "cycle_print, cycle_inc" *)
    rule cycle_print;
        $display("= cycle %0d ====================", cycle);
    endrule

    rule init(cycle == 0);
        randomA.cntrl.init;
        randomB.cntrl.init;
        randomC.cntrl.init;
        randomData.cntrl.init;
    endrule

    rule feed_inputs (input_count < 1024);
        let rnd <- randomA.next;
        if( rnd != 0 ) begin // P = 3/4
            let a <- randomData.next;
            fifo.enq( a );
            ref_fifo.enq( a );
            $display("\tEnqueued %0d", a);
            input_count <= input_count + 1;
        end
    endrule

    rule check_outputs;
        let rnd <- randomB.next;
        if( rnd != 0 ) begin // P = 3/4
            let b = fifo.first;
            fifo.deq;
            $display("\tDequeued %0d", b);
            let c = ref_fifo.first;
            ref_fifo.deq;
            if( b != c ) begin
                $display("\tERROR: should have dequeued %0d", c);
                $finish;
            end
            output_count <= output_count + 1;
        end
    endrule

    rule maybe_clear;
        let rnd <- randomC.next;
        if( has_clear && (rnd == 0) ) begin // P = 1/16
            fifo.clear;
            ref_fifo.clear;
            $display("\tCleared fifo");
        end
    endrule

    rule check_fifos_not_full;
        if( ref_fifo.notFull != fifo.notFull ) begin
            if( fifo.notFull ) begin
                $display( "\tERROR: test fifo is not full but reference fifo is." );
                $finish;
            end else begin
                $display( "\tERROR: test fifo is full but reference fifo is not." );
                $finish;
            end
        end
    endrule

    rule check_fifos_not_empty;
        if( ref_fifo.notEmpty != fifo.notEmpty ) begin
            if( fifo.notEmpty ) begin
                $display( "\tERROR: test fifo is not empty but reference fifo is." );
                $finish;
            end else begin
                $display( "\tERROR: test fifo is empty but reference fifo is not." );
                $finish;
            end
        end
    endrule

    rule check_fifos_first;
        if( ref_fifo.notEmpty && fifo.notEmpty ) begin
            if( ref_fifo.first != fifo.first ) begin
                $display( "\tError: fifo.first = %0d but ref_fifo.first = %0d.", fifo.first, ref_fifo.first );
                $finish;
            end
        end
    endrule

    rule stop_tb (input_count == 1024 || cycle == 4096);
        if( input_count == 1024 ) begin
            $display("\tFinished Test");
            $display("\tOutput count = %0d", output_count);
        end else begin
            $display("\tERROR: Reached maximum cycle count!");
        end
        $finish;
    endrule

    rule cycle_inc;
        cycle <= cycle + 1;
    endrule
endmodule

// This tests the schedulability of the fifo
module [Module] mkTbSchedulingTemplate( Module#(Fifo#(3, Bit#(8))) mkFifo, FifoType fifo_type, Bool has_clear, Empty ifc );
    Reg#(Bit#(32)) cycle <- mkReg(0);

    Fifo#(3, Bit#(8)) fifo_1 <- mkFifo();
    Fifo#(3, Bit#(8)) fifo_2 <- mkFifo();

    Ehr#(3, Bit#(2)) fifo_1_ehr <- mkEhr(0);
    Ehr#(3, Bit#(2)) fifo_2_ehr <- mkEhr(0);

    Bool enq_before_deq = (fifo_type == Bypass || fifo_type == CF);
    Bool deq_before_enq = (fifo_type == Pipeline || fifo_type == CF);

    // fifo_1
    // enq < deq < clear
    if( enq_before_deq ) begin
        rule enq_fifo_1;
            if( fifo_1_ehr[0] == 0 ) begin
                if( fifo_1.notFull() ) begin
                    fifo_1.enq(1);
                end
                fifo_1_ehr[0] <= 1;
            end
        endrule
        rule deq_fifo_1;
            if( fifo_1_ehr[1] == 1 ) begin
                if( fifo_1.notEmpty() ) begin
                    $display("fifo_1 had %0d", fifo_1.first);
                    fifo_1.deq;
                end
                if( has_clear ) begin
                    fifo_1_ehr[1] <= 2;
                end else begin
                    fifo_1_ehr[1] <= 0;
                end
            end
        endrule
        if( has_clear ) begin
            rule clear_fifo_1;
                if( fifo_1_ehr[2] == 2 ) begin
                    fifo_1.clear;
                    fifo_1_ehr[2] <= 0;
                end
            endrule
        end
    end

    // fifo_2
    // deq < enq < clear
    if( deq_before_enq ) begin
        rule deq_fifo_2;
            if( fifo_2_ehr[0] == 0 ) begin
                if( fifo_2.notEmpty() ) begin
                    $display("fifo_2 had %0d", fifo_2.first);
                    fifo_2.deq;
                end
                fifo_2_ehr[0] <= 1;
            end
        endrule
        rule enq_fifo_2;
            if( fifo_2_ehr[1] == 1 ) begin
                if( fifo_2.notFull() ) begin
                    fifo_2.enq(2);
                end
                if( has_clear ) begin
                    fifo_2_ehr[1] <= 2;
                end else begin
                    fifo_2_ehr[1] <= 0;
                end
            end
        endrule
        if( has_clear ) begin
            rule clear_fifo_2;
                if( fifo_2_ehr[2] == 2 ) begin
                    fifo_2.clear;
                    fifo_2_ehr[2] <= 0;
                end
            endrule
        end
    end

    rule cycle_stuff;
        if( cycle == 5 ) begin
            $display("This testbench is not designed to be run. Instead it is intended to produce");
            $display("compiler warnings based on the scheduling properities of the specified fifo.");
            $display("See the lab documentation and the source code for more details.");
            $finish;
        end
        cycle <= cycle + 1;
    endrule
endmodule
