bscflags = -keep-fires -aggressive-conditions
bsvdir = ../common
build_dir = bscdir
synth_dir = /tmp/6375-lab1-${USER}

src = FIRFilter.bsv

compile: $(src)
	mkdir -p bscdir
	bsc -u -sim -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkTestDriver ../common/TestDriver.bsv

link: compile
	bsc -e mkTestDriver -sim -o ./out -simdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags)

simulation: link

verilog: $(src)
	mkdir -p bscdir
	bsc -u -verilog -elab -vdir $(build_dir) -bdir $(build_dir) -info-dir $(build_dir) $(bscflags) -p +:$(bsvdir) -g mkFIRFilter $^

synth: $(src)
	mkdir -p $(synth_dir)
	synth $^ mkFIRFilter -p $(bsvdir) -s $(synth_dir) -l multisize

clean:
	rm -rf bscdir out out.so