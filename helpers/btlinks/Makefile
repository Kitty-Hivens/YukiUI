# OUT lets the build script put the result somewhere other than the source
# directory, which is owned by the package and not written to.
OUT ?= yuki-btlinks
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -Wall -Wextra

all: $(OUT)

$(OUT): main.c
	$(CC) $(CFLAGS) main.c -o $@

clean:
	rm -f $(OUT)

.PHONY: all clean
