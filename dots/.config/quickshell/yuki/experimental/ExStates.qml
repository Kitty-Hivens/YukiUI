pragma Singleton

import QtQuick
import Quickshell

// What the experimental environment's surfaces need to know about each other.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool sessionOpen: false
    /** How many notification centers are open. There is one per dock, so one
     *  per screen, and only one flyout is open across the docks, so more than
     *  one only for the moment one hands over to the next. */
    property int notificationViewers: 0
    /** The dock flyout open now, on whichever screen, or null. */
    property var openPopup: null
    /** The dock's windows, one per screen. A flyout's focus grab takes them in,
     *  so clicking the dock does not count as clicking away. */
    property list<var> dockWindows: []
}
