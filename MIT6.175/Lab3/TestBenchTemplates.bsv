import Multipliers::*;
import Randomizable::*;
import FIFO::*;


// Function-Function Test Bench
module mkTbMulFunction(
    function Bit#(TAdd#(n,n)) test_function( Bit#(n) a, Bit#(n) b ),
    function Bit#(TAdd#(n,n)) ref_function( Bit#(n) a, Bit#(n) b ),
    Bool verbose,
    Empty ifc
) provisos( Add#(a__, n, TMul#(TDiv#(n, 32), 32)), Add#(1, b__, n) );
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Randomize#(Bit#(n)) randomA <- mkGenericRandomizer;
    Randomize#(Bit#(n)) randomB <- mkGenericRandomizer;
    Bit#(n) most_neg_number = { 1'b1, 0 };

    rule test;
        if(cycle == 0) begin
            randomA.cntrl.init;
            randomB.cntrl.init;
        end else if(cycle == 128) begin
            $display("PASSED");
            $finish;
        end else begin
            Bit#(n) a <- randomA.next;
            Bit#(n) b <- randomB.next;

            // Don't allow a or b to be the most negative number
            if( a != most_neg_number && b != most_neg_number ) begin
                let test = test_function(a,b);
                let expected = ref_function(a,b);

                if(test != expected) begin
                    Int#(n) a_signed = unpack(a);
                    Int#(n) b_signed = unpack(b);
                    Int#(TAdd#(n,n)) test_signed = unpack(test);
                    Int#(TAdd#(n,n)) expected_signed = unpack(expected);
                    $display("FAILED:");
                    $display("    if signed: %0d * %0d test function gave %0d instead of %0d", a_signed, b_signed, test_signed, expected_signed);
                    $display("    if unsigned: %0d * %0d test function gave %0d instead of %0d", a, b, test, expected);
                    $finish;
                end else if( verbose ) begin
                    Int#(n) a_signed = unpack(a);
                    Int#(n) b_signed = unpack(b);
                    Int#(TAdd#(n,n)) test_signed = unpack(test);
                    $display("PASSED case %0d", cycle);
                    $display("    if signed: %0d * %0d test function gave %0d", a_signed, b_signed, test_signed);
                    $display("    if unsigned: %0d * %0d test function gave %0d", a, b, test);
                end
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule



// Module-Function Test Bench
module mkTbMulModule(
    Multiplier#(n) dut,
    function Bit#(TAdd#(n,n)) ref_function( Bit#(n) a, Bit#(n) b ),
    Bool verbose,
    Empty ifc
) provisos( Add#(a__, n, TMul#(TDiv#(n, 32), 32)), Add#(1, b__, n) );
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Reg#(Bit#(32)) feed_count <- mkReg(0);
    Reg#(Bit#(32)) read_count <- mkReg(0);
    FIFO#(Tuple2#(Bit#(n),Bit#(n))) operands_fifo <- mkSizedFIFO(4);
    Randomize#(Bit#(n)) randomA <- mkGenericRandomizer;
    Randomize#(Bit#(n)) randomB <- mkGenericRandomizer;
    Bit#(n) most_neg_number = { 1'b1, 0 };

    rule feed( feed_count != 128 && dut.start_ready );
        Bit#(n) a <- randomA.next;
        Bit#(n) b <- randomB.next;
        // Don't allow a or b to be the most negative number
        if( a != most_neg_number && b != most_neg_number ) begin
            operands_fifo.enq( tuple2(a,b) );
            dut.start( a, b );
            feed_count <= feed_count + 1;
        end
    endrule

    rule read( read_count != 128 && dut.result_ready );
        Bit#(n) a = tpl_1( operands_fifo.first() );
        Bit#(n) b = tpl_2( operands_fifo.first() );
        operands_fifo.deq();
        Bit#(TAdd#(n,n)) test <- dut.result();
        Bit#(TAdd#(n,n)) expected = ref_function(a,b);
        if( test != expected ) begin
            Int#(n) a_signed = unpack(a);
            Int#(n) b_signed = unpack(b);
            Int#(TAdd#(n,n)) test_signed = unpack(test);
            Int#(TAdd#(n,n)) expected_signed = unpack(expected);
            $display("FAILED case %0d", read_count);
            $display("    if signed: %0d * %0d DUT gave %0d instead of %0d", a_signed, b_signed, test_signed, expected_signed);
            $display("    if unsigned: %0d * %0d DUT gave %0d instead of %0d", a, b, test, expected);
            $finish;
        end else if( verbose ) begin
            Int#(n) a_signed = unpack(a);
            Int#(n) b_signed = unpack(b);
            Int#(TAdd#(n,n)) test_signed = unpack(test);
            $display("PASSED case %0d", read_count);
            $display("    if signed: %0d * %0d DUT gave %0d", a_signed, b_signed, test_signed);
            $display("    if unsigned: %0d * %0d DUT gave %0d", a, b, test);
        end
        read_count <= read_count + 1;
    endrule

    rule monitor_test;
        if( cycle == 0 ) begin
            randomA.cntrl.init;
            randomB.cntrl.init;
        end
        if( read_count == 128 ) begin
            if( verbose ) begin
                $display("PASSED %0d test cases in %0d cycles", read_count, cycle);
            end else begin
                $display("PASSED");
            end
            $finish;
        end
        if( cycle == 128*128 ) begin
            // 128 cycles per mult should be pleanty of time
            $display("FAILED due to cycle limit");
            $finish;
        end
        cycle <= cycle + 1;
    endrule
endmodule
