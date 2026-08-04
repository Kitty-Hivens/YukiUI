pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * What the window can show, in the order it offers it.
 *
 * The navigation, the window header and the home page all describe the same
 * set of pages. Written once here, they cannot drift apart, and a page added
 * below appears in all three.
 */
Singleton {
    id: root

    readonly property string homeComponent: "modules/systemSettings/HomePage.qml"
    readonly property string displaysComponent: "modules/systemSettings/DisplaysPage.qml"

    /**
     * A line of live state per page.
     *
     * It lives with the page entry rather than on the home page, so a section
     * can say what it currently holds without the home page having to know how
     * to read any of it.
     */
    readonly property string displaysStatus: {
        const active = Displays.outputs.filter(output => !output.disabled);
        if (active.length === 1)
            return `${active[0].name} · ${active[0].width}x${active[0].height}`;
        if (active.length > 1)
            return Translation.tr("%1 connected").arg(active.length);
        return "";
    }

    readonly property var groups: [
        {
            // Unnamed: the way in needs no heading above it.
            name: "",
            pages: [
                {
                    name: Translation.tr("Home"),
                    icon: "home",
                    description: Translation.tr("Overview of this system"),
                    component: root.homeComponent,
                    status: ""
                }
            ]
        },
        {
            name: Translation.tr("Hardware"),
            pages: [
                {
                    name: Translation.tr("Displays"),
                    icon: "monitor",
                    description: Translation.tr("Arrangement, modes, colour"),
                    component: root.displaysComponent,
                    status: root.displaysStatus
                }
            ]
        }
    ]

    readonly property var pages: {
        const all = [];
        for (const group of root.groups)
            for (const page of group.pages)
                all.push(page);
        return all;
    }
}
