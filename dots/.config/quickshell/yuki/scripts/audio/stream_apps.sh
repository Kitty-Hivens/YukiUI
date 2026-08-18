#!/usr/bin/env sh
# Resolve audio stream pids to the application they belong to.
#
# A stream's own process is often a short lived helper: Electron and Chromium
# spawn one per audio service, and it reports itself as "Chromium" no matter
# what the program is called. Helpers are recognised by --type= on their command
# line, so walking up until that stops gives the process a person would name.
#
# Prints, per requested pid: pid, the ancestor's argv[0], and its argv[1]. The
# caller decides what to make of them, since only it knows the desktop entries.

for pid in "$@"; do
    p=$pid
    depth=0
    while [ $depth -lt 8 ]; do
        cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
        [ -z "$cmd" ] && break
        case "$cmd" in
            *--type=*) : ;;
            *) break ;;
        esac
        # The second field is the command name in brackets and may hold spaces
        # -- Firefox names a content process "Web Content" -- so the fields
        # after it are counted from the closing bracket, not from the start.
        stat=$(cat "/proc/$p/stat" 2>/dev/null)
        [ -z "$stat" ] && break
        ppid=${stat##*") "}
        ppid=${ppid#* }
        ppid=${ppid%% *}
        case "$ppid" in
            '' | 0 | 1) break ;;
        esac
        p=$ppid
        depth=$((depth + 1))
    done

    # Arguments are meant to be separated by NUL, but a program that rewrites
    # its own title -- Electron does -- leaves the whole command in argv[0] with
    # spaces. Fall back to splitting on those when nothing else separates them.
    args=$(tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | grep .)
    if [ "$(printf '%s\n' "$args" | wc -l)" -le 1 ]; then
        args=$(printf '%s\n' "$args" | tr ' ' '\n' | grep .)
    fi

    first=$(printf '%s\n' "$args" | sed -n 1p)
    second=$(printf '%s\n' "$args" | sed -n 2p)
    [ -z "$first" ] && continue
    printf '%s\t%s\t%s\n' "$pid" "$first" "$second"
done
