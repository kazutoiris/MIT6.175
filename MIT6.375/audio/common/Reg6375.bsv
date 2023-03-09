import RevertingVirtualReg::*;
// mkReg and mkRegU replacemen for _write C _write
module mkReg#(t reset_val)(Reg#(t)) provisos (Bits#(t, tSz));
    Reg#(t) _r <- Prelude::mkReg(reset_val);
    // This reverting virtual reg is used to force _write C _write
    Reg#(Bool) double_write_error <- mkRevertingVirtualReg(True);
    method t _read;
        return _r._read;
    endmethod
    method Action _write(t x) if (double_write_error);
        double_write_error <= False;
        _r <= x;
    endmethod
endmodule

module mkRegU(Reg#(t)) provisos (Bits#(t, tSz));
    Reg#(t) _r <- Prelude::mkRegU;
    // This reverting virtual reg is used to force _write C _write
    Reg#(Bool) double_write_error <- mkRevertingVirtualReg(True);
    method t _read;
        return _r._read;
    endmethod
    method Action _write(t x) if (double_write_error);
        double_write_error <= False;
        _r <= x;
    endmethod
endmodule

interface BypassReg#(type t);
    method t oldValue;
    method t newValue;
    method Action _write(t x);
endinterface

module mkBypassReg#(t reset_val)(BypassReg#(t)) provisos (Bits#(t, tSz));
    Array#(Reg#(t)) _r <- mkCReg(2, reset_val);
    // This reverting virtual reg is used to force _write C _write
    Reg#(Bool) double_write_error <- mkRevertingVirtualReg(True);
    method t oldValue;
        return _r[0];
    endmethod
    method t newValue;
        return _r[1];
    endmethod
    method Action _write(t x) if (double_write_error);
        double_write_error <= False;
        _r[0] <= x;
    endmethod
endmodule

