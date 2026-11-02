// Gives Bluetooth connections a device makes to this machine the packet
// types the kernel gives connections it makes itself.
//
//     yuki-btlinks
//
// Linux tells the controller which baseband packets a link may use, and with
// them whether the faster EDR ones are allowed, when it opens a connection
// itself. For one a device opens to it, it leaves that to the controller's
// defaults, telling only controllers older than Bluetooth 2.0. Some
// controllers then keep such a link on basic rate packets, which tops out at
// about 700 kbit/s: a headset that connects on its own as it is switched on
// plays LDAC, which needs more, through a link that cannot carry it, and the
// sound breaks up, while the same headset connected from here is clean.
//
// As a connection a device opened completes, this sends the controller the
// same Change Connection Packet Type the kernel sends for one it opens. On a
// controller that allowed those packets already, nothing changes.
//
// It sees nothing of what goes over the links. Each controller is read through
// a socket the kernel filters down to the two events wanted, a device asking
// to connect and a connection completing, and controllers coming and going
// are heard from the kernel's own notices, so it sleeps until one of those
// happens. It needs CAP_NET_RAW and runs as a service of the system.

#define _GNU_SOURCE

#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif
#define BTPROTO_HCI 1
#define SOL_HCI 0
#define HCI_FILTER 2
#define HCI_DEV_NONE 0xffff
#define HCI_CHANNEL_RAW 0
#define HCIGETDEVLIST _IOR('H', 210, int)

#define HCI_EVENT_PKT 0x04
#define EVT_CONN_COMPLETE 0x03
#define EVT_CONN_REQUEST 0x04
// The kernel's notice of a controller registered, gone, up or down, given to
// sockets bound to no controller.
#define EVT_STACK_INTERNAL 0xfd
#define EVT_SI_DEVICE 0x01
#define HCI_DEV_REG 1
#define HCI_DEV_UNREG 2
#define HCI_DEV_UP 3

#define LINK_ACL 0x01
#define OP_CHANGE_CONN_PTYPE ((0x01 << 10) | 0x000f)
// DM1, DH1, DM3, DH3, DM5 and DH5, every EDR packet allowed: what the kernel
// asks for as it opens a connection to a device that supports them all.
#define PACKET_TYPES 0xcc18

// Looked at again this often should a notice of a controller be missed.
#define RESCAN_MS 30000
#define CONTROLLERS 8
#define PENDING 16

struct sockaddr_hci {
    sa_family_t hci_family;
    unsigned short hci_dev;
    unsigned short hci_channel;
};

struct hci_filter {
    uint32_t type_mask;
    uint32_t event_mask[2];
    uint16_t opcode;
};

struct hci_dev_req {
    uint16_t dev_id;
    uint32_t dev_opt;
};

struct hci_dev_list_req {
    uint16_t dev_num;
    struct hci_dev_req dev_req[CONTROLLERS];
};

static struct controller {
    int fd;
    uint16_t id;
    // Devices that asked to connect and have not finished.
    uint8_t pending[PENDING][6];
    int pendingUsed[PENDING];
} controllers[CONTROLLERS];

static void filter_events(struct hci_filter *filter, const uint8_t *events, int count) {
    memset(filter, 0, sizeof(*filter));
    filter->type_mask = 1u << HCI_EVENT_PKT;
    for (int i = 0; i < count; i++) {
        int bit = events[i] & 63;
        filter->event_mask[bit >> 5] |= 1u << (bit & 31);
    }
}

static int open_raw(uint16_t id, const uint8_t *events, int count) {
    int fd = socket(AF_BLUETOOTH, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI);
    if (fd < 0)
        return -1;
    struct sockaddr_hci at = { AF_BLUETOOTH, id, HCI_CHANNEL_RAW };
    struct hci_filter filter;
    filter_events(&filter, events, count);
    if (bind(fd, (struct sockaddr *)&at, sizeof(at)) < 0 || setsockopt(fd, SOL_HCI, HCI_FILTER, &filter, sizeof(filter)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static struct controller *find(uint16_t id) {
    for (int i = 0; i < CONTROLLERS; i++)
        if (controllers[i].fd >= 0 && controllers[i].id == id)
            return &controllers[i];
    return NULL;
}

static void watch(uint16_t id) {
    if (find(id))
        return;
    for (int i = 0; i < CONTROLLERS; i++) {
        if (controllers[i].fd >= 0)
            continue;
        static const uint8_t events[] = { EVT_CONN_REQUEST, EVT_CONN_COMPLETE };
        int fd = open_raw(id, events, 2);
        if (fd < 0) {
            fprintf(stderr, "yuki-btlinks: cannot watch hci%u: %s\n", id, strerror(errno));
            return;
        }
        memset(&controllers[i], 0, sizeof(controllers[i]));
        controllers[i].fd = fd;
        controllers[i].id = id;
        printf("watching hci%u\n", id);
        fflush(stdout);
        return;
    }
}

static void unwatch(struct controller *controller) {
    close(controller->fd);
    controller->fd = -1;
}

/** Every controller there is now, watched. */
static void rescan(int any) {
    struct hci_dev_list_req list = { .dev_num = CONTROLLERS };
    if (ioctl(any, HCIGETDEVLIST, &list) < 0)
        return;
    for (int i = 0; i < list.dev_num && i < CONTROLLERS; i++)
        watch(list.dev_req[i].dev_id);
}

static void remember(struct controller *c, const uint8_t *address) {
    int slot = -1;
    for (int i = 0; i < PENDING; i++) {
        if (c->pendingUsed[i] && memcmp(c->pending[i], address, 6) == 0)
            return;
        if (!c->pendingUsed[i] && slot < 0)
            slot = i;
    }
    // Full, the first goes: a request that never completed.
    if (slot < 0)
        slot = 0;
    c->pendingUsed[slot] = 1;
    memcpy(c->pending[slot], address, 6);
}

/** Whether a device had asked to connect, and forgets it. */
static int take(struct controller *c, const uint8_t *address) {
    for (int i = 0; i < PENDING; i++) {
        if (c->pendingUsed[i] && memcmp(c->pending[i], address, 6) == 0) {
            c->pendingUsed[i] = 0;
            return 1;
        }
    }
    return 0;
}

static void send_packet_types(struct controller *c, uint16_t handle, const uint8_t *address) {
    uint8_t command[8] = {
        0x01, OP_CHANGE_CONN_PTYPE & 0xff, OP_CHANGE_CONN_PTYPE >> 8, 4,
        handle & 0xff, (handle >> 8) & 0x0f, PACKET_TYPES & 0xff, PACKET_TYPES >> 8,
    };
    if (write(c->fd, command, sizeof(command)) != sizeof(command))
        fprintf(stderr, "yuki-btlinks: hci%u: could not send the packet types: %s\n", c->id, strerror(errno));
    else
        printf("hci%u: %02X:%02X:%02X:%02X:%02X:%02X connected to us, handle %u given packet types 0x%04x\n", c->id,
               address[5], address[4], address[3], address[2], address[1], address[0], handle, PACKET_TYPES);
    fflush(stdout);
}

/** One event of a controller: the packet type, the event, its length and what it carries. */
static void on_event(struct controller *c, const uint8_t *packet, size_t size) {
    if (size < 3 || packet[0] != HCI_EVENT_PKT)
        return;
    uint8_t event = packet[1];
    size_t plen = packet[2];
    const uint8_t *params = packet + 3;
    if (plen > size - 3)
        return;
    // A device asks to connect: its address, class of device, link type.
    if (event == EVT_CONN_REQUEST && plen >= 10 && params[9] == LINK_ACL)
        remember(c, params);
    // The connection is up: status, handle, address, link type, encryption.
    else if (event == EVT_CONN_COMPLETE && plen >= 11) {
        const uint8_t *address = params + 3;
        int incoming = take(c, address);
        if (params[0] == 0 && params[9] == LINK_ACL && incoming)
            send_packet_types(c, params[1] | (params[2] << 8), address);
    }
}

int main(void) {
    for (int i = 0; i < CONTROLLERS; i++)
        controllers[i].fd = -1;

    static const uint8_t notices[] = { EVT_STACK_INTERNAL };
    int any = open_raw(HCI_DEV_NONE, notices, 1);
    if (any < 0) {
        fprintf(stderr, "yuki-btlinks: no HCI socket: %s\n", strerror(errno));
        return 1;
    }
    rescan(any);

    uint8_t packet[260];
    for (;;) {
        struct pollfd fds[CONTROLLERS + 1];
        struct controller *of[CONTROLLERS + 1];
        int n = 0;
        fds[n] = (struct pollfd){ .fd = any, .events = POLLIN };
        of[n++] = NULL;
        for (int i = 0; i < CONTROLLERS; i++) {
            if (controllers[i].fd < 0)
                continue;
            fds[n] = (struct pollfd){ .fd = controllers[i].fd, .events = POLLIN };
            of[n++] = &controllers[i];
        }

        int ready = poll(fds, n, RESCAN_MS);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            fprintf(stderr, "yuki-btlinks: %s\n", strerror(errno));
            return 1;
        }
        if (ready == 0) {
            rescan(any);
            continue;
        }

        for (int i = 0; i < n; i++) {
            if (!fds[i].revents)
                continue;
            ssize_t got = (fds[i].revents & POLLIN) ? recv(fds[i].fd, packet, sizeof(packet), MSG_DONTWAIT) : -1;
            if (of[i] == NULL) {
                // A controller registered or up is watched, one gone is let go.
                // The notice: its type, then what happened and to which
                // controller, two bytes each.
                if (got >= 9 && packet[1] == EVT_STACK_INTERNAL && (packet[3] | (packet[4] << 8)) == EVT_SI_DEVICE) {
                    uint16_t what = packet[5] | (packet[6] << 8);
                    uint16_t id = packet[7] | (packet[8] << 8);
                    struct controller *c = find(id);
                    if (what == HCI_DEV_UNREG && c)
                        unwatch(c);
                    else if (what == HCI_DEV_REG || what == HCI_DEV_UP)
                        watch(id);
                }
                continue;
            }
            // Gone underneath its socket, as a controller reset over USB is.
            if (got < 0 && errno != EAGAIN && errno != EINTR) {
                printf("hci%u gone\n", of[i]->id);
                fflush(stdout);
                unwatch(of[i]);
                continue;
            }
            if (got > 0)
                on_event(of[i], packet, (size_t)got);
        }
    }
}
