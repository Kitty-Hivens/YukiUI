#!/usr/bin/env bash
# Freeze or thaw the video wallpaper, for game mode.
#
# SIGSTOP halts mpvpaper's decode and render, which takes it to about no cpu at
# all and leaves the last frame on the screen rather than a blank colour, and
# SIGCONT starts it again. A monitor appearing or leaving while it is frozen is
# somebody else's problem: the hotplug watcher relaunches it.
#
# The pid comes from the process name because this script does not start
# mpvpaper and has no other way to find it, and the name is matched exactly so
# it cannot reach a viewer or an editor that merely mentions it.

case "${1:-}" in
    stop) pkill -STOP -x mpvpaper ;;
    cont) pkill -CONT -x mpvpaper ;;
    *)    echo "usage: ${0##*/} stop|cont" >&2; exit 2 ;;
esac
exit 0
