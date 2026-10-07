#!/usr/bin/env bash
# Keeps a screenshot and puts it on the clipboard as the picture and as the
# file, so it pastes into a program that takes pictures and into one that
# takes files, a terminal or a game, alike.
#
#     picture.sh SOURCE FOLDER [CROP]
#
# SOURCE is the capture, and is taken away. CROP is the part of it to keep, as
# magick takes it, or all of it when left out. The picture is kept in FOLDER,
# where the settings save screenshots. With no FOLDER it is kept in the cache
# instead, since a link on the clipboard needs a file behind it for as long as
# it can be pasted, and the last twenty kept there are enough for that.

set -euo pipefail

source=$1
folder=${2:-}
crop=${3:-}

keep=${folder:-${XDG_CACHE_HOME:-$HOME/.cache}/yuki/clipboard}
mkdir -p -- "$keep"
shot="$keep/screenshot-$(date +%Y-%m-%d_%H.%M.%S).png"

if [[ -n "$crop" ]]; then
    magick "$source" -crop "$crop" +repage "$shot"
    rm -f -- "$source"
else
    mv -f -- "$source" "$shot"
fi

if [[ -z "$folder" ]]; then
    ls -1t -- "$keep"/screenshot-*.png | tail -n +21 | while IFS= read -r old; do
        rm -f -- "$old"
    done
fi

exec bash "$(dirname -- "$0")/offer.sh" --image "$shot" "$shot"
