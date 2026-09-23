"""Shared bits for the yuki xdg-desktop-portal backend.

One process owns org.freedesktop.impl.portal.desktop.yuki and registers every
interface the yuki family implements on the one object path below. The pieces
live in modules of their own (wallpaper, filechooser) and the entry point wires
them together, so this holds only what more than one of them needs.
"""

import sys

# Response codes of org.freedesktop.impl.portal.Request, the value every impl
# method hands back in its first out arg.
RESPONSE_SUCCESS = 0
RESPONSE_CANCELLED = 1
RESPONSE_FAILED = 2

# The single path xdg-desktop-portal talks to a desktop backend on.
OBJECT_PATH = "/org/freedesktop/portal/desktop"


def make_log(prefix):
    """A logger that tags its lines so one journal holds every interface."""

    def log(message):
        print(f"[{prefix}] {message}", file=sys.stderr, flush=True)

    return log
