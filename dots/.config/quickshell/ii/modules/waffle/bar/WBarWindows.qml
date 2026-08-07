pragma Singleton

import QtQuick
import Quickshell

/**
 * The bar's windows, so panels can count them as their own.
 *
 * A panel holds a focus grab while it is open, and a grab swallows the click that
 * breaks it. Clicking one bar button while another button's panel is open would
 * therefore take two clicks: one to dismiss, one to press. Naming the bar in the
 * grab makes a press on it reach the button.
 */
Singleton {
    id: root

    property list<var> windows: []

    function add(window) {
        if (root.windows.indexOf(window) !== -1)
            return;
        root.windows = root.windows.concat([window]);
    }

    function remove(window) {
        root.windows = root.windows.filter(known => known !== window);
    }
}
