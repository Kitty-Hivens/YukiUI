#!/usr/bin/env bash
# Opens the shell's own settings window on one page.
#
# A page name rather than a window, because the window is one process per
# invocation and decides what to show from its environment. Kept as a script so
# a bind can name a page without the environment assignment being mistaken for
# the command to look for.

set -u

page="${1:-home}"
config="${qsConfig:-yuki}"

command -v qs >/dev/null 2>&1 || exit 1
YUKIUI_SETTINGS_PAGE="$page" setsid -f qs -p "$HOME/.config/quickshell/$config/systemSettings.qml" >/dev/null 2>&1
