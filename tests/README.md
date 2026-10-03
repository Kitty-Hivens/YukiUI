# Tests

Behaviour tests for the shell, run against a real compositor.

```
cd tests
pytest
```

A run takes about a minute. It needs what the shell and its plugins need to
build and run, and a running Hyprland session to start from:

- `Hyprland` and `hyprctl`, the same version the session runs, with its headers
  (`pkg-config hyprland`), `make` and a C++ compiler, for the plugins
- `qs` (Quickshell)
- `wayland-scanner` and a C compiler, for the bench's pointer
- Python with `pytest`, PyGObject with GTK 4, and `python-xlib`

## What a run does

`bench/` starts a Hyprland of its own inside the session, with one headless
screen of 1920 by 1080 and 52 pixels reserved along the bottom where a dock
would stand. Nothing of the person's own is written: the config, data, state
and cache directories of the compositor and of everything started on it are
temporary ones under pytest's temporary directory, its plugins are built there
from `hypr-plugins/`, and the compositor rules are the experimental
environment's own file from this repository. The home folder is read, for
fonts and icons, and the session bus is the person's unless a test brings a
bus of its own, as the notification tests do. Its window on the session is
switched off, so nothing appears on the desktop. It is stopped at the end of
the run, and a start that fails halfway takes down what it had started.

On it run:

- the part of the shell under test, from a probe written into the shell's
  directory for the run and removed after it (`bench/shell.py`)
- windows the tests drive, a Wayland one through GTK 4 and an X11 one through
  python-xlib (`bench/clients/`). Each takes commands on its stdin, asks the
  compositor for what an application asks for, and says what it believes of
  itself, so a test sees a placement from the window's side as well as from the
  compositor's
- a pointer, a wlr-virtual-pointer device held for a whole test
  (`bench/pointer/`). A click drifts a pixel between press and release and a
  drag moves in small steps, as a hand does: a press and release in the same
  spot once hid a bug that every real mouse set off

Before each test the geometry memory is emptied and the compositor rules read
afresh. After it every window it opened is closed, and the test fails if the
shell logged a script error meanwhile.

## Tests

`core/` holds what every environment shares: how the shell hands the compositor
the rules of the environment that is up.

`experimental/` holds the experimental environment's: maximising, snapping by
the shell and with the mouse, minimising, the geometry memory, what X11
applications ask for, and the lock screen. The lock tests run on a compositor
of their own, since a session they lock cannot be unlocked again. The notification
tests run the shell under a session bus of its own, so its notification server
does not take the name from the live shell.
