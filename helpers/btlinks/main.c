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
// This watches every controller's traffic, as btmon does, and as a connection
// a device opened completes, sends the controller the same Change Connection
// Packet Type the kernel sends for one it opens. It needs CAP_NET_RAW and runs
// as a service of the system.

#define _GNU_SOURCE

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif
#define BTPROTO_HCI 1
#define HCI_DEV_NONE 0xffff
#define HCI_CHANNEL_RAW 0
#define HCI_CHANNEL_MONITOR 2

// Monitor channel opcodes.
#define MONITOR_EVENT_PKT 0x0003
#define MONITOR_DEL_INDEX 0x0001

// HCI events and the command.
#define EVT_CONN_COMPLETE 0x03
#define EVT_CONN_REQUEST 0x04
#define LINK_ACL 0x01
#define OP_CHANGE_CONN_PTYPE ((0x01 << 10) | 0x000f)
// DM1, DH1, DM3, DH3, DM5 and DH5, every EDR packet allowed: what the kernel
// asks for as it opens a connection to a device that supports them all.
#define PACKET_TYPES 0xcc18

struct sockaddr_hci {
    sa_family_t hci_family;
    unsigned short hci_dev;
    unsigned short hci_channel;
};

struct monitor_header {
    uint16_t opcode;
    uint16_t index;
    uint16_t len;
} __attribute__((packed));

// Devices that asked to connect and have not finished, by controller.
#define PENDING 32
static struct {
    uint16_t index;
    uint8_t address[6];
    int used;
} pending[PENDING];

static void remember(uint16_t index, const uint8_t *address) {
    int slot = -1;
    for (int i = 0; i < PENDING; i++) {
        if (pending[i].used && pending[i].index == index && memcmp(pending[i].address, address, 6) == 0)
            return;
        if (!pending[i].used && slot < 0)
            slot = i;
    }
    // Full, the first goes: a request that never completed.
    if (slot < 0)
        slot = 0;
    pending[slot].used = 1;
    pending[slot].index = index;
    memcpy(pending[slot].address, address, 6);
}

/** Whether a device had asked to connect, and forgets it. */
static int take(uint16_t index, const uint8_t *address) {
    for (int i = 0; i < PENDING; i++) {
        if (pending[i].used && pending[i].index == index && memcmp(pending[i].address, address, 6) == 0) {
            pending[i].used = 0;
            return 1;
        }
    }
    return 0;
}

static void forget_controller(uint16_t index) {
    for (int i = 0; i < PENDING; i++)
        if (pending[i].index == index)
            pending[i].used = 0;
}

static void send_packet_types(uint16_t index, uint16_t handle, const uint8_t *address) {
    int sock = socket(AF_BLUETOOTH, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI);
    if (sock < 0) {
        fprintf(stderr, "yuki-btlinks: no HCI socket: %s\n", strerror(errno));
        return;
    }
    struct sockaddr_hci at = { AF_BLUETOOTH, index, HCI_CHANNEL_RAW };
    if (bind(sock, (struct sockaddr *)&at, sizeof(at)) < 0) {
        fprintf(stderr, "yuki-btlinks: hci%u: %s\n", index, strerror(errno));
        close(sock);
        return;
    }
    uint8_t command[8] = {
        0x01, OP_CHANGE_CONN_PTYPE & 0xff, OP_CHANGE_CONN_PTYPE >> 8, 4,
        handle & 0xff, (handle >> 8) & 0x0f, PACKET_TYPES & 0xff, PACKET_TYPES >> 8,
    };
    if (write(sock, command, sizeof(command)) != sizeof(command))
        fprintf(stderr, "yuki-btlinks: hci%u: could not send the packet types: %s\n", index, strerror(errno));
    else
        printf("hci%u: %02X:%02X:%02X:%02X:%02X:%02X connected to us, handle %u given packet types 0x%04x\n", index,
               address[5], address[4], address[3], address[2], address[1], address[0], handle, PACKET_TYPES);
    fflush(stdout);
    close(sock);
}

int main(void) {
    int monitor = socket(AF_BLUETOOTH, SOCK_RAW | SOCK_CLOEXEC, BTPROTO_HCI);
    if (monitor < 0) {
        fprintf(stderr, "yuki-btlinks: no HCI socket: %s\n", strerror(errno));
        return 1;
    }
    struct sockaddr_hci at = { AF_BLUETOOTH, HCI_DEV_NONE, HCI_CHANNEL_MONITOR };
    if (bind(monitor, (struct sockaddr *)&at, sizeof(at)) < 0) {
        fprintf(stderr, "yuki-btlinks: cannot watch the controllers: %s\n", strerror(errno));
        return 1;
    }

    uint8_t buffer[sizeof(struct monitor_header) + 1024];
    for (;;) {
        ssize_t length = recv(monitor, buffer, sizeof(buffer), 0);
        if (length < 0) {
            if (errno == EINTR)
                continue;
            fprintf(stderr, "yuki-btlinks: %s\n", strerror(errno));
            return 1;
        }
        if ((size_t)length < sizeof(struct monitor_header))
            continue;
        struct monitor_header header;
        memcpy(&header, buffer, sizeof(header));
        const uint8_t *packet = buffer + sizeof(header);
        size_t size = (size_t)length - sizeof(header);

        if (header.opcode == MONITOR_DEL_INDEX) {
            forget_controller(header.index);
            continue;
        }
        if (header.opcode != MONITOR_EVENT_PKT || size < 2)
            continue;
        uint8_t event = packet[0];
        const uint8_t *params = packet + 2;
        size_t plen = packet[1];
        if (plen > size - 2)
            continue;

        // A device asks to connect: bdaddr, class of device, link type.
        if (event == EVT_CONN_REQUEST && plen >= 10 && params[9] == LINK_ACL) {
            remember(header.index, params);
        }
        // The connection is up: status, handle, bdaddr, link type, encryption.
        else if (event == EVT_CONN_COMPLETE && plen >= 11) {
            const uint8_t *address = params + 3;
            int incoming = take(header.index, address);
            if (params[0] == 0 && params[9] == LINK_ACL && incoming) {
                uint16_t handle = params[1] | (params[2] << 8);
                send_packet_types(header.index, handle, address);
            }
        }
    }
}
