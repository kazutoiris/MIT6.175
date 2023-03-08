// Reference functions that use Bluespec's '*' operator
function Bit#(TAdd#(n,n)) multiply_unsigned( Bit#(n) a, Bit#(n) b );
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack( product_uint );
endfunction

function Bit#(TAdd#(n,n)) multiply_signed( Bit#(n) a, Bit#(n) b );
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack( product_int );
endfunction

// Multiplication by repeated addition
function Bit#(TAdd#(n,n)) multiply_by_adding(Bit#(n) a, Bit#(n) b);
    Bit#(n) carry = 0;
    Bit#(n) res = 0;

    for(Integer i = 0; i < valueOf(n); i = i + 1)
    begin
        Bit#(TAdd#(1,n)) sum = zeroExtend(carry) + ((b[i] == 1) ? zeroExtend(a) : 0);
        res[i] = sum[0];
        carry = truncateLSB(sum);
    end
    return {carry, res};
endfunction

// Multiplier Interface
interface Multiplier#( numeric type n );
    method Bool start_ready();
    method Action start( Bit#(n) a, Bit#(n) b );
    method Bool result_ready();
    method ActionValue#(Bit#(TAdd#(n,n))) result();
endinterface


// Folded multiplier by repeated addition
module mkFoldedMultiplier( Multiplier#(n) )
	provisos(Add#(1, a__, n)); // make sure n >= 1

    // You can use these registers or create your own if you want
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(n)) res <- mkRegU();
    Reg#(Bit#(n)) carry <- mkRegU();
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg(fromInteger(valueOf(n) + 1));

    rule mulStep(i < fromInteger(valueOf(n)));
        Bit#(TAdd#(n, 1)) sum = zeroExtend(carry) + zeroExtend((b[0] == 1)? a: 0);
        res[i] <= sum[0];
        carry <= truncateLSB(sum);
        b <= b >> 1;
        i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n) + 1);
    endmethod

    method Action start( Bit#(n) aIn, Bit#(n) bIn ) if (i == fromInteger(valueOf(n) + 1));
        a <= aIn;
        b <= bIn;
        i <= 0;
        carry <= 0;
        res <= 0;
    endmethod

    method Bool result_ready();
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result if (i == fromInteger(valueOf(n)));
        i <= i + 1;
        return { carry, res };
    endmethod
endmodule



function Bit#(n) arth_shift(Bit#(n) a, Integer n, Bool right_shift);
    Int#(n) a_int = unpack(a);
    if (right_shift) begin
        return  pack(a_int >> n);
    end else begin //left shift
        return  pack(a_int <<n);
    end
endfunction



// Booth Multiplier
module mkBoothMultiplier( Multiplier#(n) )
	provisos(Add#(2, a__, n)); // make sure n >= 2

    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),1))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)+1) );

    rule mul_step(i < fromInteger(valueOf(n)));
        let pr = p[1:0];
        Bit#(TAdd#(TAdd#(n,n), 1)) temp = p;

        if (pr == 2'b01) begin
            temp = p + m_pos;
        end

        if (pr == 2'b10) begin
            temp = p + m_neg;
        end

        p <= arth_shift(temp, 1, True);
        i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n) + 1);
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r ) if (i == fromInteger(valueOf(n) + 1));
        m_pos <= {m, 0};
        m_neg <= {-m, 0};
        p <= {0, r, 1'b0};
        i <= 0;
    endmethod

    method Bool result_ready();
        return i == fromInteger(valueOf(n));
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result() if (i == fromInteger(valueOf(n)));
        i <= i + 1;
        return truncateLSB(p);
    endmethod
endmodule



// Radix-4 Booth Multiplier
module mkBoothMultiplierRadix4( Multiplier#(n) )
	provisos(Mul#(a__, 2, n), Add#(1, b__, a__)); // make sure n >= 2 and n is even

    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_pos <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) m_neg <- mkRegU;
    Reg#(Bit#(TAdd#(TAdd#(n,n),2))) p <- mkRegU;
    Reg#(Bit#(TAdd#(TLog#(n),1))) i <- mkReg( fromInteger(valueOf(n)/2+1) );

    rule mul_step(i < fromInteger(valueOf(n))/2);
        let pr  = p[2:0];
        Bit#(TAdd#(TAdd#(n, n), 2)) temp = p;

        if ((pr == 3'b001) || (pr == 3'b010)) begin temp = p + m_pos; end
        if ((pr == 3'b101) || (pr == 3'b110)) begin temp = p + m_neg; end
        if (pr == 3'b011) begin temp = p + arth_shift(m_pos, 1, False); end
        if (pr == 3'b100) begin temp = p + arth_shift(m_neg, 1, False); end

        p <= arth_shift(temp, 2, True);
        i <= i + 1;
    endrule

    method Bool start_ready();
        return i == fromInteger(valueOf(n)/2 + 1);
    endmethod

    method Action start( Bit#(n) m, Bit#(n) r ) if (i == fromInteger(valueOf(n)/2 + 1));
        m_pos <= {msb(m), m, 0};
        m_neg <= {msb(-m), -m, 0};
        p <= {0, r, 1'b0};
        i <= 0;
    endmethod

    method Bool result_ready();
        return i == fromInteger(valueOf(n)/2);
    endmethod

    method ActionValue#(Bit#(TAdd#(n,n))) result() if (i == fromInteger(valueOf(n)/2));
        i <= i + 1;
        return p [(2*valueOf(n)):1];
    endmethod
endmodule
