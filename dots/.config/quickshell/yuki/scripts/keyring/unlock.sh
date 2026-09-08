#!/usr/bin/env bash
# Hands the login password to the keyring daemon the session already has.
#
# The daemon that owns org.freedesktop.secrets is started by systemd, and its
# socket unit brings it back the moment anything connects. Killing it to run a
# replacement under --login, which is what this did, raced that restart: two
# daemons then claimed the same name, and the one holding the unlocked keyring
# was the one systemd knew nothing about, spawned into whatever cgroup the
# shell happened to be in. --unlock says the same thing over the control
# socket to the daemon that is already running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if already unlocked
if "${SCRIPT_DIR}/is_unlocked.sh"; then
    exit 1
fi

# Prompt for password if not provided
if [[ -z "${UNLOCK_PASSWORD}" ]]; then
    echo -n 'Login password: ' >&2
    # Not "return": this is a script, not a function, and bash refuses it there
    # -- so a read that gave nothing carried on to unlock with an empty password.
    read -s UNLOCK_PASSWORD || exit 1
    echo '' >&2
fi

# Without -n the newline is read as part of the password.
#
# Which of the two calls depends on there being a daemon to talk to. Under
# systemd the socket is there before the daemon is, so --unlock always has an
# ear; under an init that starts nothing on its own, and where PAM did not
# start one either, there is no socket and no daemon, and --login is the call
# that both starts it and opens the keyring with the same password.
control="${GNOME_KEYRING_CONTROL:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring}"
if [[ -S "${control}/control" ]]; then
    printf '%s' "${UNLOCK_PASSWORD}" | gnome-keyring-daemon --unlock
    status=$?
else
    printf '%s' "${UNLOCK_PASSWORD}" | gnome-keyring-daemon --daemonize --login >/dev/null
    status=$?
fi
unset UNLOCK_PASSWORD
exit "${status}"
