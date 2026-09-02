#!/usr/bin/env bash
# Shared by the launchers next to it. Sourced, not run.
#
# The binds used to name their applications in a preference list and take the
# first one installed. That made the list the answer to "which browser is mine",
# which it is not: the system already holds that answer, and the shell's own
# settings page writes it. Two consequences, and the second is worse than the
# first. A choice made in the settings was ignored, and installing an unrelated
# package could silently change what a key did, because a name earlier in the
# list had appeared.
#
# So the system is asked first and the list is what is left when nothing is set.

# Full path of an installed desktop entry, by id. Non-zero when it is not there.
desktop_path() {
    local id="$1" dir hit
    local -a roots
    IFS=':' read -r -a roots <<< "${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

    for dir in "${roots[@]}"; do
        [[ -n "$dir" && -f "$dir/applications/$id" ]] || continue
        printf '%s\n' "$dir/applications/$id"
        return 0
    done

    # An id may name an entry inside a subdirectory, where the flat lookup above
    # misses it. Rare enough to be worth a walk only after that has failed.
    for dir in "${roots[@]}"; do
        [[ -n "$dir" && -d "$dir/applications" ]] || continue
        hit=$(find "$dir/applications" -name "$id" -type f -print -quit 2>/dev/null)
        [[ -n "$hit" ]] || continue
        printf '%s\n' "$hit"
        return 0
    done

    return 1
}

# Starts whatever the system opens $1 with, passing the rest as arguments.
# Non-zero when nothing is set for that type, or when what is set is not
# installed -- and only then is falling back to a list the right answer.
#
# A set-but-broken default is launched rather than skipped. Someone who chose it
# should see it fail, not watch a different application open in its place.
launch_default() {
    local mime="$1"
    shift
    local id path
    id=$(xdg-mime query default "$mime" 2>/dev/null)
    [[ -n "$id" ]] || return 1
    path=$(desktop_path "$id") || return 1
    gio launch "$path" "$@" >/dev/null 2>&1 &
    return 0
}
