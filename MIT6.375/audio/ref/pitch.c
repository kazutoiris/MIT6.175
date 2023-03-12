
#include <complex.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include <fftw3.h>

// N - number of points in the fft.
// A value of 1024 (with S 64) gives a nice sounding output.
#define N 8

// S - Number of samples to shift each iteration
// overlap = N/S
#define S 2

// The amount to raise the pitch by
#define PITCH_FACTOR 2.0

// FIR Filter coefficients
#define NUM_TAPS 8
double coeffs[9] = {
    -0.0124, 0.0, -0.0133, 0.0, 0.8181, 0.0, -0.0133, 0.0, -0.0124
};

// Get the integer part from a double.
// This is meant to correspond to fxptGetInt in bluespec.
short getInt(double x)
{
    return x < 0 ? (short)(x-1) : (short)x;
}

// Given the next input to the fir filter, return the next output from the fir
// filter.
short fir(short sample)
{
    // taps persist accross calls to this function.
    static short taps[NUM_TAPS] = {0};

    double accumulate = coeffs[0] * (double)sample;
    int i;
    for (i = 0; i < NUM_TAPS; i++) {
        accumulate += coeffs[i+1] * (double)taps[i];
    }

    for (i = NUM_TAPS-1; i > 0; i--) {
        taps[i] = taps[i-1];
    }
    taps[0] = sample;

    return getInt(accumulate);
}

// Construct a complex number from magnitude and phase.
complex double cmplxmp(double mag, double phs)
{
    return mag * cexp(I*phs);
}

// Perform pitch adjustment on the given block of complex numbers..
void pitchadjust(complex double* in, complex double* out)
{
    // keep track of last rounds phases for each bin.
    // These persist accross calls to this function.
    static double inphases[N] = {0};
    static double outphases[N] = {0};

    bzero(out, sizeof(complex double) * N);

    int i;
    for (i = 0; i < N; i++) {
        double phase = carg(in[i]);
        double mag = cabs(in[i]);

        double dphase = phase - inphases[i];
        inphases[i] = phase;

        // Perform the adjustment
        // It's possible multiple different input bins could fall into the
        // same output bin, in which case we just use the last of those input
        // bins.
        int bin = i * PITCH_FACTOR;
        int nbin = (i+1) * PITCH_FACTOR;
        if (nbin != bin && bin >= 0 && bin < N) {
            double shifted = dphase * PITCH_FACTOR;
            outphases[bin] += shifted;
            out[bin] = cmplxmp(mag, outphases[bin]);
        }
    }
}

int main(int argc, char* argv[])
{
    if (argc != 3) {
        fprintf(stderr, "usage: inputpcm outputpcm\n");
        return 1;
    }

    const char* iname = argv[1];
    const char* oname = argv[2];

    FILE* fin = fopen(iname, "rb");
    FILE* fout = fopen(oname, "wb");

    // Set up the FFT.
    fftw_complex* infft = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * N);
    fftw_complex* outfft = (fftw_complex*) fftw_malloc(sizeof(fftw_complex) * N);
    fftw_plan forward = fftw_plan_dft_1d(N, infft, outfft, FFTW_FORWARD, FFTW_ESTIMATE);
    fftw_plan reverse = fftw_plan_dft_1d(N, infft, outfft, FFTW_BACKWARD, FFTW_ESTIMATE);

    // window - holds the window samples.
    // We shift through from right to left S samples at a time.
    short window[N] = {0};

    // outblock - holds the output samples we shift out from right to left.
    short outblock[N] = {0};

    int i;
    while (!feof(fin)) {

        // Read in the next S samples
        short samples[S];
        fread(samples, sizeof(short), S, fin);

        // Pass the samples through the fir filter.
        for (i = 0; i < S; i++) {
            samples[i] = fir(samples[i]);
        }

        // Shift input samples left by S and copy in the next S sample values.
        // (Oversampling)
        memmove(window, window + S, sizeof(short) * (N-S));
        memcpy(window + (N-S), samples, sizeof(short)*S); 

        // Convert audio samples to complex numbers
        for (i = 0; i < N; i++) {
            infft[i] = (double complex)window[i];
        }

        // Forward FFT
        fftw_execute(forward);

        // Pitch Adjustment.
        pitchadjust(outfft, infft);

        // Inverse FFT
        // We have to scale down by N because fftw doesn't for us.
        fftw_execute(reverse);
        for (i = 0; i < N; i++) {
            outfft[i] /= (double)N;
        }

        // Average in new samples with output block and shift out ready
        // samples. (Overlayer)
        for (i = 0; i < N; i++) {
            outblock[i] += (short)(creal(outfft[i])*S/(double)(N));
        }
        fwrite(outblock, sizeof(short), S, fout);
        memmove(outblock, outblock+S, sizeof(short) * (N-S));
        for (i = N-S; i < N; i++) {
            outblock[i] = 0;
        }
    }

    fftw_destroy_plan(forward);
    fftw_destroy_plan(reverse);
    fftw_free(infft);
    fftw_free(outfft);

    fclose(fin);
    fclose(fout);
}

