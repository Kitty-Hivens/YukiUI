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
    readonly property string soundComponent: "modules/systemSettings/SoundPage.qml"

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

    // The device sound currently goes to. Deliberately not the volume as well:
    // that changes on every scroll of the wheel, and the whole page list is
    // rebuilt whenever a status does.
    readonly property string soundStatus: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : ""

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
                },
                {
                    name: Translation.tr("Sound"),
                    icon: "volume_up",
                    description: Translation.tr("Devices, applications and profiles"),
                    component: root.soundComponent,
                    status: root.soundStatus
                }
            ]
        }
    ]

    /**
     * The page a caller asked for by name, so a button elsewhere in the shell
     * can open the window where it means rather than at the front door.
     */
    function componentFor(key) {
        switch ((key ?? "").toLowerCase()) {
        case "sound":
            return root.soundComponent;
        case "displays":
            return root.displaysComponent;
        default:
            return root.homeComponent;
        }
    }

    readonly property var pages: {
        const all = [];
        for (const group of root.groups)
            for (const page of group.pages)
                all.push(page);
        return all;
    }
}
