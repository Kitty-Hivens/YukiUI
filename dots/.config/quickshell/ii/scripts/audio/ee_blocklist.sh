#!/usr/bin/env sh
# Add or remove an application in EasyEffects' own exclusion list.
#
# Usage: ee_blocklist.sh add|remove <node-name> [output|input]
#
# The list lives in the preset that is currently loaded, and EasyEffects only
# reads it when a preset is loaded -- hence the reload at the end. It is matched
# against the stream's node.name, which is not the same string a person sees:
# every Electron program calls itself Chromium. That is EasyEffects' matching,
# not ours.
#
# Exclusion applies to streams that start afterwards. One already playing keeps
# going where it is until it is moved, which the caller does once this returns.
set -u

action=${1:-}
name=${2:-}
kind=${3:-output}

[ -z "$action" ] || [ -z "$name" ] && exit 2
case "$kind" in
    output | input) ;;
    *) exit 2 ;;
esac

db="$HOME/.config/easyeffects/db/easyeffectsrc"
key="lastLoadedOutputPreset"
[ "$kind" = "input" ] && key="lastLoadedInputPreset"

preset=$(sed -n "s/^$key=//p" "$db" 2>/dev/null)
[ -z "$preset" ] && exit 1

file="$HOME/.local/share/easyeffects/$kind/$preset.json"
[ -f "$file" ] || exit 1

tmp="$file.yuki-tmp"
if [ "$action" = "add" ]; then
    jq --arg n "$name" --arg k "$kind" \
        '.[$k].blocklist = (((.[$k].blocklist // []) + [$n]) | unique)' "$file" > "$tmp" || exit 1
else
    jq --arg n "$name" --arg k "$kind" \
        '.[$k].blocklist = ((.[$k].blocklist // []) - [$n])' "$file" > "$tmp" || exit 1
fi
mv "$tmp" "$file" || exit 1

easyeffects --load-preset "$preset" >/dev/null 2>&1
