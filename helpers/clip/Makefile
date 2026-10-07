# OUT lets the build script put the result somewhere other than the source
# directory, which is owned by the package and not written to. The protocol
# code is generated next to the result for the same reason.
OUT ?= yuki-clip
GEN := $(dir $(abspath $(OUT)))
PROTOCOL := $(shell pkg-config --variable=pkgdatadir wayland-protocols)/staging/ext-data-control/ext-data-control-v1.xml
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra

all: $(OUT)

$(GEN)ext-data-control-v1-client-protocol.h: $(PROTOCOL)
	wayland-scanner client-header $< $@

$(GEN)ext-data-control-v1-protocol.c: $(PROTOCOL)
	wayland-scanner private-code $< $@

$(OUT): main.c $(GEN)ext-data-control-v1-client-protocol.h $(GEN)ext-data-control-v1-protocol.c
	$(CC) $(CFLAGS) -I$(GEN) main.c $(GEN)ext-data-control-v1-protocol.c -o $@ $(shell pkg-config --cflags --libs wayland-client)

clean:
	rm -f $(OUT) $(GEN)ext-data-control-v1-client-protocol.h $(GEN)ext-data-control-v1-protocol.c

.PHONY: all clean
