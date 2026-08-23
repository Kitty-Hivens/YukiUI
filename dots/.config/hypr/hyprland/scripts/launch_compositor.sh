#!/bin/sh
# The compositor binary the session watchdog launches, with safe mode filtered out.
#
# start-hyprland restarts Hyprland after any unclean exit, and from the first
# such restart it appends --safe-mode and never clears the flag again. Safe mode
# refuses the real config: the compositor generates a stock one in its runtime
# directory and comes up on that, so a crash returns a session with no cursor
# theme, no shell, no idle daemon and no clipboard watchers. Reloading the config
# does not bring those back either -- it loads the real config, but hyprland.start,
# the event the whole autostart hangs off, fired long before, on the stock one.
#
# Dropping the flag makes a crash restart come up as the real session. The flag
# still has a job when the config itself is what kills the compositor, so a run of
# starts that die immediately ends the override and lets safe mode through.
#
# Named by the session entry the installer writes, so every way into the session
# goes through it -- $XDG_DATA_HOME/wayland-sessions/yuki.desktop:
#   Exec=/usr/bin/start-hyprland --path <this file>

STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-safe-mode-override"
RETRIES=3   # crash restarts that may keep the real config
SETTLED=60  # seconds a start must survive to count as a session, not a failed start

hyprland=/usr/bin/Hyprland
[ -x "$hyprland" ] || hyprland=$(command -v Hyprland) || hyprland=Hyprland

now=$(date +%s)

safe=0
for arg in "$@"; do
    [ "$arg" = "--safe-mode" ] && safe=1
done

# A start that is not a crash restart ends whatever run came before it.
if [ "$safe" -eq 0 ]; then
    echo "$now 0" > "$STATE"
    exec "$hyprland" "$@"
fi

last=0
count=0
[ -r "$STATE" ] && read -r last count < "$STATE"
case "$last$count" in '' | *[!0-9]*) last=0; count=0 ;; esac

# Only starts that died quickly count towards the run. One that carried the
# session for a while and then crashed is a crash, not a config that cannot come up.
[ "$((now - last))" -ge "$SETTLED" ] && count=0
count=$((count + 1))
echo "$now $count" > "$STATE"

if [ "$count" -gt "$RETRIES" ]; then
    echo "launch_compositor: $count starts died within ${SETTLED}s, letting safe mode through" >&2
    exec "$hyprland" "$@"
fi

echo "launch_compositor: crash restart $count of $RETRIES, keeping the real config" >&2

# Rebuild the argument list without the flag. Everything else has to survive:
# --watchdog-fd is how the watchdog learns the compositor came up at all, and
# --locked is what carries a locked session across the restart.
i=0
n=$#
while [ "$i" -lt "$n" ]; do
    arg=$1
    shift
    [ "$arg" = "--safe-mode" ] || set -- "$@" "$arg"
    i=$((i + 1))
done

exec "$hyprland" "$@"
