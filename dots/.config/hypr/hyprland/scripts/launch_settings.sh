#!/usr/bin/env bash
# Opens the shell's own settings window on one page.
#
#   launch_settings.sh [page] [surface]
#
# The running shell is asked first, and the environment that is up opens its
# own settings: each desktop has its own window, and only the shell knows which
# one is up. `surface` is "settings" by default, or "appearance" for the
# appearance settings. Without a shell to ask, Illogical Impulse's windows are
# opened directly, as before environments had settings of their own.
#
# A page name rather than a window, because the window is one process per
# invocation and decides what to show from its environment. Kept as a script so
# a bind can name a page without the environment assignment being mistaken for
# the command to look for.

set -u

page="${1:-}"
surface="${2:-settings}"
config="${qsConfig:-yuki}"

command -v qs >/dev/null 2>&1 || exit 1

if qs -c "$config" ipc call surfaces open "$surface" "$page" >/dev/null 2>&1; then
    exit 0
fi

if [[ "$surface" == "appearance" ]]; then
    setsid -f qs -p "$HOME/.config/quickshell/$config/appearanceSettings.qml" >/dev/null 2>&1
else
    YUKIUI_SETTINGS_PAGE="${page:-home}" setsid -f qs -p "$HOME/.config/quickshell/$config/systemSettings.qml" >/dev/null 2>&1
fi
