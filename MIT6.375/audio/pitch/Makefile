bscflags = -keep-fires -aggressive-conditions -Xc++ -D_GLIBCXX_USE_CXX11_ABI=0
bsvdir = ../common:../fir:../fft
build_dir = bscdir
synth_dir = /tmp/6375-lab3-${USER}

src = PitchAdjust.bsv PitchAdjustTest.bsv $(wildcard ../common/*.bsv) $(wildcard ../fft/*.bsv) $(wildcard ../fir/*.bsv) 


PitchAdjust: PitchAdjust.bsv PitchAdjustTest.bsv
	mkdir -p bscdir
	bsc -u -sim -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkPitchAdjustTest PitchAdjustTest.bsv
	bsc -e mkPitchAdjustTest -sim -o $@ -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags)	
AudioPipeline: $(src)
	mkdir -p bscdir
	bsc -u -sim -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkTestDriver ../common/TestDriver.bsv
	bsc -e mkTestDriver -sim -o $@ -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags)

synthAudioPipeline: $(src)
	mkdir -p $(synth_dir)
	synth ../common/AudioPipeline.bsv mkAudioPipeline -p $(bsvdir) -s $(synth_dir) -l multisize

clean:
	rm -rf bscdir PitchAdjust AudioPipeline *.so
