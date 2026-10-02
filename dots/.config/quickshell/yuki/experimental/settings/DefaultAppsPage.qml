pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.core.services
import qs.experimental.looks

// What opens what, a category at a time: links, pictures, text. The desktop
// keeps it per type of file, so a category can be split between applications,
// and then the card says so rather than naming one of them.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    Component.onCompleted: DefaultApps.load()

    spacing: 4

    // A category, with the application that opens it and the list to change it.
    component GroupCard: SettingsCard {
        id: group

        required property var modelData
        readonly property var chosen: group.modelData.candidates.find(entry => entry.id === group.modelData.current) ?? null
        readonly property var split: Object.keys(group.modelData.perType)
            .filter(type => group.modelData.perType[type].length > 0)
            .map(type => `${type}: ${group.modelData.perType[type].replace(".desktop", "")}`)

        Layout.fillWidth: true
        glyph: group.modelData.icon
        text: Translation.tr(group.modelData.name)
        description: group.modelData.candidates.length === 0 ? Translation.tr("No installed application opens these")
            : !group.modelData.agreed ? Translation.tr("Different applications open different kinds")
            : group.modelData.missing.length > 0 ? Translation.tr("Nothing is set for %1").arg(group.modelData.missing.join(", "))
            : ""

        ExButton {
            id: current

            kind: "control"
            enabled: group.modelData.candidates.length > 0 && !DefaultApps.busy
            implicitWidth: Math.min(300, Math.max(200, currentName.implicitWidth + 80))
            onClicked: picker.visible ? picker.close() : picker.open()

            contentItem: RowLayout {
                spacing: ExLooks.spacing.s

                IconImage {
                    Layout.leftMargin: ExLooks.spacing.m
                    visible: group.chosen !== null
                    implicitSize: 18
                    source: group.chosen ? Quickshell.iconPath(group.chosen.icon, "application-x-executable") : ""
                }
                ExText {
                    id: currentName
                    Layout.fillWidth: true
                    Layout.leftMargin: group.chosen ? 0 : ExLooks.spacing.m
                    text: group.chosen?.name ?? (group.modelData.agreed ? Translation.tr("Not set") : Translation.tr("Several applications"))
                    role: "label"
                    elide: Text.ElideRight
                    color: current.ink
                }
                ExGlyph {
                    Layout.rightMargin: ExLooks.spacing.m
                    text: "expand_more"
                    size: 18
                    color: current.ink
                }
            }

            Popup {
                id: picker

                readonly property real rowHeight: 44
                readonly property real headHeight: head.visible ? head.implicitHeight + ExLooks.spacing.s : 0

                x: current.width - picker.width
                y: current.height + 4
                width: 340
                height: Math.min(420, picker.headHeight + group.modelData.candidates.length * picker.rowHeight + 2 * ExLooks.sizes.menuPadding)
                // Kept inside the window, moved up rather than cut off.
                margins: ExLooks.spacing.s
                padding: 0
                focus: true
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                background: null

                contentItem: ExSurface {
                    radius: ExLooks.radius.menu
                    elevation: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: ExLooks.sizes.menuPadding
                        spacing: ExLooks.spacing.s

                        // How the category is split now, so the choice below is
                        // made knowing what it replaces.
                        ExText {
                            id: head
                            Layout.fillWidth: true
                            Layout.leftMargin: ExLooks.spacing.s
                            Layout.rightMargin: ExLooks.spacing.s
                            Layout.topMargin: ExLooks.spacing.xs
                            visible: !group.modelData.agreed && group.split.length > 0
                            text: group.split.join("\n")
                            role: "caption"
                            dim: true
                            wrapMode: Text.Wrap
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: group.modelData.candidates

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            delegate: AbstractButton {
                                id: choice

                                ExPrimaryOnly {
                                    z: 1
                                }

                                required property var modelData
                                readonly property bool current: choice.modelData.id === group.modelData.current

                                width: ListView.view.width
                                height: picker.rowHeight
                                hoverEnabled: true
                                onClicked: {
                                    picker.close();
                                    if (!choice.current)
                                        DefaultApps.assign(group.modelData.key, choice.modelData.id);
                                }

                                background: Rectangle {
                                    radius: ExLooks.radius.menuItem
                                    color: choice.current ? ExLooks.colors.tonal : "transparent"

                                    ExStateLayer {
                                        ink: ExLooks.colors.text
                                        hovered: choice.hovered
                                        pressed: choice.down
                                    }
                                }

                                contentItem: RowLayout {
                                    spacing: ExLooks.spacing.m

                                    IconImage {
                                        Layout.leftMargin: ExLooks.spacing.s + 2
                                        implicitSize: 24
                                        source: Quickshell.iconPath(choice.modelData.icon, "application-x-executable")
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        ExText {
                                            Layout.fillWidth: true
                                            text: choice.modelData.name
                                            elide: Text.ElideRight
                                        }
                                        // Two applications can carry one name, and
                                        // then only the id tells them apart.
                                        ExText {
                                            Layout.fillWidth: true
                                            visible: choice.modelData.ambiguous
                                            text: choice.modelData.id.replace(".desktop", "")
                                            role: "caption"
                                            dim: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                    // An application that takes only part of the
                                    // category leaves the rest where it is.
                                    ExText {
                                        visible: choice.modelData.covers < choice.modelData.total
                                        text: Translation.tr("%1 of %2").arg(choice.modelData.covers).arg(choice.modelData.total)
                                        role: "caption"
                                        dim: true
                                    }
                                    ExGlyph {
                                        Layout.rightMargin: ExLooks.spacing.s + 2
                                        text: "check"
                                        size: 18
                                        opacity: choice.current ? 1 : 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: DefaultApps.error.length > 0
        glyph: "error"
        text: DefaultApps.error
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: DefaultApps.assignError.length > 0
        glyph: "error"
        text: DefaultApps.assignError

        ExButton {
            kind: "control"
            text: Translation.tr("Got it")
            onClicked: DefaultApps.assignError = ""
        }
    }
    ExText {
        visible: !DefaultApps.ready && DefaultApps.error.length === 0
        Layout.leftMargin: ExLooks.spacing.l
        text: Translation.tr("Reading what is installed...")
        dim: true
    }

    Repeater {
        model: DefaultApps.groups
        GroupCard {}
    }
}
