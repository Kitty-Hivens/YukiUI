# A Wayland window that gives its own icon. OUT is where the tests build it,
# outside the source tree.
OUT ?= icon-window
PROTOCOLS := $(shell pkg-config --variable=pkgdatadir wayland-protocols)
SHELL_XML := $(PROTOCOLS)/stable/xdg-shell/xdg-shell.xml
ICON_XML := $(PROTOCOLS)/staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml
GENERATED := $(dir $(abspath $(OUT)))generated-icon-window

all: $(OUT)

$(GENERATED)/xdg-shell-client-protocol.h: $(SHELL_XML)
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/xdg-shell-protocol.c: $(SHELL_XML)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(GENERATED)/xdg-toplevel-icon-v1-client-protocol.h: $(ICON_XML)
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/xdg-toplevel-icon-v1-protocol.c: $(ICON_XML)
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(OUT): icon_window.c $(GENERATED)/xdg-shell-client-protocol.h $(GENERATED)/xdg-shell-protocol.c $(GENERATED)/xdg-toplevel-icon-v1-client-protocol.h $(GENERATED)/xdg-toplevel-icon-v1-protocol.c
	$(CC) -O2 -Wall -Wextra -Wno-unused-parameter -I$(GENERATED) icon_window.c $(GENERATED)/xdg-shell-protocol.c $(GENERATED)/xdg-toplevel-icon-v1-protocol.c -o $@ $(shell pkg-config --cflags --libs wayland-client)

.PHONY: all
