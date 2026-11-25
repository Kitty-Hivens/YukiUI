/*
 * The power saving of the PCI Express links, changed and kept.
 *
 *     yuki-pcie set default|performance|powersave|powersupersave
 *
 * Run as root, by polkit's pkexec or sudo. Writes the kernel's ASPM policy,
 * which takes effect at once, and keeps it across restarts with a file for
 * systemd-tmpfiles, whatever the bootloader: "default" takes that file away.
 *
 * A link in a low power state takes a device that wakes badly with it: a disk
 * whose link timed out on every way out of it held a processor for 50 ms at a
 * time, which broke the sound. Turning the saving off for it stops that.
 *
 * The paths can be changed through YUKI_PCIE_POLICY and YUKI_PCIE_CONF, for the
 * tests, and only when not run as root.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *POLICY = "/sys/module/pcie_aspm/parameters/policy";
static const char *CONF = "/etc/tmpfiles.d/yuki-pcie.conf";

static const char *const NAMES[] = {"default", "performance", "powersave", "powersupersave"};

static int fail(const char *what) {
    fprintf(stderr, "yuki-pcie: %s: %s\n", what, strerror(errno));
    return 1;
}

/* Whether the kernel offers NAME, and, when `current` is set, whether it is the
 * one in use, which it shows in brackets. */
static int offered(const char *name, int current) {
    char text[256] = {0};
    int fd = open(POLICY, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    ssize_t got = read(fd, text, sizeof text - 1);
    close(fd);
    if (got <= 0)
        return 0;
    /* Alone in the file, as it stands in one written by a test, it is in use. */
    if (current && strcspn(text, " \n") == strlen(name) && strncmp(text, name, strlen(name)) == 0 && strchr(text, ' ') == NULL)
        return 1;
    for (char *save = NULL, *word = strtok_r(text, " \n", &save); word; word = strtok_r(NULL, " \n", &save)) {
        size_t length = strlen(word);
        int chosen = length > 2 && word[0] == '[' && word[length - 1] == ']';
        if (chosen) {
            word[length - 1] = '\0';
            word++;
        }
        if (strcmp(word, name) == 0)
            return current ? chosen : 1;
    }
    return 0;
}

static int apply(const char *name) {
    int fd = open(POLICY, O_WRONLY | O_TRUNC | O_CLOEXEC);
    if (fd < 0)
        return fail(POLICY);
    size_t length = strlen(name);
    if (write(fd, name, length) != (ssize_t)length) {
        close(fd);
        return fail("the kernel does not take it, the firmware may not let it be changed");
    }
    if (close(fd) != 0)
        return fail(POLICY);
    return 0;
}

static int keep(const char *name) {
    if (strcmp(name, "default") == 0)
        return unlink(CONF) != 0 && errno != ENOENT ? fail(CONF) : 0;

    char beside[4096];
    if (snprintf(beside, sizeof beside, "%s.new", CONF) >= (int)sizeof beside)
        return 1;
    /* The folder may not be there on a system without systemd-tmpfiles. */
    char folder[4096];
    snprintf(folder, sizeof folder, "%s", CONF);
    char *slash = strrchr(folder, '/');
    if (slash) {
        *slash = '\0';
        mkdir(folder, 0755);
    }
    int fd = open(beside, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0644);
    if (fd < 0)
        return fail(beside);
    char line[512];
    int size = snprintf(line, sizeof line, "# Set in YukiUI's settings, Power.\nw %s - - - - %s\n", "/sys/module/pcie_aspm/parameters/policy", name);
    int ok = write(fd, line, (size_t)size) == size && fchmod(fd, 0644) == 0;
    ok = close(fd) == 0 && ok;
    if (!ok || rename(beside, CONF) != 0) {
        unlink(beside);
        return fail(CONF);
    }
    return 0;
}

int main(int argc, char **argv) {
    /* Never from the environment of a process run as root. */
    if (geteuid() != 0) {
        if (getenv("YUKI_PCIE_POLICY"))
            POLICY = getenv("YUKI_PCIE_POLICY");
        if (getenv("YUKI_PCIE_CONF"))
            CONF = getenv("YUKI_PCIE_CONF");
    }
    if (argc != 3 || strcmp(argv[1], "set") != 0) {
        fprintf(stderr, "usage: yuki-pcie set default|performance|powersave|powersupersave\n");
        return 2;
    }
    const char *name = NULL;
    for (size_t i = 0; i < sizeof NAMES / sizeof *NAMES; i++)
        if (strcmp(argv[2], NAMES[i]) == 0)
            name = NAMES[i];
    if (!name) {
        fprintf(stderr, "yuki-pcie: %s is not one of default, performance, powersave and powersupersave\n", argv[2]);
        return 2;
    }
    if (!offered(name, 0)) {
        fprintf(stderr, "yuki-pcie: this kernel does not offer %s\n", name);
        return 1;
    }
    int status = apply(name);
    if (status)
        return status;
    if (!offered(name, 1)) {
        fprintf(stderr, "yuki-pcie: the kernel kept its own policy\n");
        return 1;
    }
    return keep(name);
}
