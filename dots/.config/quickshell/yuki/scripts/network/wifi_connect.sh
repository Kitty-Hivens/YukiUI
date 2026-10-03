#!/usr/bin/env bash
# Joins a wifi network with a password, without the password ever being an
# argument of a process.
#
#     SSID=... PASSWORD=... SECURITY=... wifi_connect.sh
#
# Every process on the machine can read every other process's arguments in
# /proc, so `nmcli dev wifi connect SSID password PASSWORD` put the password
# where anyone could read it for as long as the attempt ran. The environment
# of a process is readable by its owner alone, and the password goes from
# there to nmcli on its stdin, written by a builtin, as the passwd-file of
# `nmcli connection up`.
#
# That needs a profile to bring up. The one saved for this SSID is used, the
# same one every other wifi action here matches on. A network never joined
# has one made for it first, as `nmcli dev wifi connect` would, with the key
# management its SECURITY (nmcli's own column) calls for, and it is deleted
# again when the attempt fails, so a wrong password leaves nothing behind.
# NetworkManager keeps the password in the profile once the network is joined.
#
# Errors are nmcli's own, on stderr, for the caller to read.

set -u

ssid=${SSID:?}
security=${SECURITY:-}

# The key management a security column calls for, and the secret it takes.
case "$security" in
    *802.1X*)
        echo "Error: networks that sign in with a user name are not supported here" >&2
        exit 1
        ;;
    *WEP*)
        keymgmt=none
        secret=802-11-wireless-security.wep-key0
        # As nmcli guesses it: a key is 5 or 13 characters, or 10 or 26 hex
        # digits, and anything else is a passphrase.
        case ${#PASSWORD} in
            5 | 10 | 13 | 26) weptype=1 ;;
            *) weptype=2 ;;
        esac
        ;;
    *WPA1* | *WPA2*)
        keymgmt=wpa-psk
        secret=802-11-wireless-security.psk
        ;;
    *WPA3*)
        keymgmt=sae
        secret=802-11-wireless-security.psk
        ;;
    *)
        keymgmt=wpa-psk
        secret=802-11-wireless-security.psk
        ;;
esac

uuid=
while IFS=: read -r candidate type; do
    [ "$type" = "802-11-wireless" ] || continue
    if [ "$(nmcli -g 802-11-wireless.ssid connection show "$candidate")" = "$ssid" ]; then
        uuid=$candidate
        break
    fi
done < <(nmcli -g UUID,TYPE connection show)

made=false
if [ -z "$uuid" ]; then
    settings=(type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt "$keymgmt")
    if [ "$keymgmt" = none ]; then
        settings+=(wifi-sec.wep-key-type "$weptype")
    fi
    added=$(nmcli connection add "${settings[@]}") || exit 1
    uuid=$(printf '%s\n' "$added" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1)
    if [ -z "$uuid" ]; then
        echo "Error: the new profile for this network could not be found" >&2
        exit 1
    fi
    made=true
fi

# nmcli strips spaces from both ends of a secret in its passwd-file and reads a
# backslash as an escape, so those characters go in as octal escapes, which
# it reads back. A password may begin or end with a space.
escaped=${PASSWORD//\\/\\134}
escaped=${escaped// /\\040}
escaped=${escaped//$'\t'/\\011}
printf '%s:%s\n' "$secret" "$escaped" | nmcli connection up uuid "$uuid" passwd-file /dev/stdin
status=$?
if [ "$status" -eq 0 ]; then
    exit 0
fi
if $made; then
    nmcli connection delete uuid "$uuid" > /dev/null 2>&1
fi
exit "$status"
