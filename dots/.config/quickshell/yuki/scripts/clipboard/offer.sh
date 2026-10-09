#!/usr/bin/env bash
# Puts files on the clipboard as files, the way a file manager does, and a
# picture as the picture as well.
#
#     offer.sh [--cut] [--image FILE] PATH...
#
# The paths go on as a list of links, as the list GNOME's file manager reads
# for a copy or a cut, and as plain text, one a line. A program that takes
# files pastes the files, a terminal pastes the paths. With --image the file
# named goes on as a picture too, first, so a program that takes pictures
# pastes the picture, and the paths do not go on as text: a browser's text
# field takes text before a picture, and pasted the path of a screenshot.
#
# Through yuki-clip, which offers all of these at once. Without it only one
# form can go on: the picture when there is one, the list of links otherwise.

set -euo pipefail

mode=copy
image=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cut) mode=cut; shift ;;
        --image) image="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
[[ $# -gt 0 ]] || { echo "offer.sh: nothing to put on the clipboard" >&2; exit 1; }

# A link has its path escaped, a space as %20 and so on. Every path goes in
# as an argument, never into the code.
mapfile -t links < <(python3 -c '
import sys, urllib.parse, os
for path in sys.argv[1:]:
    print("file://" + urllib.parse.quote(os.path.abspath(path)))
' "$@")

# Every line of a list of links ends in a carriage return and a line feed,
# the last one included, which a command substitution would cut off.
uriList=$(printf '%s\r\n' "${links[@]}")$'\n'
gnomeList=$(printf '%s' "$mode"; printf '\n%s' "${links[@]}")
plain=$(printf '%s\n' "$@")

helper="${YUKI_CLIP:-/usr/lib/yuki/yuki-clip}"
if [[ -x "$helper" ]]; then
    forms=()
    [[ -n "$image" ]] && forms+=(-f image/png "$image")
    forms+=(-t text/uri-list "$uriList" -t x-special/gnome-copied-files "$gnomeList")
    [[ -z "$image" ]] && forms+=(-t "text/plain;charset=utf-8" "$plain" -t text/plain "$plain")
    exec "$helper" "${forms[@]}"
fi

if [[ -n "$image" ]]; then
    exec wl-copy --type image/png < "$image"
fi
printf '%s' "$uriList" | exec wl-copy --type text/uri-list
