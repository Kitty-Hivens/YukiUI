pragma Singleton

import QtQuick
import Quickshell

// What the experimental environment's surfaces need to know about each other.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool sessionOpen: false
    /** The dock's windows, one per screen. A flyout's focus grab takes them in,
     *  so clicking the dock does not count as clicking away. */
    property list<var> dockWindows: []
}
