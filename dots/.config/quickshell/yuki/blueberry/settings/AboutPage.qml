pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// What this machine is: its name, what it is made of, what runs on it, and how
// full its disks are. The name is the one thing here to change. It goes through
// hostnamed, which asks for a password.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var made: [
        { glyph: "laptop_chromebook", label: Translation.tr("Model"), value: SystemInfo.deviceModel },
        { glyph: "developer_board", label: Translation.tr("CPU"), value: SystemInfo.cpuThreads > 0 ? Translation.tr("%1, %2 threads").arg(SystemInfo.cpuModel).arg(SystemInfo.cpuThreads) : SystemInfo.cpuModel },
        { glyph: "videogame_asset", label: Translation.tr("Graphics"), value: SystemInfo.graphics },
        { glyph: "memory", label: Translation.tr("RAM"), value: root.memory }
        // A machine that reports nothing for a field is not worth a blank row.
    ].filter(fact => fact.value.length > 0)
    readonly property var running: [
        { glyph: "deployed_code", label: Translation.tr("Distribution"), value: SystemInfo.distroName },
        { glyph: "terminal", label: Translation.tr("Kernel"), value: SystemInfo.kernel },
        { glyph: "layers", label: Translation.tr("Compositor"), value: [SystemInfo.desktopEnvironment, SystemInfo.compositorVersion].filter(part => part.length > 0).join(" ") },
        { glyph: "schedule", label: Translation.tr("Uptime"), value: DateTime.uptime }
    ].filter(fact => fact.value.length > 0)
    readonly property var links: [
        { glyph: "public", label: Translation.tr("Website of the distribution"), url: SystemInfo.homeUrl },
        { glyph: "auto_stories", label: Translation.tr("Documentation of the distribution"), url: SystemInfo.documentationUrl },
        { glyph: "bug_report", label: Translation.tr("Report a bug in the distribution"), url: SystemInfo.bugReportUrl },
        { glyph: "code", label: Translation.tr("YukiUI source code"), url: "https://github.com/Kitty-Hivens/YukiUI" }
    ].filter(link => link.url.length > 0)

    /** All of it as text, for a bug report. */
    function asText(): string {
        return [SystemInfo.hostname, ...root.made, ...root.running]
            .map(fact => typeof fact === "string" ? fact : `${fact.label}: ${fact.value}`).join("\n");
    }

    // A name may have letters, digits and dashes, and not start with a dash.
    readonly property bool nameValid: /^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(nameField.text)
    readonly property bool nameEdited: nameField.text !== SystemInfo.hostname
    property string renameFailure: ""
    property bool renamed: false

    property string memory: ""

    spacing: ExLooks.settings.groupGap

    DiskUsage {
        id: usage
    }

    FileView {
        path: "/proc/meminfo"
        blockLoading: true
        onLoaded: {
            const kilobytes = Number(/^MemTotal:\s+(\d+)/m.exec(text())?.[1] ?? 0);
            if (kilobytes > 0)
                root.memory = usage.bytes(kilobytes * 1024);
        }
    }

    Process {
        id: rename
        property string wanted: ""
        command: ["hostnamectl", "set-hostname", rename.wanted]
        onExited: exitCode => {
            if (exitCode === 0) {
                SystemInfo.hostname = rename.wanted;
                root.renamed = true;
                root.renameFailure = "";
            } else {
                root.renameFailure = Translation.tr("The name was not changed");
            }
        }
    }

    component Fact: SettingsCard {
        id: fact

        required property var modelData

        Layout.fillWidth: true
        glyph: fact.modelData.glyph
        text: fact.modelData.label

        ExText {
            width: Math.min(implicitWidth, root.width * 0.62)
            text: fact.modelData.value
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            dim: true
        }
    }

    SettingsSection {
        Layout.fillWidth: true

        SettingsCard {
            Layout.fillWidth: true
            glyph: "computer"
            text: Translation.tr("Device name")
            description: root.renameFailure.length > 0 ? root.renameFailure
                : root.renamed ? Translation.tr("Applications already open keep the old name until they restart")
                : ""

            ExTextField {
                id: nameField
                width: 220
                text: SystemInfo.hostname
            }
            ExButton {
                visible: root.nameEdited
                kind: "accent"
                enabled: root.nameValid && !rename.running
                text: Translation.tr("Rename")
                onClicked: {
                    rename.wanted = nameField.text;
                    rename.running = true;
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("What it is made of")

        Repeater {
            model: root.made
            Fact {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("What runs on it")

        Repeater {
            model: root.running
            Fact {}
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Storage")

        Repeater {
            model: usage.disks

            SettingsCard {
                id: disk

                required property var modelData

                glyph: "hard_drive"
                text: disk.modelData.target === "/" ? Translation.tr("System disk") : disk.modelData.target
                description: Translation.tr("%1 of %2 used").arg(usage.bytes(disk.modelData.used)).arg(usage.bytes(disk.modelData.size))

                SettingsMeter {
                    width: 140
                    value: disk.modelData.share
                    warn: disk.modelData.share > 0.9
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("More")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "content_copy"
            text: Translation.tr("Copy these details")

            ExButton {
                kind: "control"
                text: Translation.tr("Copy")
                onClicked: Quickshell.clipboardText = root.asText()
            }
        }
        Repeater {
            model: root.links

            SettingsCard {
                id: link

                required property var modelData

                glyph: link.modelData.glyph
                text: link.modelData.label
                leads: true
                onClicked: Qt.openUrlExternally(link.modelData.url)
            }
        }
    }
}
