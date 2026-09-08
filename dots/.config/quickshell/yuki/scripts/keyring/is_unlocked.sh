#!/usr/bin/env bash
# Whether the keyring holding the shell's secrets is unlocked.
#
# The default collection is not always the one named "login": a Secret Service
# provider is free to call it something else. Asking about a collection that is
# not there fails, which reads as locked, and the shell then waits for an unlock
# that already happened. The service is asked which collection it means, and the
# well known name is only the fallback.
#
# Asked through gdbus rather than busctl: busctl ships with systemd, so on an
# init that is not systemd it is simply absent, and every answer here would come
# back "locked" for a keyring that is open. gdbus comes with glib, which is
# already under anything that talks to a Secret Service at all.
collection=$(gdbus call --session --dest org.freedesktop.secrets \
    --object-path /org/freedesktop/secrets \
    --method org.freedesktop.Secret.Service.ReadAlias default 2>/dev/null \
    | sed -n "s/^(objectpath '\(.*\)',)$/\1/p")

if [[ -z "${collection}" || "${collection}" == "/" ]]; then
    collection=/org/freedesktop/secrets/collection/login
fi

locked_state=$(gdbus call --session --dest org.freedesktop.secrets \
    --object-path "${collection}" \
    --method org.freedesktop.DBus.Properties.Get \
    org.freedesktop.Secret.Collection Locked 2>/dev/null)
if [[ "${locked_state}" == "(<false>,)" ]]; then
    echo 'Keyring is unlocked' >&2
    exit 0
else
    echo 'Keyring is locked' >&2
    exit 1
fi
