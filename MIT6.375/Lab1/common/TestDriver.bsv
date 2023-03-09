
import Counter::*;

import FIRFilter::*;
import AudioProcessorTypes::*;

(* synthesize *)
module mkTestDriver (Empty);

    AudioProcessor pipeline <- mkFIRFilter();

    Reg#(File) m_in <- mkRegU();
    Reg#(File) m_out <- mkRegU();

    Reg#(Bool) m_inited <- mkReg(False);
    Reg#(Bool) m_doneread <- mkReg(False);

    Counter#(32) m_outstanding <- mkCounter(0);

    rule init(!m_inited);
        m_inited <= True;

        File in <- $fopen("in.pcm", "rb");
        if (in == InvalidFile) begin
            $display("couldn't open in.pcm");
            $finish;
        end
        m_in <= in;

        File out <- $fopen("out.pcm", "wb");
        if (out == InvalidFile) begin
            $display("couldn't open out.pcm for write");
            $finish;
        end
        m_out <= out;
    endrule

    rule read(m_inited && !m_doneread && m_outstanding.value() != maxBound);
        int a <- $fgetc(m_in);
        int b <- $fgetc(m_in);

        if (a == -1 || b == -1) begin
            m_doneread <= True;
            $fclose(m_in);
        end else begin
            Bit#(8) a8 = truncate(pack(a));
            Bit#(8) b8 = truncate(pack(b));

            // Input is little endian. That means the first byte we read (a8)
            // is the least significant byte in the sample.
            pipeline.putSampleInput(unpack({b8, a8}));
            m_outstanding.up();
        end
    endrule

    rule write(m_inited);
        Sample d <- pipeline.getSampleOutput();
        m_outstanding.down();

        // Little endian: first thing out is least significant.
        Bit#(8) a8 = pack(d)[7:0];
        Bit#(8) b8 = pack(d)[15:8];
        $fwrite(m_out, "%c", a8);
        $fwrite(m_out, "%c", b8);
    endrule

    rule finish(m_doneread && m_outstanding.value() == 0);
        $fclose(m_out);
        $finish();
    endrule

endmodule

