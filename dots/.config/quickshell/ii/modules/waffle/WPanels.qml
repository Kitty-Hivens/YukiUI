pragma Singleton

import QtQuick
import Quickshell
import qs

/**
 * The panels that hang off the bar, and the rule that only one of them is out at
 * a time -- pressing a bar button puts away whatever the last one opened.
 */
Singleton {
    id: root

    readonly property list<string> exclusive: ["searchOpen", "searchPanelOpen", "sidebarLeftOpen", "sidebarRightOpen", "widgetsOpen"]

    function keepOnly(state) {
        for (const other of root.exclusive) {
            if (other !== state && GlobalStates[other])
                GlobalStates[other] = false;
        }
    }
}
