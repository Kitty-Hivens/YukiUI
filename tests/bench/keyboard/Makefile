# The bench's keyboard. OUT is where the tests build it, outside the source tree.
# The listeners take what the protocol hands them, most of it unused.
OUT ?= keyboard
PROTOCOL := virtual-keyboard-unstable-v1
GENERATED := $(dir $(OUT))generated

all: $(OUT)

$(GENERATED)/$(PROTOCOL)-client-protocol.h: $(PROTOCOL).xml
	mkdir -p $(GENERATED)
	wayland-scanner client-header $< $@

$(GENERATED)/$(PROTOCOL)-protocol.c: $(PROTOCOL).xml
	mkdir -p $(GENERATED)
	wayland-scanner private-code $< $@

$(OUT): keyboard.c $(GENERATED)/$(PROTOCOL)-client-protocol.h $(GENERATED)/$(PROTOCOL)-protocol.c
	$(CC) -O2 -Wall -Wextra -Wno-unused-parameter -I$(GENERATED) keyboard.c $(GENERATED)/$(PROTOCOL)-protocol.c -o $@ $(shell pkg-config --cflags --libs wayland-client xkbcommon)

.PHONY: all
