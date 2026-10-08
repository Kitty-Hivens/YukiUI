// A clipboard client of the first version of wlr-data-control, as Wine's
// Wayland driver is one: it binds version 1 and handles the events of version
// 1 and no others. Sent the primary selection event of version 2, libwayland
// finds no handler for it and aborts, which is how Wine's clipboard died.
//
// Prints "ready" once its device is set up, and "selection" for every
// clipboard change it hears of, until it is killed.

#include <stdio.h>
#include <string.h>

#include <wayland-client.h>

#include "wlr-data-control-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwlr_data_control_manager_v1 *manager;

static void offerOffer(void *data, struct zwlr_data_control_offer_v1 *offer, const char *type) {}

static const struct zwlr_data_control_offer_v1_listener offerListener = {
    .offer = offerOffer,
};

static void deviceDataOffer(void *data, struct zwlr_data_control_device_v1 *device, struct zwlr_data_control_offer_v1 *offer) {
    zwlr_data_control_offer_v1_add_listener(offer, &offerListener, NULL);
}

static void deviceSelection(void *data, struct zwlr_data_control_device_v1 *device, struct zwlr_data_control_offer_v1 *offer) {
    if (offer)
        zwlr_data_control_offer_v1_destroy(offer);
    printf("selection\n");
    fflush(stdout);
}

static void deviceFinished(void *data, struct zwlr_data_control_device_v1 *device) {}

// The three events of version 1, as Wine has them, and no primary selection.
static const struct zwlr_data_control_device_v1_listener deviceListener = {
    .data_offer = deviceDataOffer,
    .selection = deviceSelection,
    .finished = deviceFinished,
};

static void registryGlobal(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, wl_seat_interface.name) == 0 && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, zwlr_data_control_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface, 1);
}

static void registryGlobalRemove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registryListener = {
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
        return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager)
        return 1;
    struct zwlr_data_control_device_v1 *device = zwlr_data_control_manager_v1_get_data_device(manager, seat);
    zwlr_data_control_device_v1_add_listener(device, &deviceListener, NULL);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);
    while (wl_display_dispatch(display) >= 0)
        ;
    return 2;
}
