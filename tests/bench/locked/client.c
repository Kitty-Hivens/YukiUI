// A fullscreen window that locks the pointer, as a game with raw input does.
//
// Asks for fullscreen, draws itself grey, and locks the pointer for as long
// as it lives once the pointer is over it. Prints one line for each thing
// that happens to it: "ready" once shown, "locked" and "unlocked", "button
// <code> <pressed|released>" for every press that reaches it, and "keyboard
// in" and "keyboard out" as it gains and loses the keyboard. It ends when its
// standard input closes or the compositor closes it.

#define _GNU_SOURCE

#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <wayland-client.h>

#include "pointer-constraints-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct wl_seat *seat;
static struct xdg_wm_base *wmBase;
static struct zwp_pointer_constraints_v1 *constraints;

static struct wl_surface *surface;
static struct xdg_surface *xdgSurface;
static struct xdg_toplevel *toplevel;
static int width = 640, height = 480;
static int closed;
static int shown;

static void say(const char *line) {
    printf("%s\n", line);
    fflush(stdout);
}

static void draw(void) {
    const int stride = width * 4;
    const int size = stride * height;
    int fd = memfd_create("bench-locked", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size) < 0)
        exit(1);
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    for (int i = 0; i < width * height; i++)
        pixels[i] = 0xff606060;
    munmap(pixels, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, width, height);
    wl_surface_commit(surface);
}

static void wmPing(void *data, struct xdg_wm_base *base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wmListener = {.ping = wmPing};

static void surfaceConfigure(void *data, struct xdg_surface *xdg, uint32_t serial) {
    xdg_surface_ack_configure(xdg, serial);
    draw();
    if (!shown) {
        shown = 1;
        say("ready");
    }
}
static const struct xdg_surface_listener surfaceListener = {.configure = surfaceConfigure};

static void toplevelConfigure(void *data, struct xdg_toplevel *top, int32_t w, int32_t h, struct wl_array *states) {
    if (w > 0 && h > 0) {
        width = w;
        height = h;
    }
}
static void toplevelClose(void *data, struct xdg_toplevel *top) {
    closed = 1;
}
static void toplevelBounds(void *data, struct xdg_toplevel *top, int32_t w, int32_t h) {}
static void toplevelCapabilities(void *data, struct xdg_toplevel *top, struct wl_array *caps) {}
static const struct xdg_toplevel_listener toplevelListener = {
    .configure = toplevelConfigure,
    .close = toplevelClose,
    .configure_bounds = toplevelBounds,
    .wm_capabilities = toplevelCapabilities,
};

static void locked(void *data, struct zwp_locked_pointer_v1 *lock) {
    say("locked");
}
static void unlocked(void *data, struct zwp_locked_pointer_v1 *lock) {
    say("unlocked");
}
static const struct zwp_locked_pointer_v1_listener lockListener = {.locked = locked, .unlocked = unlocked};

static void pointerEnter(void *data, struct wl_pointer *pointer, uint32_t serial, struct wl_surface *s, wl_fixed_t x, wl_fixed_t y) {}
static void pointerLeave(void *data, struct wl_pointer *pointer, uint32_t serial, struct wl_surface *s) {}
static void pointerMotion(void *data, struct wl_pointer *pointer, uint32_t time, wl_fixed_t x, wl_fixed_t y) {}
static void pointerButton(void *data, struct wl_pointer *pointer, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    char line[64];
    snprintf(line, sizeof line, "button %u %s", button, state == WL_POINTER_BUTTON_STATE_PRESSED ? "pressed" : "released");
    say(line);
}
static void pointerAxis(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis, wl_fixed_t value) {}
static void pointerFrame(void *data, struct wl_pointer *pointer) {}
static void pointerAxisSource(void *data, struct wl_pointer *pointer, uint32_t source) {}
static void pointerAxisStop(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis) {}
static void pointerAxisDiscrete(void *data, struct wl_pointer *pointer, uint32_t axis, int32_t discrete) {}
static const struct wl_pointer_listener pointerListener = {
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
    .frame = pointerFrame,
    .axis_source = pointerAxisSource,
    .axis_stop = pointerAxisStop,
    .axis_discrete = pointerAxisDiscrete,
};

static void keyboardKeymap(void *data, struct wl_keyboard *keyboard, uint32_t format, int32_t fd, uint32_t size) {
    close(fd);
}
static void keyboardEnter(void *data, struct wl_keyboard *keyboard, uint32_t serial, struct wl_surface *s, struct wl_array *keys) {
    say("keyboard in");
}
static void keyboardLeave(void *data, struct wl_keyboard *keyboard, uint32_t serial, struct wl_surface *s) {
    say("keyboard out");
}
static void keyboardKey(void *data, struct wl_keyboard *keyboard, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {}
static void keyboardModifiers(void *data, struct wl_keyboard *keyboard, uint32_t serial, uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {}
static void keyboardRepeat(void *data, struct wl_keyboard *keyboard, int32_t rate, int32_t delay) {}
static const struct wl_keyboard_listener keyboardListener = {
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeat,
};

static void registryGlobal(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 5);
    else if (strcmp(interface, xdg_wm_base_interface.name) == 0)
        wmBase = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    else if (strcmp(interface, zwp_pointer_constraints_v1_interface.name) == 0)
        constraints = wl_registry_bind(registry, name, &zwp_pointer_constraints_v1_interface, 1);
}
static void registryGlobalRemove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registryListener = {.global = registryGlobal, .global_remove = registryGlobalRemove};

int main(int argc, char **argv) {
    const char *appId = argc > 1 ? argv[1] : "bench.locked";
    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
        return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !seat || !wmBase || !constraints)
        return 1;
    xdg_wm_base_add_listener(wmBase, &wmListener, NULL);

    struct wl_pointer *pointer = wl_seat_get_pointer(seat);
    wl_pointer_add_listener(pointer, &pointerListener, NULL);
    struct wl_keyboard *keyboard = wl_seat_get_keyboard(seat);
    wl_keyboard_add_listener(keyboard, &keyboardListener, NULL);

    surface = wl_compositor_create_surface(compositor);
    xdgSurface = xdg_wm_base_get_xdg_surface(wmBase, surface);
    xdg_surface_add_listener(xdgSurface, &surfaceListener, NULL);
    toplevel = xdg_surface_get_toplevel(xdgSurface);
    xdg_toplevel_add_listener(toplevel, &toplevelListener, NULL);
    xdg_toplevel_set_app_id(toplevel, appId);
    xdg_toplevel_set_title(toplevel, appId);
    xdg_toplevel_set_fullscreen(toplevel, NULL);
    struct zwp_locked_pointer_v1 *lock = zwp_pointer_constraints_v1_lock_pointer(constraints, surface, pointer, NULL,
                                                                               ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT);
    zwp_locked_pointer_v1_add_listener(lock, &lockListener, NULL);
    wl_surface_commit(surface);

    struct pollfd fds[2] = {{.fd = wl_display_get_fd(display), .events = POLLIN}, {.fd = STDIN_FILENO, .events = POLLIN}};
    while (!closed) {
        wl_display_flush(display);
        if (poll(fds, 2, -1) < 0)
            break;
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            char buffer[64];
            if (read(STDIN_FILENO, buffer, sizeof buffer) <= 0)
                break;
        }
        if (fds[0].revents & POLLIN && wl_display_dispatch(display) < 0)
            break;
    }
    return 0;
}
