#!/usr/bin/env bash
# Puts the compositor rules of the environment that is up where the compositor
# config reads them.
#
#     environment_rules.sh HEADER RULES TARGET
#
# TARGET becomes HEADER, a blank line, then the file RULES, or the header alone
# when RULES is empty.
#
# Written only when that differs from what TARGET already holds. Hyprland
# reloads its whole config whenever a file it read is replaced, and the shell
# calls this every time it starts, so rewriting the same rules made every
# start of the shell a reload: global shortcuts registered anew under a held
# key, and every setting made at runtime, game mode's among them, dropped.
#
# The config reads TARGET only if it is there, so a TARGET that did not exist
# when the config was last read is not watched, and creating it changes
# nothing until something reloads. Creating it reloads, once.
#
# Written beside TARGET under a name of its own and renamed into place, so the
# compositor never reads half a file and two runs at once never share one.

set -u

header=$1
rules=$2
target=$3

mkdir -p "$(dirname "$target")" || exit 1
staged=$(mktemp "$target.XXXXXX") || exit 1
trap 'rm -f "$staged"' EXIT

{
    printf '%s\n\n' "$header"
    if [ -n "$rules" ]; then
        cat "$rules"
    fi
} > "$staged" || exit 1

if cmp -s "$staged" "$target"; then
    exit 0
fi

existed=false
[ -e "$target" ] && existed=true
chmod 644 "$staged"
mv -f "$staged" "$target" || exit 1

if ! $existed; then
    hyprctl reload > /dev/null
fi
