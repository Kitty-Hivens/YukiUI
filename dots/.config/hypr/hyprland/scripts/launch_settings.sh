#!/usr/bin/env bash
# Opens the shell's own settings window on one page.
#
#   launch_settings.sh [page] [surface]
#
# The running shell is asked first, and the environment that is up opens its
# own settings: each desktop has its own window, and only the shell knows which
# one is up. `surface` is "settings" by default, or "appearance" for the
# appearance settings. Without a shell to ask, the window of the environment the
# config names is opened directly, or of whichever one is installed: a desktop
# can be installed without the others, and Illogical Impulse's window, which
# used to be opened here for everybody, may not be on the disk.
#
# A page name rather than a window, because the window is one process per
# invocation and decides what to show from its environment. Kept as a script so
# a bind can name a page without the environment assignment being mistaken for
# the command to look for.

set -u

page="${1:-}"
surface="${2:-settings}"
config="${qsConfig:-yuki}"
root="$HOME/.config/quickshell/$config"

command -v qs >/dev/null 2>&1 || exit 1

if qs -c "$config" ipc call surfaces open "$surface" "$page" >/dev/null 2>&1; then
    exit 0
fi

family="$(python3 -c 'import json, sys
try:
    print(json.load(open(sys.argv[1])).get("panelFamily", ""))
except Exception:
    print("")' "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json" 2>/dev/null)"

open_blueberry() {
    [[ -f "$root/blueberrySettings.qml" ]] || return 1
    local start="$page"
    [[ -z "$start" && "$surface" == "appearance" ]] && start="personalization"
    YUKIUI_SETTINGS_PAGE="$start" setsid -f qs -n -p "$root/blueberrySettings.qml" >/dev/null 2>&1
}

open_ii() {
    if [[ "$surface" == "appearance" ]]; then
        [[ -f "$root/appearanceSettings.qml" ]] || return 1
        setsid -f qs -p "$root/appearanceSettings.qml" >/dev/null 2>&1
    else
        [[ -f "$root/systemSettings.qml" ]] || return 1
        YUKIUI_SETTINGS_PAGE="${page:-home}" setsid -f qs -p "$root/systemSettings.qml" >/dev/null 2>&1
    fi
}

case "$family" in
    blueberry) open_blueberry || open_ii ;;
    *) open_ii || open_blueberry ;;
esac
