#!/usr/bin/env bash
# Starts an application for a bind.
#
#   launch_first_available.sh --mime x-scheme-handler/http 'firefox' 'chromium'
#   launch_first_available.sh 'foot' 'kitty'
#
# With --mime the system is asked first and the list is the fallback. Without it
# the list is all there is, which is right for the kinds of application XDG has
# no default for: a terminal has no settled one, and a task manager has no
# concept at all.

set -u
source "$(dirname "$(readlink -f "$0")")/launcher-lib.sh"

mime=""
if [[ "${1:-}" == "--mime" ]]; then
    mime="${2:-}"
    shift 2
fi

[[ -n "$mime" ]] && launch_default "$mime" && exit 0

for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    eval "command -v ${cmd%% *}" >/dev/null 2>&1 || continue
    eval "$cmd" &
    exit 0
done
