pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry.looks

// One application: starting it, whether it starts with the session and on
// which graphics card, whether its notifications get through, what it opens
// by default, and what installed it, with the way to take it off.
//
// Opened from an application's menu in the launcher, or from the list of
// installed applications. Opened as "app:<id>|uninstall" it opens on the
// question of taking it off.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    /** Taken once as the page is built: the window's key moves on before this page goes. */
    property string appId: ""
    readonly property var entry: root.appId.length > 0 ? DesktopEntries.byId(root.appId) : null

    /** What the helper said of it: origin, package, autostart, kinds of files. Null until read. */
    property var details: null
    /** Held back by the window until what it says has been read. */
    readonly property bool ready: root.details !== null
    readonly property string summary: root.entry ? (root.entry.genericName || root.entry.comment || "") : Translation.tr("This application is not installed")

    readonly property string helper: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/apps/app-info.py"))

    Component.onCompleted: {
        root.appId = (root.settings?.pageKey ?? "").slice(4);
        // Opened on the question of taking it off, from the launcher's menu.
        // Taken once, so going back to the page later does not ask again.
        const ask = root.settings?.ask ?? null;
        if (ask && ask.page === `app:${root.appId}` && ask.what === "uninstall") {
            root.confirming = true;
            root.settings.ask = null;
        }
        root.read();
    }

    // Asked again while on show, after Cancel say.
    Connections {
        target: root.settings ?? null
        function onAsked(page, what) {
            if (page === `app:${root.appId}` && what === "uninstall") {
                root.confirming = true;
                root.settings.ask = null;
            }
        }
    }

    function read() {
        reader.running = false;
        reader.command = ["python3", root.helper, "info", root.appId];
        reader.running = true;
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.details = JSON.parse(text);
                } catch (error) {
                    root.details = { origin: "none", removes: [], mimeTypes: [], alsoApps: [], autostart: false };
                }
                // The kinds of files it opens, and which it opens by default,
                // are read for an application that opens any: reading them
                // goes over every installed entry.
                if ((root.details.mimeTypes ?? []).length > 0)
                    DefaultApps.load();
            }
        }
    }

    // Whether it starts with the session, written as the desktop keeps it.
    Process {
        id: autostartWriter
        onExited: root.read()
    }

    readonly property var blockedApps: Config.options.notifications.blockedApps ?? []
    readonly property bool notificationsOn: !root.blockedApps.includes(root.appId)

    function setNotifications(on: bool) {
        const rest = root.blockedApps.filter(id => id !== root.appId);
        Config.options.notifications.blockedApps = on ? rest : rest.concat([root.appId]);
    }

    readonly property string gpuChoice: (Config.options.apps.secondGpu ?? []).includes(root.appId) ? "second"
        : (Config.options.apps.firstGpu ?? []).includes(root.appId) ? "first" : "auto"

    function setGpu(choice: string) {
        const second = (Config.options.apps.secondGpu ?? []).filter(id => id !== root.appId);
        const first = (Config.options.apps.firstGpu ?? []).filter(id => id !== root.appId);
        Config.options.apps.secondGpu = choice === "second" ? second.concat([root.appId]) : second;
        Config.options.apps.firstGpu = choice === "first" ? first.concat([root.appId]) : first;
    }

    /** The groups of file kinds it can open, from the defaults the desktop keeps. */
    readonly property string fileId: `${root.appId}.desktop`
    readonly property var openGroups: (root.details?.mimeTypes ?? []).length === 0 ? []
        : DefaultApps.groups.filter(group => group.candidates.some(candidate => candidate.id === root.fileId))

    readonly property string origin: root.details?.origin ?? "none"
    readonly property bool installed: (root.details?.path ?? "").length > 0
    /** What needs it, when something else does and it cannot go. */
    readonly property string blocked: root.details?.blocked ?? ""
    readonly property bool removable: root.installed && (root.origin === "pacman" || root.origin === "flatpak" || root.origin === "steam" || root.origin === "user")
    readonly property string originText: {
        const d = root.details;
        if (!d)
            return "";
        if (!root.installed)
            return Translation.tr("Not installed");
        const extra = [d.version, d.size].filter(part => (part ?? "").length > 0).join(", ");
        if (root.origin === "pacman")
            return Translation.tr("Package %1").arg(d.package) + (extra.length > 0 ? `, ${extra}` : "");
        if (root.origin === "flatpak")
            return Translation.tr("Flatpak %1").arg(d.package) + (extra.length > 0 ? `, ${extra}` : "");
        if (root.origin === "steam")
            return Translation.tr("A Steam game");
        if (root.origin === "user")
            return Translation.tr("Added to the list by hand or by another program");
        return Translation.tr("Installed with the system");
    }

    // Taking it off, asked first, and done by a service that outlives the
    // page: going back in the middle of it does not stop it halfway.
    property bool confirming: false
    property bool deleteData: false
    readonly property bool removing: AppRemoval.removing === root.appId
    readonly property string removalProblem: AppRemoval.problemFor === root.appId ? AppRemoval.problem : ""
    Connections {
        target: AppRemoval
        function onFinished(id, ok) {
            if (id !== root.appId)
                return;
            if (ok)
                root.confirming = false;
            root.read();
        }
    }
    function remove() {
        if (root.origin === "steam") {
            // Steam asks on its own, in its own window.
            AppRemoval.removeFromSteam(root.details.package);
            root.confirming = false;
            return;
        }
        AppRemoval.remove(root.details, root.deleteData);
    }

    spacing: ExLooks.settings.groupGap

    // What it is and where it came from, with starting it and taking it off.
    // At the top, so the question of taking it off, which the launcher's menu
    // opens the page on, is in sight however long the page is.
    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            iconSource: Quickshell.iconPath(root.entry?.icon ?? "", "application-x-executable")
            text: root.details === null ? (root.entry?.name ?? root.appId) : root.originText
            description: root.removing ? Translation.tr("Taking it off...")
                : root.removalProblem.length > 0 ? root.removalProblem
                : root.blocked.length > 0 ? Translation.tr("Cannot be taken off: %1 needs it").arg(root.blocked)
                : root.confirming && root.installed && !root.removable ? Translation.tr("Came with the system, so it is not taken off from here")
                : ""

            ExButton {
                kind: "accent"
                text: Translation.tr("Open")
                visible: root.entry !== null && root.installed
                onClicked: AppLaunch.run(root.entry)
            }
            ExButton {
                // Kept, greyed, for what cannot go, so the reason beside it
                // reads as the answer to it.
                visible: root.removable && !(root.confirming && root.blocked.length === 0)
                kind: "control"
                text: root.origin === "user" ? Translation.tr("Remove from the list") : Translation.tr("Uninstall")
                enabled: root.blocked.length === 0 && !AppRemoval.busy
                onClicked: root.confirming = true
            }
        }
        // The user's own copy of the entry, shown in place of the installed one.
        SettingsCard {
            Layout.fillWidth: true
            visible: root.installed && (root.details?.override ?? "").length > 0
            glyph: "edit_note"
            text: Translation.tr("Your own copy of its entry is used")
            description: root.details?.override ?? ""

            ExButton {
                kind: "control"
                text: Translation.tr("Use the installed one")
                onClicked: {
                    AppRemoval.resetOverride(root.details.override);
                    resetLater.restart();
                }
            }
            Timer {
                id: resetLater
                interval: 400
                onTriggered: root.read()
            }
        }
        // The question, with what goes with it. Not asked of what cannot go.
        SettingsCard {
            Layout.fillWidth: true
            visible: root.confirming && root.removable && root.blocked.length === 0
            glyph: "delete"
            text: root.origin === "user" ? Translation.tr("Move its entry to the trash?")
                : root.origin === "steam" ? Translation.tr("Steam asks for itself before it takes the game off")
                : Translation.tr("Take %1 off?").arg(root.entry?.name ?? root.appId)
            description: {
                const parts = [];
                const removes = (root.details?.removes ?? []).filter(name => name !== root.details.package);
                if (removes.length > 0)
                    parts.push(Translation.tr("Packages that go with it: %1").arg(removes.join(", ")));
                const apps = root.details?.alsoApps ?? [];
                if (apps.length > 0)
                    parts.push(Translation.tr("Applications that go with it: %1").arg(apps.join(", ")));
                if ((root.details?.override ?? "").length > 0)
                    parts.push(Translation.tr("Your own copy of its entry goes to the trash"));
                return parts.join("\n");
            }

            ExButton {
                kind: "control"
                text: Translation.tr("Cancel")
                enabled: !root.removing
                onClicked: root.confirming = false
            }
            ExButton {
                kind: "accent"
                text: root.origin === "user" ? Translation.tr("Move to trash") : Translation.tr("Uninstall")
                enabled: !AppRemoval.busy
                onClicked: root.remove()
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: root.confirming && root.origin === "flatpak" && (root.details?.hasData ?? false)
            glyph: "folder_delete"
            text: Translation.tr("Delete its data as well")
            description: root.details?.dataFolder ?? ""

            ExSwitch {
                checked: root.deleteData
                onToggled: root.deleteData = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Starting")
        visible: root.entry !== null && root.installed

        SettingsCard {
            Layout.fillWidth: true
            glyph: "start"
            text: Translation.tr("Start with the session")
            description: Translation.tr("Opens on its own after signing in")

            ExSwitch {
                enabled: root.details !== null && !autostartWriter.running
                checked: root.details?.autostart ?? false
                onToggled: {
                    autostartWriter.command = ["python3", root.helper, "autostart", root.appId, checked ? "on" : "off"];
                    autostartWriter.running = true;
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: AppLaunch.hasSecondGpu
            glyph: "memory"
            text: Translation.tr("Graphics card")
            description: AppLaunch.asksForSecondGpu(root.entry) ? Translation.tr("The application asks for the second card") : ""

            SettingsChoice {
                value: root.gpuChoice
                options: [
                    { value: "auto", text: Translation.tr("As it asks") },
                    { value: "second", text: Translation.tr("Second card") },
                    { value: "first", text: Translation.tr("This card") }
                ]
                onPicked: choice => root.setGpu(choice)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "keep"
            text: Translation.tr("Pinned to the launcher")

            ExSwitch {
                checked: (Config.options.launcher.pinnedApps ?? []).includes(root.appId)
                onToggled: {
                    const pins = (Config.options.launcher.pinnedApps ?? []).filter(id => id !== root.appId);
                    Config.options.launcher.pinnedApps = checked ? pins.concat([root.appId]) : pins;
                }
            }
        }
        SettingsCard {
            id: dockPin

            readonly property string dockId: (root.entry?.startupClass ?? "").length > 0 ? root.entry.startupClass : root.appId

            Layout.fillWidth: true
            glyph: "dock_to_bottom"
            text: Translation.tr("Pinned to the dock")

            ExSwitch {
                checked: TaskbarApps.isPinned(dockPin.dockId) || TaskbarApps.isPinned(root.appId)
                onToggled: {
                    if (TaskbarApps.isPinned(root.appId))
                        TaskbarApps.togglePin(root.appId);
                    else
                        TaskbarApps.togglePin(dockPin.dockId);
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Notifications")
        visible: root.entry !== null && root.installed

        SettingsCard {
            Layout.fillWidth: true
            glyph: root.notificationsOn ? "notifications" : "notifications_off"
            text: Translation.tr("Allow notifications")
            description: root.notificationsOn ? Translation.tr("Shown and kept like any other") : Translation.tr("Turned away: neither shown nor kept")

            ExSwitch {
                checked: root.notificationsOn
                onToggled: root.setNotifications(checked)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Opens by default")
        visible: root.openGroups.length > 0

        Repeater {
            model: root.openGroups

            SettingsCard {
                id: group

                required property var modelData
                readonly property bool isDefault: group.modelData.agreed && group.modelData.current === root.fileId

                Layout.fillWidth: true
                glyph: group.modelData.icon
                text: Translation.tr(group.modelData.name)
                description: group.isDefault ? Translation.tr("Opened with this application") : ""

                ExButton {
                    visible: !group.isDefault
                    kind: "control"
                    text: Translation.tr("Use this one")
                    enabled: !DefaultApps.busy
                    onClicked: DefaultApps.assign(group.modelData.key, root.fileId)
                }
                ExGlyph {
                    visible: group.isDefault
                    text: "check"
                    size: 20
                }
            }
        }
    }
}
