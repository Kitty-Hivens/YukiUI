# OUT lets the build script put the result somewhere other than the source
# directory, which is owned by the package and not written to.
OUT ?= yuki-tray
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra

all: $(OUT)

$(OUT): main.c
	$(CC) $(CFLAGS) main.c -o $@ $(shell pkg-config --cflags --libs gio-2.0)

clean:
	rm -f $(OUT)

.PHONY: all clean
