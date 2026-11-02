#!/bin/bash
# Lists the templates a new file can be made from, as the file managers find
# them, one a line: kind, name, icon and the file to copy, tab between.
#
#     templates.sh LANGUAGE
#
# Nautilus's are the files in the templates folder of the user's own folders,
# named and copied as they are ("file" kind, "-" for the icon they have not). Dolphin's
# are links in the templates folders of the data directories, each naming the
# file it copies, relative to itself or by path, and the name and icon it is
# offered under, in LANGUAGE where it gives one ("link" kind). One whose file
# is not there is left out.

language=${1:-}

templates=$(xdg-user-dir TEMPLATES 2>/dev/null)
# With no templates folder set, xdg-user-dir answers the home folder.
if [ -n "$templates" ] && [ "$templates" != "$HOME" ] && [ -d "$templates" ]; then
    find "$templates" -maxdepth 1 -type f ! -name '.*' -printf 'file\t%f\t-\t%p\n' | sort
fi

data_dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
IFS=: read -r -a dirs <<< "$data_dirs"
seen=""
for dir in "${dirs[@]}"; do
    folder="$dir/templates"
    [ -d "$folder" ] || continue
    for link in "$folder"/*.desktop; do
        [ -f "$link" ] || continue
        # The first data directory to have a link of a name wins, as for
        # desktop entries.
        base=${link##*/}
        case ":$seen:" in *":$base:"*) continue ;; esac
        seen="$seen:$base"
        awk -v language="$language" -v folder="$folder" '
            /^\[/ { entry = ($0 == "[Desktop Entry]"); next }
            !entry { next }
            {
                key = $0; sub(/=.*/, "", key)
                value = $0; sub(/^[^=]*=/, "", value)
                if (key == "Name") name = value
                else if (language != "" && key == "Name[" language "]") local = value
                else if (key == "Icon") icon = value
                else if (key == "URL") url = value
                else if (key == "Type") type = value
            }
            END {
                if (type != "Link" || url == "") exit
                sub(/^file:\/\//, "", url)
                if (substr(url, 1, 1) != "/") url = folder "/" url
                # A dash for no icon: read joins the tabs either side of an empty field.
                print "link\t" (local != "" ? local : name) "\t" (icon != "" ? icon : "-") "\t" url
            }' "$link"
    done
done | while IFS=$'\t' read -r kind name icon file; do
    # A link to a folder, or to nothing, is not a file to copy.
    [ -f "$file" ] && printf '%s\t%s\t%s\t%s\n' "$kind" "$name" "$icon" "$file"
done
