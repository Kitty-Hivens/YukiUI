#!/usr/bin/env bash
# Pastes what is on the clipboard into a folder, as a file manager does.
#
#     paste.sh FOLDER COPY_WORD
#
# Files copied go in as copies, files cut are moved, both read from the list
# GNOME's file manager writes, which says which it was, or from a plain list
# of links, which is a copy. A picture with no file behind it goes in as a new
# picture file. A name already taken in the folder gets COPY_WORD after it,
# "report (copy).pdf", then "report (copy 2).pdf", and so on, as the file
# manager names them in the person's language.
#
# Prints the name of everything that went in, one a line, so it can be picked.
# Exits 2 when there is nothing on the clipboard to paste.

set -uo pipefail

folder=$1
word=${2:-copy}
types=$(wl-paste --list-types 2>/dev/null) || exit 2

has() { grep -qxF "$1" <<<"$types"; }

# A free name in the folder for one wanted.
freeName() {
    local name=$1 stem ext n=1 candidate
    if [[ ! -e "$folder/$name" && ! -L "$folder/$name" ]]; then
        printf '%s' "$name"
        return
    fi
    if [[ "$name" == ?*.* ]]; then
        stem=${name%.*}
        ext=".${name##*.}"
    else
        stem=$name
        ext=""
    fi
    while :; do
        if (( n == 1 )); then candidate="$stem ($word)$ext"; else candidate="$stem ($word $n)$ext"; fi
        if [[ ! -e "$folder/$candidate" && ! -L "$folder/$candidate" ]]; then
            printf '%s' "$candidate"
            return
        fi
        n=$((n + 1))
    done
}

if has x-special/gnome-copied-files; then
    listing=$(wl-paste --no-newline --type x-special/gnome-copied-files)
    mode=$(head -n 1 <<<"$listing")
    links=$(tail -n +2 <<<"$listing")
elif has text/uri-list; then
    mode=copy
    links=$(wl-paste --no-newline --type text/uri-list)
elif has image/png; then
    name=$(freeName "Pasted image $(date '+%Y-%m-%d %H.%M.%S').png")
    wl-paste --type image/png >"$folder/$name" && printf '%s\n' "$name"
    exit
else
    exit 2
fi

# The links as paths, local ones only, unescaped. Comments and blank lines in
# a list of links are skipped, as the format has them.
mapfile -t paths < <(python3 -c '
import sys, urllib.parse
for line in sys.stdin.read().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or not line.startswith("file://"):
        continue
    print(urllib.parse.unquote(urllib.parse.urlparse(line).path))
' <<<"$links")
(( ${#paths[@]} > 0 )) || exit 2

status=0
for source in "${paths[@]}"; do
    name=$(basename -- "$source")
    # Cut and pasted where it already is, it stays as it is.
    if [[ "$mode" == cut && "$(dirname -- "$source")" -ef "$folder" ]]; then
        continue
    fi
    target=$(freeName "$name")
    if [[ "$mode" == cut ]]; then
        mv -n -- "$source" "$folder/$target" || { status=1; continue; }
    else
        cp -a -- "$source" "$folder/$target" || { status=1; continue; }
    fi
    printf '%s\n' "$target"
done
exit $status
