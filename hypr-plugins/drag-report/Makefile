# Built against the headers of the Hyprland that will load it, with the same
# compiler: the plugin API passes C++ objects and has no stable ABI.
#
# OUT lets the rebuild hook put the result somewhere other than the source
# directory, which is owned by the package and not written to.
OUT ?= drag-report.so
CXXFLAGS ?= -O2 -g
CXXFLAGS += -shared -fPIC --no-gnu-unique -std=c++2c -Wall -Wextra
# Every symbol resolved as the plugin is loaded, so one that is missing fails
# the load instead of ending the compositor at the first call that needs it.
LDFLAGS += -Wl,-z,now

all: $(OUT)

$(OUT): main.cpp
	$(CXX) $(CXXFLAGS) $< -o $@ $(shell pkg-config --cflags hyprland) $(LDFLAGS)

clean:
	rm -f drag-report.so

.PHONY: all clean
