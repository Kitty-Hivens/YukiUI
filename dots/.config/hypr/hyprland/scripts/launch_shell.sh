#!/usr/bin/env bash
# Starts the shell, on Vulkan where Vulkan actually works.
#
# Qt Quick renders through OpenGL by default on Linux; QSG_RHI_BACKEND=vulkan is
# an explicit override and there is NO fallback -- with the variable set and no
# usable driver, Quickshell does not start slower, it crashes on launch and the
# session comes up with no shell at all. So the variable is only exported once a
# driver has answered.
#
# Called with the shell config name (what `qs -c` takes) as its only argument.
set -u

config="${1:-yuki}"
here="$(dirname "$(readlink -f "$0")")"

if python3 "$here/vulkan_supported.py" 2>/dev/null; then
    export QSG_RHI_BACKEND=vulkan
fi

# systemd-cat: the shell logs to stdout, and its own log under $XDG_RUNTIME_DIR
# keeps nothing once the process is gone abruptly. journald has each line the
# moment it is written. exec, so the unit's main process stays qs.
exec systemd-cat --identifier=quickshell qs --no-color -c "$config"
