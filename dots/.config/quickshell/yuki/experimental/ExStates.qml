pragma Singleton

import QtQuick
import Quickshell

// What the experimental environment's surfaces need to know about each other.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool sessionOpen: false
    /** How many notification centers are open. There is one per dock, so one
     *  per screen, and two can be open at once. */
    property int notificationViewers: 0
    /** The dock's windows, one per screen. A flyout's focus grab takes them in,
     *  so clicking the dock does not count as clicking away. */
    property list<var> dockWindows: []
}
