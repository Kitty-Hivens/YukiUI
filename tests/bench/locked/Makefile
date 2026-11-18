# A fullscreen window that locks the pointer, for the bench. OUT is where the
# tests build it, outside the source tree. The listeners take what the
# protocols hand them, most of it unused.
OUT ?= locked
PROTOCOLS := $(shell pkg-config --variable=pkgdatadir wayland-protocols)
GENERATED := $(dir $(OUT))generated-locked

XDG_SHELL := $(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
CONSTRAINTS := $(PROTOCOLS)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml
RELATIVE := $(PROTOCOLS)/unstable/relative-pointer/relative-pointer-unstable-v1.xml

HEADERS := $(GENERATED)/xdg-shell-client-protocol.h $(GENERATED)/pointer-constraints-unstable-v1-client-protocol.h $(GENERATED)/relative-pointer-unstable-v1-client-protocol.h
SOURCES := $(GENERATED)/xdg-shell-protocol.c $(GENERATED)/pointer-constraints-unstable-v1-protocol.c $(GENERATED)/relative-pointer-unstable-v1-protocol.c

all: $(OUT)

$(GENERATED)/xdg-shell-client-protocol.h: $(XDG_SHELL)
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/xdg-shell-protocol.c: $(XDG_SHELL)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(GENERATED)/pointer-constraints-unstable-v1-client-protocol.h: $(CONSTRAINTS)
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/pointer-constraints-unstable-v1-protocol.c: $(CONSTRAINTS)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(GENERATED)/relative-pointer-unstable-v1-client-protocol.h: $(RELATIVE)
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/relative-pointer-unstable-v1-protocol.c: $(RELATIVE)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(OUT): client.c $(HEADERS) $(SOURCES)
	$(CC) -O2 -Wall -Wextra -Wno-unused-parameter -I$(GENERATED) client.c $(SOURCES) -o $@ $(shell pkg-config --cflags --libs wayland-client)

.PHONY: all
