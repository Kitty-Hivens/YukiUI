# A fullscreen window that locks the pointer, for the bench. OUT is where the
# tests build it, outside the source tree. The listeners take what the
# protocols hand them, most of it unused.
OUT ?= locked
PROTOCOLS := $(shell pkg-config --variable=pkgdatadir wayland-protocols)
GENERATED := $(dir $(OUT))generated-locked

all: $(OUT)

$(GENERATED)/xdg-shell-client-protocol.h: $(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/xdg-shell-protocol.c: $(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(GENERATED)/pointer-constraints-unstable-v1-client-protocol.h: $(PROTOCOLS)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/pointer-constraints-unstable-v1-protocol.c: $(PROTOCOLS)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(OUT): client.c $(GENERATED)/xdg-shell-client-protocol.h $(GENERATED)/xdg-shell-protocol.c $(GENERATED)/pointer-constraints-unstable-v1-client-protocol.h $(GENERATED)/pointer-constraints-unstable-v1-protocol.c
	$(CC) -O2 -Wall -Wextra -Wno-unused-parameter -I$(GENERATED) client.c $(GENERATED)/xdg-shell-protocol.c $(GENERATED)/pointer-constraints-unstable-v1-protocol.c -o $@ $(shell pkg-config --cflags --libs wayland-client)

.PHONY: all
