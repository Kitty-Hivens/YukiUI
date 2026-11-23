/*
 * A Wayland window that gives itself an icon through xdg-toplevel-icon-v1, for
 * the tests. Toolkits that do this, SDL3 among them, may give it before the
 * window is first shown, so this one can too.
 *
 *     icon-window APP_ID [name=ICON] [colour=RRGGBB] [size=N] [early] [minimized]
 *
 * name gives the icon a name from the theme, colour a picture of that colour,
 * N pixels square (48 unless said). early gives the icon before the window is
 * shown, after it otherwise. minimized asks to be minimised once configured and
 * before the window is shown, as Wine does for a window shown again from the
 * notification area, its Windows window still minimised then. Answers in a line of JSON each, as the other
 * clients of the bench do: {"ready": true} once shown with its icon given,
 * then one answer to each command it takes one a line on stdin:
 *
 *     unset    takes the icon back
 *     quit     ends, as does stdin closing
 */

#define _GNU_SOURCE
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"
#include "xdg-toplevel-icon-v1-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct xdg_toplevel_icon_manager_v1 *icon_manager;
static int configured;

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_compositor_interface.name) == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, wl_shm_interface.name) == 0)
        shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (strcmp(interface, xdg_wm_base_interface.name) == 0)
        wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
    else if (strcmp(interface, xdg_toplevel_icon_manager_v1_interface.name) == 0)
        icon_manager = wl_registry_bind(registry, name, &xdg_toplevel_icon_manager_v1_interface, 1);
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {registry_global, registry_global_remove};

static void wm_base_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {wm_base_ping};

static void surface_configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    xdg_surface_ack_configure(surface, serial);
    configured = 1;
}

static const struct xdg_surface_listener surface_listener = {surface_configure};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height, struct wl_array *states) {}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    exit(0);
}

static void toplevel_bounds(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height) {}

static void toplevel_capabilities(void *data, struct xdg_toplevel *toplevel, struct wl_array *capabilities) {}

static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure,
    .close = toplevel_close,
    .configure_bounds = toplevel_bounds,
    .wm_capabilities = toplevel_capabilities,
};

static void icon_size(void *data, struct xdg_toplevel_icon_manager_v1 *manager, int32_t size) {}

static void icon_done(void *data, struct xdg_toplevel_icon_manager_v1 *manager) {}

static const struct xdg_toplevel_icon_manager_v1_listener icon_manager_listener = {icon_size, icon_done};

/* A buffer of one colour, ARGB8888, opaque. */
static struct wl_buffer *solid_buffer(int width, int height, uint32_t colour) {
    const int stride = width * 4, size = stride * height;
    int fd = memfd_create("icon-window", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, size) < 0)
        return NULL;
    uint32_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED)
        return NULL;
    for (int i = 0; i < width * height; i++)
        pixels[i] = 0xff000000 | colour;
    munmap(pixels, size);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buffer;
}

static const char *icon_name;
static long icon_colour = -1;
static int icon_side = 48;

static void give_icon(struct xdg_toplevel *toplevel) {
    if (!icon_manager)
        return;
    struct xdg_toplevel_icon_v1 *icon = xdg_toplevel_icon_manager_v1_create_icon(icon_manager);
    if (icon_name)
        xdg_toplevel_icon_v1_set_name(icon, icon_name);
    if (icon_colour >= 0)
        xdg_toplevel_icon_v1_add_buffer(icon, solid_buffer(icon_side, icon_side, (uint32_t)icon_colour), 1);
    xdg_toplevel_icon_manager_v1_set_icon(icon_manager, toplevel, icon);
    xdg_toplevel_icon_v1_destroy(icon);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: icon-window APP_ID [name=ICON] [colour=RRGGBB] [size=N] [early] [minimized]\n");
        return 2;
    }
    int early = 0, minimized = 0;
    for (int i = 2; i < argc; i++) {
        if (strncmp(argv[i], "name=", 5) == 0)
            icon_name = argv[i] + 5;
        else if (strncmp(argv[i], "colour=", 7) == 0)
            icon_colour = strtol(argv[i] + 7, NULL, 16);
        else if (strncmp(argv[i], "size=", 5) == 0)
            icon_side = atoi(argv[i] + 5);
        else if (strcmp(argv[i], "early") == 0)
            early = 1;
        else if (strcmp(argv[i], "minimized") == 0)
            minimized = 1;
    }

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "no Wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm_base) {
        fprintf(stderr, "the compositor lacks what a window needs\n");
        return 1;
    }
    xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
    if (icon_manager)
        xdg_toplevel_icon_manager_v1_add_listener(icon_manager, &icon_manager_listener, NULL);

    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xsurface = xdg_wm_base_get_xdg_surface(wm_base, surface);
    xdg_surface_add_listener(xsurface, &surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xsurface);
    xdg_toplevel_add_listener(toplevel, &toplevel_listener, NULL);
    xdg_toplevel_set_app_id(toplevel, argv[1]);
    xdg_toplevel_set_title(toplevel, argv[1]);
    if (early)
        give_icon(toplevel);
    wl_surface_commit(surface);
    while (!configured && wl_display_dispatch(display) != -1) {
    }
    if (minimized)
        xdg_toplevel_set_minimized(toplevel);
    wl_surface_attach(surface, solid_buffer(300, 200, 0xffffff), 0, 0);
    wl_surface_commit(surface);
    wl_display_roundtrip(display);
    if (!early)
        give_icon(toplevel);
    wl_display_roundtrip(display);
    printf("{\"ready\": true, \"protocol\": %s}\n", icon_manager ? "true" : "false");
    fflush(stdout);

    struct pollfd fds[2] = {{.fd = wl_display_get_fd(display), .events = POLLIN}, {.fd = STDIN_FILENO, .events = POLLIN}};
    char line[64];
    for (;;) {
        wl_display_flush(display);
        if (poll(fds, 2, -1) < 0)
            break;
        if ((fds[0].revents & POLLIN) && wl_display_dispatch(display) == -1)
            break;
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            if (!fgets(line, sizeof line, stdin) || strncmp(line, "quit", 4) == 0)
                break;
            if (strncmp(line, "unset", 5) == 0 && icon_manager) {
                xdg_toplevel_icon_manager_v1_set_icon(icon_manager, toplevel, NULL);
                wl_display_roundtrip(display);
                printf("{\"ok\": \"unset\"}\n");
                fflush(stdout);
            }
        }
    }
    return 0;
}
