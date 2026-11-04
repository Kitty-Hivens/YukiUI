// A keyboard for the nested test compositor, through virtual-keyboard on
// whatever WAYLAND_DISPLAY names. It carries the plain us layout and sends the
// codes a real keyboard sends. wtype makes up a keymap of its own for each run,
// whose keycodes mean nothing elsewhere, and what reads the code of a key, the
// key event in lua, never sees the key it is looking for from it.
//
//   keyboard
//
// then one command a line on stdin, each answered with "ok" once the compositor
// has had it:
//
//   press CODE             an evdev key code, KEY_LEFTALT is 56
//   release CODE
//
// It ends at the end of its input.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "virtual-keyboard-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_seat_interface.name) == 0)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, zwp_virtual_keyboard_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, global_remove};

static uint32_t now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "error no display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager || !seat) {
        fprintf(stderr, "error no virtual keyboard manager\n");
        return 1;
    }

    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    const struct xkb_rule_names names = {.layout = "us"};
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    struct xkb_state *state = keymap ? xkb_state_new(keymap) : NULL;
    if (!state) {
        fprintf(stderr, "error no keymap\n");
        return 1;
    }
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    const size_t size = strlen(text) + 1;
    const int fd = memfd_create("bench-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t)size) {
        fprintf(stderr, "error no keymap file\n");
        return 1;
    }
    lseek(fd, 0, SEEK_SET);

    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);

    char line[256];
    while (fgets(line, sizeof line, stdin)) {
        char command[32] = {0};
        int code = 0;
        if (sscanf(line, "%31s %d", command, &code) != 2 || (strcmp(command, "press") != 0 && strcmp(command, "release") != 0)) {
            // Answered on stdout too: the bench waits for an answer to every line.
            printf("error unknown command %s", line);
            fflush(stdout);
            continue;
        }
        const int pressed = strcmp(command, "press") == 0;
        zwp_virtual_keyboard_v1_key(keyboard, now(), code, pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
        // xkb numbers its keys eight above evdev.
        xkb_state_update_key(state, code + 8, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);
        zwp_virtual_keyboard_v1_modifiers(keyboard, xkb_state_serialize_mods(state, XKB_STATE_MODS_DEPRESSED), xkb_state_serialize_mods(state, XKB_STATE_MODS_LATCHED),
                                          xkb_state_serialize_mods(state, XKB_STATE_MODS_LOCKED), xkb_state_serialize_layout(state, XKB_STATE_LAYOUT_EFFECTIVE));
        wl_display_roundtrip(display);
        printf("ok\n");
        fflush(stdout);
    }

    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
