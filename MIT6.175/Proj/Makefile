CONNECTALDIR ?= /home/adam/connectal
S2H_INTERFACES = \
	ConnectalProcRequest:ConnectalWrapper.connectProc\
	ConnectalMemoryInitialization:ConnectalWrapper.initProc
H2S_INTERFACES = \
	ConnectalWrapper:ConnectalProcIndication

BSVFILES += \
	src/includes/Ifc.bsv
BSVPATH += / \
	src/ \
	src/includes \
	src/ref \
	$(CONNECTALDIR)/bsv
CPPFILES += \
	main.cpp\
	Platform.cpp

C_LIB_DIR = src/ref

#CONNECTALFLAGS += --mainclockperiod=20
#CONNECTALFLAGS += --verilog=ddr3_v2_0/

SOFTWARE_SOCKET_NAME=/tmp/connectal$(USER)
export SOFTWARE_SOCKET_NAME



CONNECTALFLAGS += -D CORE_NUM=$(CORENUM)
CONNECTALFLAGS += -D $(CORE)
CONNECTALFLAGS += -D $(CACHE)

CONNECTALFLAGS += --bscflags " -I $(C_LIB_DIR)"
CONNECTALFLAGS += --bscflags " -L $(C_LIB_DIR)"

CONNECTALFLAGS += --bscflags " -D CORE_NUM=$(CORENUM) -D $(CORE) -D $(CACHE) -steps-max-intervals 50 +RTS -K256M -RTS"
CONNECTALFLAGS += --bscflags " -show-schedule"
CONNECTALFLAGS += --cxxflags="-g -std=gnu++11"

include $(CONNECTALDIR)/Makefile.connectal


clean:
	rm -rf bluesim

