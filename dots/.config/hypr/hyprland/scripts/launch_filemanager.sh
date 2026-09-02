#!/usr/bin/env bash
# File-manager launcher for the Win+E bind.
#
# The application is the one the system is set to open directories with, which
# is what the shell's own settings page writes. The list passed in is only what
# is left when nothing is set at all.
#
# It used to be the list alone, with the D-Bus path below taken for nautilus by
# name. That ignored the choice made in the settings, and it meant installing an
# unrelated package that happened to be named earlier could change which file
# manager the key opened.

set -u
source "$(dirname "$(readlink -f "$0")")/launcher-lib.sh"

FM_URI="file://$HOME"
FM_TIMEOUT=8

# The binary behind a desktop entry's Exec, or behind a D-Bus service file's.
exec_binary() {
    local line
    line=$(sed -n 's/^Exec=//p' "$1" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 1
    basename "${line%% *}"
}

filemanager1_service() {
    local dir
    local -a roots
    IFS=':' read -r -a roots <<< "${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${roots[@]}"; do
        [[ -n "$dir" && -f "$dir/dbus-1/services/org.freedesktop.FileManager1.service" ]] || continue
        printf '%s\n' "$dir/dbus-1/services/org.freedesktop.FileManager1.service"
        return 0
    done
    return 1
}

# Whether the application set to open directories is the one behind the
# FileManager1 interface.
#
# Asked about the interface rather than about a name: FileManager1 is a
# freedesktop interface and several file managers implement it, so the window
# reuse and the recovery below should not belong to whichever one the code was
# written against. But the service name belongs to whoever registered it, which
# need not be the manager the person chose, so going in that way is only correct
# when the two are the same application.
chosen_owns_filemanager1() {
    local desktop="$1" service
    service=$(filemanager1_service) || return 1
    [[ "$(exec_binary "$service")" == "$(exec_binary "$desktop")" ]]
}

# Opens/presents a window through the running (or D-Bus-activated) manager.
# Returns non-zero if the primary does not answer within FM_TIMEOUT, i.e. it is
# wedged -- a healthy instance replies in well under a second even while its
# background threads are busy generating thumbnails.
show_folder() {
    gdbus call --session --timeout "$FM_TIMEOUT" \
        --dest org.freedesktop.FileManager1 \
        --object-path /org/freedesktop/FileManager1 \
        --method org.freedesktop.FileManager1.ShowFolders \
        "['$FM_URI']" "" >/dev/null 2>&1
}

# A single-instance manager holds the bus name, so a busy or crashed primary
# makes every re-launch block on that primary's main loop -- which is exactly
# the "Win+E hangs for a long time" symptom. The window is opened through a
# bounded call; if it does not answer in time the instance is stuck, so it is
# torn down and started clean.
open_via_filemanager1() {
    local binary="$1"

    # ShowFolders both activates a cold manager and reuses a warm one, so the
    # happy path is a single bounded call.
    show_folder && return 0

    pkill -x "$binary" 2>/dev/null
    for _ in $(seq 1 10); do
        pgrep -x "$binary" >/dev/null 2>&1 || break
        sleep 0.2
    done
    pgrep -x "$binary" >/dev/null 2>&1 && pkill -9 -x "$binary" 2>/dev/null

    # Re-activate via the bus; fall back to a direct spawn if that still fails.
    show_folder && return 0
    setsid -f "$binary" >/dev/null 2>&1
}

chosen=$(xdg-mime query default inode/directory 2>/dev/null)
if [[ -n "$chosen" ]] && chosen_path=$(desktop_path "$chosen"); then
    if chosen_owns_filemanager1 "$chosen_path"; then
        open_via_filemanager1 "$(exec_binary "$chosen_path")"
    else
        gio launch "$chosen_path" "$HOME" >/dev/null 2>&1 &
    fi
    exit 0
fi

for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    eval "command -v ${cmd%% *}" >/dev/null 2>&1 || continue
    eval "$cmd" &
    exit 0
done
