#!/usr/bin/env bash
# Names the graphics adapters.
#
# From the kernel's own PCI ids and the id database every distribution ships,
# rather than from lspci: that is a package of its own for what is two files and
# a lookup, and the database it reads is the same one.
#
# One adapter per line, in the order the kernel numbers them. Nothing at all
# when there is no database to read or the device is not in it -- a name that is
# half a hexadecimal id answers nobody's question.

set -u

ids=/usr/share/hwdata/pci.ids
[ -r "$ids" ] || exit 0

for device in /sys/class/drm/card[0-9]*/device; do
    [ -r "$device/class" ] && [ -r "$device/vendor" ] && [ -r "$device/device" ] || continue
    # 0x03xxxx is the display controller class; everything else on the bus is
    # not what anyone means by "graphics".
    case "$(cat "$device/class")" in
        0x03*) ;;
        *) continue;;
    esac
    vendor=$(cat "$device/vendor"); vendor=${vendor#0x}
    model=$(cat "$device/device"); model=${model#0x}
    awk -v vendor="$vendor" -v model="$model" '
        # The short name where the database carries one in brackets, which is
        # what the part is sold and spoken of as, and the long one trimmed of its
        # company suffix otherwise.
        function short(name) {
            if (match(name, /\[[^]]+\]/))
                return substr(name, RSTART + 1, RLENGTH - 2)
            sub(/,? (Corporation|Corp\.|Inc\.|Incorporated|Technologies|Technology|Co\.,? Ltd\.?|Ltd\.?)$/, "", name)
            return name
        }
        # Vendor lines start at column zero and the devices of that vendor are
        # indented under it, so the vendor is known by the time its device is.
        /^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]  / {
            if (found)
                exit
            found = (tolower(substr($0, 1, 4)) == vendor)
            if (found)
                vendorName = substr($0, 7)
            next
        }
        found && /^\t[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]  / {
            if (tolower(substr($0, 2, 4)) != model)
                next
            print short(vendorName) " " short(substr($0, 8))
            exit
        }
    ' "$ids"
done | awk '!seen[$0]++'
