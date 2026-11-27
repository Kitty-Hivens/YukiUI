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
    property bool askRemoval: false
    readonly property var entry: root.appId.length > 0 ? DesktopEntries.byId(root.appId) : null

    /** What the helper said of it: origin, package, autostart, kinds of files. Null until read. */
    property var details: null
    /** Held back by the window until what it says has been read. */
    readonly property bool ready: root.details !== null
    readonly property string summary: root.entry ? (root.entry.genericName || root.entry.comment || "") : Translation.tr("This application is not installed any more")

    readonly property string helper: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/apps/app-info.py"))

    Component.onCompleted: {
        const key = root.settings?.pageKey ?? "";
        const parts = key.slice(4).split("|");
        root.appId = parts[0];
        root.askRemoval = parts[1] === "uninstall";
        root.read();
        DefaultApps.load();
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
                    root.details = { origin: "none", removes: [], mimeTypes: [], autostart: false };
                }
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
    readonly property var openGroups: DefaultApps.groups.filter(group => group.candidates.some(candidate => candidate.id === root.fileId))

    readonly property string origin: root.details?.origin ?? "none"
    /** What needs it, when something else does and it cannot go. */
    readonly property string blocked: root.details?.blocked ?? ""
    readonly property bool removable: root.origin === "pacman" || root.origin === "flatpak" || root.origin === "steam" || root.origin === "user"
    readonly property string originText: {
        const d = root.details;
        if (!d)
            return "";
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

    // Taking it off, asked first. Root's part runs through sudo when it lets
    // itself be used without a password and through the password prompt
    // otherwise, as the power page does.
    property bool confirming: root.askRemoval
    property string removalProblem: ""
    Process {
        id: remover
        onExited: exitCode => {
            // 126 and 127 are the prompt dismissed, which is no problem.
            if (exitCode === 0) {
                root.confirming = false;
                root.removalProblem = "";
                root.read();
            } else if (exitCode !== 126 && exitCode !== 127) {
                root.removalProblem = Translation.tr("It could not be taken off, status %1").arg(exitCode);
            }
        }
    }
    function remove() {
        const d = root.details;
        root.removalProblem = "";
        if (root.origin === "pacman")
            remover.command = ["bash", "-c", 'if command -v sudo > /dev/null && sudo -n true 2> /dev/null; then sudo -n pacman -Rs --noconfirm "$1"; else pkexec pacman -Rs --noconfirm "$1"; fi', "remove", d.package];
        else if (root.origin === "flatpak")
            remover.command = ["flatpak", "uninstall", `--${d.installation ?? "system"}`, "-y", "--noninteractive", d.package];
        else if (root.origin === "steam")
            remover.command = ["steam", `steam://uninstall/${d.package}`];
        else if (root.origin === "user")
            remover.command = ["gio", "trash", d.path];
        else
            return;
        remover.running = true;
        // Steam asks on its own, in its own window.
        if (root.origin === "steam")
            root.confirming = false;
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
            description: root.removalProblem.length > 0 ? root.removalProblem
                : root.blocked.length > 0 ? Translation.tr("Cannot be taken off: %1 needs it").arg(root.blocked)
                : root.entry === null ? Translation.tr("Taken off")
                : ""

            ExButton {
                kind: "accent"
                text: Translation.tr("Open")
                visible: root.entry !== null
                onClicked: AppLaunch.run(root.entry)
            }
            ExButton {
                // Kept, greyed, for what cannot go, so the reason above reads as
                // the answer to it.
                visible: root.removable && root.entry !== null && !(root.confirming && root.blocked.length === 0)
                kind: "control"
                text: root.origin === "user" ? Translation.tr("Remove from the list") : Translation.tr("Uninstall")
                enabled: root.blocked.length === 0 && !remover.running
                onClicked: root.confirming = true
            }
        }
        // The question, with what goes with it. Not asked of what cannot go.
        SettingsCard {
            Layout.fillWidth: true
            visible: root.confirming && root.removable && root.entry !== null && root.blocked.length === 0
            glyph: "delete"
            text: root.origin === "user" ? Translation.tr("Move its entry to the trash?")
                : root.origin === "steam" ? Translation.tr("Steam asks for itself before it takes the game off")
                : Translation.tr("Take %1 off?").arg(root.entry?.name ?? root.appId)
            description: (root.details?.removes ?? []).length > 1 ? Translation.tr("Goes with it: %1").arg(root.details.removes.join(", ")) : ""

            ExButton {
                kind: "control"
                text: Translation.tr("Cancel")
                enabled: !remover.running
                onClicked: root.confirming = false
            }
            ExButton {
                kind: "accent"
                text: root.origin === "user" ? Translation.tr("Move to trash") : Translation.tr("Uninstall")
                enabled: !remover.running
                onClicked: root.remove()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Starting")
        visible: root.entry !== null

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
        visible: root.entry !== null

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
