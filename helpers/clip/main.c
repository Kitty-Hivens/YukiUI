// Puts something on the clipboard in several forms at once.
//
//     yuki-clip -f TYPE FILE -t TYPE TEXT ...
//
// Each form is its MIME type and either the file holding it, after -f, or the
// text itself, after -t. Given apart rather than joined by a separator: a
// type can carry parameters, "text/plain;charset=utf-8", and text can hold
// anything at all. A picture
// goes on as the picture and as the file it was saved to, say, so a program
// that takes pictures pastes the picture and one that takes files, a terminal
// or a game, pastes the file. wl-copy offers one form only.
//
// The files are read before anything else, so they can be removed as soon as
// this returns. It returns once the clipboard is set, and serves the forms
// from the background until something else is copied.
//
// Through ext-data-control, which lets a program without a window set the
// clipboard, as wl-copy does.

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <wayland-client.h>

#include "ext-data-control-v1-client-protocol.h"

struct form {
    const char *type;
    char *data;
    size_t size;
};

static struct form *forms;
static int formCount;

static struct wl_seat *seat;
static struct ext_data_control_manager_v1 *manager;
static int cancelled;

static void fail(const char *what) {
    fprintf(stderr, "yuki-clip: %s\n", what);
    exit(1);
}

static void readFile(const char *path, char **data, size_t *size) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "yuki-clip: cannot read %s: %s\n", path, strerror(errno));
        exit(1);
    }
    size_t capacity = 65536, length = 0;
    char *buffer = malloc(capacity);
    for (;;) {
        if (length == capacity) {
            capacity *= 2;
            buffer = realloc(buffer, capacity);
        }
        ssize_t got = read(fd, buffer + length, capacity - length);
        if (got < 0 && errno == EINTR)
            continue;
        if (got < 0) {
            fprintf(stderr, "yuki-clip: cannot read %s: %s\n", path, strerror(errno));
            exit(1);
        }
        if (got == 0)
            break;
        length += (size_t)got;
    }
    close(fd);
    *data = buffer;
    *size = length;
}

static void writeAll(int fd, const char *data, size_t size) {
    while (size > 0) {
        ssize_t put = write(fd, data, size);
        if (put < 0 && errno == EINTR)
            continue;
        if (put < 0)
            return;
        data += put;
        size -= (size_t)put;
    }
}

// Each paste is written by a process of its own, so a program that asks and
// never reads holds up nobody else's paste.
static void sourceSend(void *data, struct ext_data_control_source_v1 *source, const char *type, int32_t fd) {
    (void)data;
    (void)source;
    for (int i = 0; i < formCount; i++) {
        if (strcmp(forms[i].type, type) != 0)
            continue;
        pid_t child = fork();
        if (child == 0) {
            writeAll(fd, forms[i].data, forms[i].size);
            _exit(0);
        }
        break;
    }
    close(fd);
}

static void sourceCancelled(void *data, struct ext_data_control_source_v1 *source) {
    (void)data;
    (void)source;
    cancelled = 1;
}

static const struct ext_data_control_source_v1_listener sourceListener = {
    .send = sourceSend,
    .cancelled = sourceCancelled,
};

static void registryGlobal(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wl_seat_interface.name) == 0 && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, ext_data_control_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &ext_data_control_manager_v1_interface, 1);
}

static void registryGlobalRemove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registryListener = {
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

int main(int argc, char **argv) {
    if (argc < 4 || (argc - 1) % 3 != 0)
        fail("usage: yuki-clip -f TYPE FILE -t TYPE TEXT ...");

    forms = calloc((size_t)argc, sizeof *forms);
    for (int i = 1; i + 2 < argc; i += 3) {
        struct form *form = &forms[formCount++];
        form->type = argv[i + 1];
        if (strcmp(argv[i], "-f") == 0) {
            readFile(argv[i + 2], &form->data, &form->size);
        } else if (strcmp(argv[i], "-t") == 0) {
            form->data = argv[i + 2];
            form->size = strlen(argv[i + 2]);
        } else {
            fail("every form is -f TYPE FILE or -t TYPE TEXT");
        }
    }

    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
        fail("no Wayland display");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, NULL);
    wl_display_roundtrip(display);
    if (!seat)
        fail("no seat");
    if (!manager)
        fail("the compositor does not offer ext-data-control");

    struct ext_data_control_device_v1 *device = ext_data_control_manager_v1_get_data_device(manager, seat);
    struct ext_data_control_source_v1 *source = ext_data_control_manager_v1_create_data_source(manager);
    ext_data_control_source_v1_add_listener(source, &sourceListener, NULL);
    for (int i = 0; i < formCount; i++)
        ext_data_control_source_v1_offer(source, forms[i].type);
    ext_data_control_device_v1_set_selection(device, source);
    if (wl_display_roundtrip(display) < 0)
        fail("the compositor refused the clipboard");

    // Set, and from here on served in the background, so the caller can go
    // on. The writers are reaped as they finish.
    signal(SIGCHLD, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
    pid_t child = fork();
    if (child < 0)
        fail("cannot go to the background");
    if (child > 0)
        _exit(0);
    setsid();
    if (chdir("/") != 0)
        _exit(1);
    int null = open("/dev/null", O_RDWR);
    if (null >= 0) {
        dup2(null, STDIN_FILENO);
        dup2(null, STDOUT_FILENO);
        dup2(null, STDERR_FILENO);
        if (null > STDERR_FILENO)
            close(null);
    }

    while (!cancelled && wl_display_dispatch(display) >= 0)
        ;
    return 0;
}
