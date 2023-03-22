import FilterCoefficients::*;
import ClientServer::*;
import GetPut::*;
import FixedPoint::*;
import OverSampler::*;
import AudioProcessorTypes::*;
import Chunker::*;
import FFT::*;
import FIRFilter::*;
import Splitter::*;
import ConvertMagPhase::*;
import Complex::*;
import Vector::*;
import Overlayer::*;
import PitchAdjust::*;

typedef 16 I_SIZE;
typedef 16 F_SIZE;
typedef 8 N;
typedef 2 S;
typedef 2 FACTOR;
typedef 16 P_SIZE;

module mkAudioPipeline(SettableAudioProcessor#(I_SIZE, F_SIZE));
    AudioProcessor fir <- mkFIRFilter(c);
    Chunker#(S, Sample) chunker <- mkChunker();
    OverSampler#(S, N, Sample) overSampler <- mkOverSampler(replicate(0));
    FFT#(N,FixedPoint#(I_SIZE, P_SIZE)) fft <- mkFFT();
    ToMP#(N, I_SIZE, F_SIZE, P_SIZE) toMP <- mkToMP();
    SettablePitchAdjust#(N, I_SIZE, F_SIZE, P_SIZE) settablePitchAdjust <- mkPitchAdjust(valueOf(S));
    PitchAdjust#(N, I_SIZE, F_SIZE, P_SIZE) pitchAdjust = settablePitchAdjust.pitchAdjust;
    FromMP#(N, I_SIZE, F_SIZE, P_SIZE) fromMP <- mkFromMP();
    FFT#(N,FixedPoint#(I_SIZE, P_SIZE)) ifft <- mkIFFT();
    Overlayer#(N, S, Sample) overlayer <- mkOverlayer(replicate(0));
    Splitter#(S, Sample) splitter <- mkSplitter();

    rule fir_to_chunker (True);
        let x <- fir.getSampleOutput();
        // $display("fir_to_chunker: %d", x);
        chunker.request.put(x);
    endrule

    rule chunker_to_overSampler (True);
        let x <- chunker.response.get();
        // $display("chunker_to_overSampler: %d", x);
        overSampler.request.put(x);
    endrule

    rule overSampler_to_fft (True);
        let x <- overSampler.response.get();
        // $display("overSampler_to_fft: %d", x);
        Vector#(len, ComplexSample) res = replicate(unpack(0));
        for (Integer i = 0; i < valueOf(len); i = i + 1) begin
            res[i] = tocmplx(x[i]);
        end
        fft.request.put(res);
    endrule

    rule fft_to_ToMP (True);
        let x <- fft.response.get();
        // $display("fft_to_ToMP: %d", x);
        toMP.request.put(x);
    endrule

    rule toMP_to_pitchAdjust (True);
        let x <- toMP.response.get();
        // $display("toMP_to_pitchAdjust: %d", x);
        pitchAdjust.request.put(x);
    endrule

    rule pitchAdjust_to_fromMP (True);
        let x <- pitchAdjust.response.get();
        // $display("pitchAdjust_to_fromMP: %d", x);
        fromMP.request.put(x);
    endrule

    rule fromMP_to_ifft (True);
        let x <- fromMP.response.get();
        // $display("fromMP_to_ifft: %d", x);
        ifft.request.put(x);
    endrule

    rule ifft_to_overlayer (True);
        let x <- ifft.response.get();
        // $display("ifft_to_overlayer: %d", x);
        Vector#(len, Sample) res = replicate(unpack(0));
        for (Integer i = 0; i < valueOf(len); i = i + 1) begin
            res[i] = frcmplx(x[i]);
        end
        overlayer.request.put(res);
    endrule

    rule overlayer_to_splitter (True);
        let x <- overlayer.response.get();
        // $display("overlayer_to_splitter: %d", x);
        splitter.request.put(x);
    endrule

    interface AudioProcessor audioProcessor;
        method Action putSampleInput(Sample x);
            // $display("putSampleInput: %d", x);
            fir.putSampleInput(x);
        endmethod

        method ActionValue#(Sample) getSampleOutput();
            let x <- splitter.response.get();
            return x;
        endmethod
    endinterface

    interface Put setFactor;
        method Action put(FixedPoint#(I_SIZE, F_SIZE) x);
            settablePitchAdjust.setFactor.put(x);
        endmethod
    endinterface

endmodule
