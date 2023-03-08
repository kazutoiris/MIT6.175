import Vector::*;
import Randomizable::*;
import Adders::*;
import Multiplexer::*;
import BarrelShifter::*;

// Mux testbenches

(* synthesize *)
module mkTbMuxSimple();
    Reg#(Bit#(32)) cycle <- mkReg(0);

    Vector#(8, Bit#(5)) val1s = replicate( 0 );
    Vector#(8, Bit#(5)) val2s = replicate( 0 );
    Vector#(8, Bit#(1)) sels = replicate( 0 );
    val1s[0] = 0;     val2s[0] = 1;   sels[0] = 0;
    val1s[1] = 4;     val2s[1] = 7;   sels[1] = 1;
    val1s[2] = 31;    val2s[2] = 31;  sels[2] = 0;
    val1s[3] = 0;     val2s[3] = 31;  sels[3] = 1;
    val1s[4] = 0;     val2s[4] = 31;  sels[4] = 0;
    val1s[5] = 8;     val2s[5] = 0;   sels[5] = 0;
    val1s[6] = 11;    val2s[6] = 29;  sels[6] = 1;
    val1s[7] = 21;    val2s[7] = 22;  sels[7] = 1;

    rule test;
        if(cycle == 8) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 = val1s[cycle];
            let val2 = val2s[cycle];
            let sel = sels[cycle];
            let test = multiplexer5(sel, val1, val2);
            let realAns = sel == 0? val1: val2;
            if(test != realAns) begin
                $display("FAILED Sel %b from %d, %d gave %d instead of %d", sel, val1, val2, test, realAns);
                $finish;
            end else begin
                $display("Sel %b from %d, %d is %d", sel, val1, val2, test);
            end
            cycle <= cycle + 1;
        end
    endrule
endmodule

(* synthesize *)
module mkTbMux();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Randomize#(Bit#(5)) randomVal1 <- mkGenericRandomizer;
    Randomize#(Bit#(5)) randomVal2 <- mkGenericRandomizer;
    Randomize#(Bit#(1))  randomSel <- mkGenericRandomizer;

    rule test;
        if(cycle == 0) begin
            randomVal1.cntrl.init;
            randomVal2.cntrl.init;
            randomSel.cntrl.init;
        end else if(cycle == 128) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 <- randomVal1.next;
            let val2 <- randomVal2.next;
            let sel <- randomSel.next;
            let test = multiplexer5(sel, val1, val2);
            let realAns = sel == 0? val1: val2;
            if(test != realAns) begin
                $display("FAILED Sel %b from %d, %d gave %d instead of %d", sel, val1, val2, test, realAns);
                $finish;
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule

// ripple carry adder testbenches

(* synthesize *)
module mkTbRCASimple();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Adder8 adder <- mkRCAdder();

    Vector#(8, Bit#(8)) as = replicate( 0 );
    Vector#(8, Bit#(8)) bs = replicate( 0 );
    as[0] = 1;    bs[0] = 1;
    as[1] = 8;    bs[1] = 8;
    as[2] = 63;   bs[2] = 27;
    as[3] = 102;  bs[3] = 92;
    as[4] = 177;  bs[4] = 202;
    as[5] = 128;  bs[5] = 128;
    as[6] = 255;  bs[6] = 1;
    as[7] = 255;  bs[7] = 255;

    rule test;
        if(cycle == 8) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 = as[cycle];
            let val2 = bs[cycle];
            let test <- adder.sum( val1, val2, 0 );
            Bit#(9) realAns = zeroExtend(val1) + zeroExtend(val2);
            if(test != realAns) begin
                $display("FAILED %d + %d gave %d instead of %d", val1, val2, test, realAns);
                $finish;
            end else begin
                $display("%d + %d = %d", val1, val2, test);
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule

(* synthesize *)
module mkTbRCA();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Randomize#(Bit#(8)) randomVal1 <- mkGenericRandomizer;
    Randomize#(Bit#(8)) randomVal2 <- mkGenericRandomizer;
    Adder8 adder <- mkRCAdder();

    rule test;
        if(cycle == 0) begin
            randomVal1.cntrl.init;
            randomVal2.cntrl.init;
        end else if(cycle == 128) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 <- randomVal1.next;
            let val2 <- randomVal2.next;
            let test <- adder.sum( val1, val2, 0 );
            Bit#(9) realAns = zeroExtend(val1) + zeroExtend(val2);
            if(test != realAns) begin
                $display("FAILED %d + %d gave %d instead of %d", val1, val2, test, realAns);
                $finish;
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule

// carry select adder testbenches

(* synthesize *)
module mkTbCSASimple();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Adder8 adder <- mkCSAdder();

    Vector#(8, Bit#(8)) as = replicate( 0 );
    Vector#(8, Bit#(8)) bs = replicate( 0 );
    as[0] = 1;    bs[0] = 1;
    as[1] = 8;    bs[1] = 8;
    as[2] = 63;   bs[2] = 27;
    as[3] = 102;  bs[3] = 92;
    as[4] = 177;  bs[4] = 202;
    as[5] = 128;  bs[5] = 128;
    as[6] = 255;  bs[6] = 1;
    as[7] = 255;  bs[7] = 255;

    rule test;
        if(cycle == 8) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 = as[cycle];
            let val2 = bs[cycle];
            let test <- adder.sum( val1, val2, 0 );
            Bit#(9) realAns = zeroExtend(val1) + zeroExtend(val2);
            if(test != realAns) begin
                $display("FAILED %d + %d gave %d instead of %d", val1, val2, test, realAns);
                $finish;
            end else begin
                $display("%d + %d = %d", val1, val2, test);
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule

(* synthesize *)
module mkTbCSA();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Randomize#(Bit#(8)) randomVal1 <- mkGenericRandomizer;
    Randomize#(Bit#(8)) randomVal2 <- mkGenericRandomizer;
    Adder8 adder <- mkCSAdder();

    rule test;
        if(cycle == 0) begin
            randomVal1.cntrl.init;
            randomVal2.cntrl.init;
        end else if(cycle == 128) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 <- randomVal1.next;
            let val2 <- randomVal2.next;
            let test <- adder.sum( val1, val2, 0 );
            Bit#(9) realAns = zeroExtend(val1) + zeroExtend(val2);
            if(test != realAns) begin
                $display("FAILED %d + %d gave %d instead of %d", val1, val2, test, realAns);
                $finish;
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule

(* synthesize *)
module mkTbBS();
    Reg#(Bit#(32)) cycle <- mkReg(0);
    Randomize#(Bit#(32)) randomVal1 <- mkGenericRandomizer;
    Randomize#(Bit#(5)) randomVal2 <- mkGenericRandomizer;

    rule test;
        if(cycle == 0) begin
            randomVal1.cntrl.init;
            randomVal2.cntrl.init;
        end else if(cycle == 128) begin
            $display("PASSED");
            $finish;
        end else begin
            let val1 <- randomVal1.next;
            let val2 <- randomVal2.next;
            Bit#(32) test = barrelShifterRight(val1,val2);
            Bit#(32) realAns = val1 >> val2;
            if(test != realAns) begin
                $display("FAILED %b >> %b gave %b instead of %b", val1, val2, test, realAns);
                $finish;
            end
        end
        cycle <= cycle + 1;
    endrule
endmodule
