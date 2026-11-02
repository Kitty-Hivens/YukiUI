pragma Singleton

import QtQuick
import Quickshell

/**
 * Keeps the tray's icons across a restart of the shell, whichever desktop is up.
 *
 * Many programs register their tray icon once, with whoever answers as the
 * StatusNotifierWatcher, and never again. The shell's tray answers as that
 * watcher itself, so a restart of the shell lost those icons until the program
 * was started again. yuki-tray answers from outside the shell for the whole
 * session: it copies what is registered while the shell holds the name, takes
 * the name over when the shell lets go of it, and the next shell reads the
 * icons from it.
 *
 * Started detached, so it outlives the shell, and only one runs: a second
 * leaves at once.
 */
Singleton {
    id: root

    function load() {}

    readonly property string helper: Quickshell.env("YUKI_TRAY") || "/usr/lib/yuki/yuki-tray"

    Component.onCompleted: Quickshell.execDetached([root.helper])
}
