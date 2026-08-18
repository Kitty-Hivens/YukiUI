pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core.services
import qs.core
import qs.common.widgets
import qs.ii.systemSettings
import qs.common

/**
 * What the window opens on: what this machine is, what it is doing right now,
 * and the way into everything else.
 *
 * The sections come from the same catalogue the navigation reads, so a page
 * added there appears here without this file knowing about it.
 */
Item {
    id: root

    // Navigation belongs to the window. The page only says where it wants to go.
    signal navigate(string component)

    readonly property bool wide: root.width > 1000
    readonly property var sections: SystemPages.pages.filter(page => page.component !== SystemPages.homeComponent)

    // Reading a filesystem costs a process, so it only happens while the page
    // that shows the figure is the one open.
    Component.onCompleted: ResourceUsage.storageWatchers++
    Component.onDestruction: ResourceUsage.storageWatchers--

    function gb(kb) {
        return (kb / (1024 * 1024)).toFixed(1);
    }

    function pairGb(used, total) {
        return `${root.gb(used)} / ${root.gb(total)} GB`;
    }

    function percent(fraction) {
        return `${Math.round(fraction * 100)}%`;
    }

    // lscpu answers with nothing on a machine that does not publish a maximum,
    // and the parsed figure is then not a number.
    readonly property string cpuClock: {
        const clock = ResourceUsage.maxAvailableCpuString;
        return clock.indexOf("NaN") === -1 && clock.indexOf("--") === -1 ? clock : "";
    }

    readonly property var facts: [
        {
            label: Translation.tr("Model"),
            value: SystemInfo.deviceModel
        },
        {
            label: Translation.tr("CPU"),
            value: SystemInfo.cpuModel
        },
        {
            label: Translation.tr("RAM"),
            value: ResourceUsage.maxAvailableMemoryString
        },
        {
            label: Translation.tr("Kernel"),
            value: SystemInfo.kernel
        },
        {
            // Not the windowing system as well: Hyprland runs on one of them.
            label: Translation.tr("Compositor"),
            value: [SystemInfo.desktopEnvironment, SystemInfo.compositorVersion].filter(part => part.length > 0).join(" ")
        },
        {
            label: Translation.tr("Uptime"),
            value: DateTime.uptime
        }
        // A machine that reports nothing for a field is not worth a blank row.
    ].filter(fact => fact.value.length > 0)

    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 4
        font.pixelSize: Appearance.font.pixelSize.smallie
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            // Positioned rather than anchored: inside a flickable the content
            // item is what scrolls, so filling it would pin the page in place.
            y: 16
            x: Math.max(20, (pageFlick.width - width) / 2)
            width: Math.min(pageFlick.width - 40, 1180)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.wide ? 2 : 1
                    columnSpacing: 28
                    rowSpacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        // Centred against the facts beside it, which are taller:
                        // top aligned, the machine's name sat alone above a gap.
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 16

                        IconImage {
                            implicitSize: 64
                            source: Quickshell.iconPath(SystemInfo.logo)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: SystemInfo.hostname
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.variableAxes: ({
                                    "wght": 600
                                })
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: SystemInfo.distroName
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: !root.wide
                        Layout.preferredWidth: root.wide ? 430 : -1
                        Layout.alignment: Qt.AlignTop
                        spacing: 3

                        Repeater {
                            model: root.facts

                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 16

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    text: modelData.value
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 6

                    RippleButtonWithIcon {
                        materialIcon: "format_paint"
                        mainText: Translation.tr("Appearance")
                        onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("appearanceSettings.qml")])
                    }
                    RippleButtonWithIcon {
                        materialIcon: "edit"
                        mainText: Translation.tr("Config file")
                        onClicked: Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`)
                    }
                }
            }

            Heading {
                text: Translation.tr("Resources")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 4 : 2
                columnSpacing: 12
                rowSpacing: 12

                StatTile {
                    Layout.fillWidth: true
                    icon: "developer_board"
                    label: Translation.tr("CPU")
                    value: root.percent(ResourceUsage.cpuUsage)
                    detail: root.cpuClock.length > 0
                        ? `${root.cpuClock} · ${Translation.tr("Threads: %1").arg(SystemInfo.cpuThreads)}`
                        : Translation.tr("Threads: %1").arg(SystemInfo.cpuThreads)
                    fraction: ResourceUsage.cpuUsage
                    history: ResourceUsage.cpuUsageHistory
                }
                StatTile {
                    Layout.fillWidth: true
                    icon: "memory"
                    label: Translation.tr("RAM")
                    value: root.percent(ResourceUsage.memoryUsedPercentage)
                    detail: root.pairGb(ResourceUsage.memoryUsed, ResourceUsage.memoryTotal)
                    fraction: ResourceUsage.memoryUsedPercentage
                    history: ResourceUsage.memoryUsageHistory
                }
                StatTile {
                    Layout.fillWidth: true
                    icon: "swap_horiz"
                    label: Translation.tr("Swap")
                    value: ResourceUsage.swapTotal > 0 ? root.percent(ResourceUsage.swapUsedPercentage) : "--"
                    detail: ResourceUsage.swapTotal > 0
                        ? root.pairGb(ResourceUsage.swapUsed, ResourceUsage.swapTotal)
                        : Translation.tr("Not configured")
                    fraction: ResourceUsage.swapUsedPercentage
                    history: ResourceUsage.swapTotal > 0 ? ResourceUsage.swapUsageHistory : []
                }
                StatTile {
                    Layout.fillWidth: true
                    icon: "storage"
                    label: Translation.tr("Storage")
                    value: ResourceUsage.storageTotal > 0 ? root.percent(ResourceUsage.storageUsedPercentage) : "--"
                    detail: ResourceUsage.storageTotal > 0
                        ? root.pairGb(ResourceUsage.storageUsed, ResourceUsage.storageTotal)
                        : ResourceUsage.storagePath
                    fraction: ResourceUsage.storageUsedPercentage
                }
            }

            Heading {
                text: Translation.tr("Settings")
            }

            Repeater {
                model: root.sections

                delegate: SectionRow {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.name
                    description: modelData.description
                    status: modelData.status
                    onClicked: root.navigate(modelData.component)
                }
            }
        }
    }
}
