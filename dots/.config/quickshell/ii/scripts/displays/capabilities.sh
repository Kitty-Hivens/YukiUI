#!/bin/sh
# Reports what each connected panel claims it can do, one line per output:
#
#   <connector> <pq> <bt2020> <peak-nits>
#
# Read from EDID rather than from the compositor, because the compositor reports
# what is currently configured, not what the hardware is willing to accept.
# Offering HDR to a panel that advertises neither PQ nor BT.2020 leaves it
# guessing at a signal it was never designed to receive.

for dir in /sys/class/drm/card*-*/; do
    connector=$(basename "$dir")
    connector=${connector#*-}

    [ "$(cat "$dir/status" 2>/dev/null)" = "connected" ] || continue

    edid=$(edid-decode "$dir/edid" 2>/dev/null) || continue
    [ -n "$edid" ] || continue

    pq=0
    printf '%s' "$edid" | grep -q "SMPTE ST2084" && pq=1

    wide=0
    printf '%s' "$edid" | grep -q "BT2020RGB" && wide=1

    peak=$(printf '%s' "$edid" \
        | grep "Desired content max luminance" \
        | grep -oE "[0-9]+\.[0-9]+" | head -1)

    printf '%s %s %s %s\n' "$connector" "$pq" "$wide" "${peak:-0}"
done
