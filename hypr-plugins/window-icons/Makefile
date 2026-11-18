# Built against the headers of the Hyprland that will load it, with the same
# compiler: the plugin API passes C++ objects and has no stable ABI.
#
# OUT lets the rebuild hook put the result somewhere other than the source
# directory, which is owned by the package and not written to. The protocol's
# generated code goes beside it for the same reason.
OUT ?= window-icons.so
PROTOCOL := xdg-toplevel-icon-v1
PROTOCOL_XML := $(shell pkg-config --variable=pkgdatadir wayland-protocols)/staging/xdg-toplevel-icon/$(PROTOCOL).xml
GENERATED := $(dir $(abspath $(OUT)))generated-window-icons
CXXFLAGS ?= -O2 -g
CXXFLAGS += -shared -fPIC --no-gnu-unique -std=c++2c -Wall -Wextra
CFLAGS ?= -O2 -g
CFLAGS += -fPIC
# Every symbol resolved as the plugin is loaded, so one that is missing fails
# the load instead of ending the compositor at the first call that needs it.
LDFLAGS += -Wl,-z,now

all: $(OUT)

$(GENERATED)/$(PROTOCOL)-server-protocol.h: $(PROTOCOL_XML)
	mkdir -p $(GENERATED)
	wayland-scanner server-header $< $@

$(GENERATED)/$(PROTOCOL)-protocol.o: $(PROTOCOL_XML)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $(GENERATED)/$(PROTOCOL)-protocol.c
	$(CC) $(CFLAGS) -c $(GENERATED)/$(PROTOCOL)-protocol.c -o $@ $(shell pkg-config --cflags wayland-server)

$(OUT): main.cpp $(GENERATED)/$(PROTOCOL)-server-protocol.h $(GENERATED)/$(PROTOCOL)-protocol.o
	$(CXX) $(CXXFLAGS) -I$(GENERATED) main.cpp $(GENERATED)/$(PROTOCOL)-protocol.o -o $@ $(shell pkg-config --cflags hyprland cairo) $(shell pkg-config --libs cairo) $(LDFLAGS)

clean:
	rm -f $(OUT)
	rm -rf $(GENERATED)

.PHONY: all clean
