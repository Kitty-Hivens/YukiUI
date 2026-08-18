#!/usr/bin/env bash
# Whether the keyring holding the shell's secrets is unlocked.
#
# The default collection is not always the one named "login": a Secret Service
# provider is free to call it something else. Asking about a collection that is
# not there fails, which reads as locked, and the shell then waits for an unlock
# that already happened. The service is asked which collection it means, and the
# well known name is only the fallback.
collection=$(busctl --user call org.freedesktop.secrets \
    /org/freedesktop/secrets org.freedesktop.Secret.Service \
    ReadAlias s default 2>/dev/null | sed -n 's/^o "\(.*\)"$/\1/p')

if [[ -z "${collection}" || "${collection}" == "/" ]]; then
    collection=/org/freedesktop/secrets/collection/login
fi

locked_state=$(busctl --user get-property org.freedesktop.secrets \
    "${collection}" \
    org.freedesktop.Secret.Collection Locked 2>/dev/null)
if [[ "${locked_state}" == "b false" ]]; then
    echo 'Keyring is unlocked' >&2
    exit 0
else
    echo 'Keyring is locked' >&2
    exit 1
fi
