# A first-version wlr-data-control client for the bench. OUT is where the
# tests build it, outside the source tree. The listeners take what the
# protocol hands them, most of it unused.
OUT ?= data-control-v1
PROTOCOL := wlr-data-control-unstable-v1
GENERATED := $(dir $(OUT))generated

all: $(OUT)

$(GENERATED)/$(PROTOCOL)-client-protocol.h: $(PROTOCOL).xml
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/$(PROTOCOL)-protocol.c: $(PROTOCOL).xml
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(OUT): client.c $(GENERATED)/$(PROTOCOL)-client-protocol.h $(GENERATED)/$(PROTOCOL)-protocol.c
	$(CC) -O2 -Wall -Wextra -Wno-unused-parameter -I$(GENERATED) client.c $(GENERATED)/$(PROTOCOL)-protocol.c -o $@ $(shell pkg-config --cflags --libs wayland-client)

.PHONY: all
