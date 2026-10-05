#!/usr/bin/env bash
# Writes a file the compositor config reads as it loads, and reloads the config
# when the file changed, for a setting that takes effect only then.
#
#     state_reload.sh TEXT TARGET
#
# Nothing is written, and nothing reloaded, when TARGET already holds TEXT: a
# reload drops every setting made at runtime, game mode's among them. Written
# beside TARGET and renamed into place, so the config never reads half a file.

set -u

text=$1
target=$2

mkdir -p "$(dirname "$target")" || exit 1
staged=$(mktemp "$target.XXXXXX") || exit 1
trap 'rm -f "$staged"' EXIT

printf '%s' "$text" > "$staged" || exit 1
if cmp -s "$staged" "$target"; then
    exit 0
fi
chmod 644 "$staged"
mv -f "$staged" "$target" || exit 1
hyprctl reload > /dev/null
