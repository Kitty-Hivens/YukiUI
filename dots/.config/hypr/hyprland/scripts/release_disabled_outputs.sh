#!/bin/sh
# Turns off outputs the kernel lit at boot and the compositor never claimed.
#
# The kernel lights every connector it finds before the compositor starts. An
# output the display layout disables is then one Hyprland never touches, so it
# keeps that boot modeset: a laptop panel sits at full backlight with nothing
# rendered to it, an external monitor shows a black frame instead of dropping to
# standby. Claiming such an output and releasing it makes the driver run its
# power sequence, which is what actually turns it off.
#
# Only the boot case is broken. Unplugging a monitor hands its output to Hyprland
# and replugging releases it, so those power down on their own.
#
# Runs before the shell is launched: changing the set of active outputs forces
# every client to reconfigure, and that costs nothing while there are no clients.

# The kernel still drives this connector. Also what keeps the pass idempotent:
# releasing an output flips this to "disabled", so a second run finds nothing.
kernel_holds() {
    for state in /sys/class/drm/card*-"$1"/enabled; do
        [ -r "$state" ] || continue
        [ "$(cat "$state")" = "enabled" ] && return 0
    done
    return 1
}

claimed() {
    hyprctl monitors all -j | jq -e --arg m "$1" \
        'any(.[]; .name == $m and (.disabled | not) and .currentFormat != "Invalid")' \
        >/dev/null 2>&1
}

# Outputs with no sysfs entry of their own -- headless, remote -- never match
# kernel_holds and are skipped.
for output in $(hyprctl monitors all -j | jq -r '.[] | select(.disabled) | .name'); do
    kernel_holds "$output" || continue

    hyprctl eval "hl.monitor({ output = '$output', mode = 'preferred', position = 'auto', scale = 1, disabled = false })" >/dev/null

    # Release it only once the output is really up. A cycle that never reaches
    # the hardware leaves the output exactly where it was.
    waited=0
    while [ "$waited" -lt 40 ]; do
        claimed "$output" && break
        waited=$((waited + 1))
        sleep 0.05
    done

    # No geometry here on purpose: the saved layout owns that, this hands the
    # output back the way it was configured.
    hyprctl eval "hl.monitor({ output = '$output', disabled = true })" >/dev/null
done
