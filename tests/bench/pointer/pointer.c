// A pointer for the nested test compositor, through wlr-virtual-pointer on
// whatever WAYLAND_DISPLAY names. One process is one pointer device for as long
// as it runs, so a button pressed by one command is released by a later one on
// the same device, the way a mouse holds it.
//
//   pointer OUTPUT
//
// then one command a line on stdin, each answered with "ok" once the
// compositor has had it, or "error ..." on stderr:
//
//   move X Y               pixels on OUTPUT
//   press [left|right|middle|side|extra|back|forward]
//   release [left|right|middle|side|extra|back|forward]
//
// A mouse sends its side buttons as side and extra, or as back and forward.
//   scroll DY
//
// It ends at the end of its input.
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_output *outputs[16];
static char *names[16];
static int widths[16], heights[16];
static int count;

static void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t subpixel,
                            const char *make, const char *model, int32_t transform) {}
static void output_mode(void *data, struct wl_output *output, uint32_t flags, int32_t width, int32_t height, int32_t refresh) {
    const long index = (long)data;
    if (flags & WL_OUTPUT_MODE_CURRENT) {
        widths[index] = width;
        heights[index] = height;
    }
}
static void output_done(void *data, struct wl_output *output) {}
static void output_scale(void *data, struct wl_output *output, int32_t factor) {}
static void output_name(void *data, struct wl_output *output, const char *name) { names[(long)data] = strdup(name); }
static void output_description(void *data, struct wl_output *output, const char *description) {}
static const struct wl_output_listener output_listener = {
    output_geometry, output_mode, output_done, output_scale, output_name, output_description,
};

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_seat_interface.name) == 0)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, version < 2 ? version : 2);
    else if (strcmp(interface, wl_output_interface.name) == 0 && count < 16 && version >= 4) {
        outputs[count] = wl_registry_bind(registry, name, &wl_output_interface, 4);
        wl_output_add_listener(outputs[count], &output_listener, (void *)(long)count);
        count++;
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, global_remove};

static struct wl_display *display;
static struct zwlr_virtual_pointer_v1 *pointer;
static int width, height;

static uint32_t now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int button_code(const char *name) {
    if (!name || strcmp(name, "left") == 0)
        return BTN_LEFT;
    if (strcmp(name, "right") == 0)
        return BTN_RIGHT;
    if (strcmp(name, "middle") == 0)
        return BTN_MIDDLE;
    if (strcmp(name, "side") == 0)
        return BTN_SIDE;
    if (strcmp(name, "extra") == 0)
        return BTN_EXTRA;
    if (strcmp(name, "back") == 0)
        return BTN_BACK;
    if (strcmp(name, "forward") == 0)
        return BTN_FORWARD;
    return -1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: pointer OUTPUT, then commands on stdin\n");
        return 2;
    }
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "error no display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    wl_display_roundtrip(display);
    if (!manager || !seat) {
        fprintf(stderr, "error no virtual pointer manager\n");
        return 1;
    }
    struct wl_output *output = NULL;
    for (int i = 0; i < count; i++)
        if (names[i] && strcmp(names[i], argv[1]) == 0) {
            output = outputs[i];
            width = widths[i];
            height = heights[i];
        }
    if (!output) {
        fprintf(stderr, "error no output %s\n", argv[1]);
        return 1;
    }
    pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(manager, seat, output);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);

    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        char command[32] = {0}, argument[32] = {0};
        int x = 0, y = 0;
        const int fields = sscanf(line, "%31s %31s", command, argument);
        if (fields < 1)
            continue;
        if (strcmp(command, "move") == 0 && sscanf(line, "move %d %d", &x, &y) == 2) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, width, height);
        } else if (strcmp(command, "press") == 0 || strcmp(command, "release") == 0) {
            const int code = button_code(fields > 1 ? argument : NULL);
            if (code < 0) {
                // Answered on stdout too: the bench waits for an answer to
                // every line, and one never given hung the run.
                printf("error unknown button %s\n", argument);
                fflush(stdout);
                continue;
            }
            zwlr_virtual_pointer_v1_button(pointer, now(), code,
                                           strcmp(command, "press") == 0 ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
        } else if (strcmp(command, "scroll") == 0 && fields > 1) {
            zwlr_virtual_pointer_v1_axis(pointer, now(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(atoi(argument)));
        } else {
            printf("error unknown command %s", line);
            fflush(stdout);
            continue;
        }
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        printf("ok\n");
        fflush(stdout);
    }

    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
