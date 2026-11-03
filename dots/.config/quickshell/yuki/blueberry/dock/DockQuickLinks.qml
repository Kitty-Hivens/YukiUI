import QtQuick
import Quickshell

import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// What a right click on the launcher button offers, as a right click on Start
// does on Windows: the places of the system a person goes to often, the
// session, and the desktop. What this desktop has no counterpart for, an
// administrator's terminal or a list of installed programs, is left out. The
// session goes one level deeper in place, the way the tray's menus do.
ExPopup {
    id: root

    /** The workspace the dock shows, for showing its desktop. */
    property int workspaceId: -1
    /** Whether the session entries are shown in place of the rest. */
    property bool inSession: false

    // The programs come from the compositor's own variables, the ones its keys
    // start them with, so a person's choice of terminal or file manager holds
    // here too, and the program is started by the compositor rather than as a
    // child of the shell.
    function runVariable(name: string) {
        Quickshell.execDetached(["hyprctl", "eval", `if ${name} then hl.exec_cmd(${name}) end`]);
    }

    readonly property var links: [
        { text: Translation.tr("Power"), glyph: "bolt", run: () => Surfaces.open("settings", "power") },
        { text: Translation.tr("System"), glyph: "computer", run: () => Surfaces.open("settings", "system") },
        { text: Translation.tr("Network and internet"), glyph: "wifi", run: () => Surfaces.open("settings", "network") },
        { separator: true },
        { text: Translation.tr("Terminal"), glyph: "terminal", run: () => root.runVariable("terminal") },
        { text: Translation.tr("Task Manager"), glyph: "monitoring", run: () => root.runVariable("taskManager") },
        { text: Translation.tr("Settings"), glyph: "settings", run: () => Surfaces.open("settings", "") },
        { text: Translation.tr("Files"), glyph: "folder", run: () => root.runVariable("fileManager") },
        { text: Translation.tr("Search"), glyph: "search", run: () => ExStates.launcherOpen = true },
        { separator: true },
        { text: Translation.tr("Shut down or sign out"), glyph: "power_settings_new", submenu: true },
        { text: Translation.tr("Desktop"), glyph: "desktop_windows", run: () => Minimize.toggleDesktop(root.workspaceId) }
    ]
    readonly property var sessionLinks: [
        { text: Translation.tr("Lock"), glyph: "lock", run: () => Session.lock() },
        { text: Translation.tr("Sign out"), glyph: "logout", run: () => Session.logout() },
        { separator: true },
        { text: Translation.tr("Sleep"), glyph: "bedtime", run: () => Session.suspend() },
        { text: Translation.tr("Shut down"), glyph: "power_settings_new", run: () => Session.poweroff() },
        { text: Translation.tr("Reboot"), glyph: "restart_alt", run: () => Session.reboot() }
    ]

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false
    onOpenChanged: {
        if (root.open)
            root.inSession = false;
    }

    Column {
        width: ExLooks.sizes.menuWidth

        ExMenuItem {
            visible: root.inSession
            glyph: "arrow_back"
            text: Translation.tr("Shut down or sign out")
            onClicked: root.inSession = false
        }
        ExMenuSeparator {
            visible: root.inSession
        }

        Repeater {
            model: root.inSession ? root.sessionLinks : root.links

            Loader {
                id: slot

                required property var modelData

                width: parent.width
                sourceComponent: slot.modelData.separator ? separator : entry

                Component {
                    id: separator
                    ExMenuSeparator {}
                }

                Component {
                    id: entry
                    ExMenuItem {
                        text: slot.modelData.text
                        glyph: slot.modelData.glyph
                        hasSubmenu: slot.modelData.submenu ?? false
                        onClicked: {
                            if (slot.modelData.submenu) {
                                root.inSession = true;
                                return;
                            }
                            root.open = false;
                            slot.modelData.run();
                        }
                    }
                }
            }
        }
    }
}
