pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.core.services
import qs.common.widgets
import qs.ii.systemSettings
import qs.common

/**
 * What opens what, asked the way a person asks it.
 *
 * The desktop stores this per MIME type while a person thinks in categories --
 * "what opens my pictures", not "what opens image/webp as opposed to image/png".
 * The two drift apart on their own and nothing says so: this machine had five
 * viewers across six image formats and a text editor on HTML.
 *
 * A category whose types point at different applications is shown as a fact, not
 * a fault. Markdown in one editor and shell scripts in a terminal is somebody
 * deciding; PNG and JPEG in different viewers is drift. Only the person reading
 * can tell which is which.
 *
 * The reading itself lives in [DefaultApps] rather than here: the window rebuilds
 * a page from scratch on every navigation, and a scan of every installed
 * application is not something to repeat each time somebody comes back.
 */
Item {
    id: root

    property string openRow: ""

    Component.onCompleted: DefaultApps.load()

    /** One application, offered inside an opened category. */
    component ApplicationChoice: RippleButton {
        id: choice
        required property var entry
        required property bool current
        required property string groupKey

        Layout.fillWidth: true
        implicitHeight: 46
        buttonRadius: Appearance.rounding.small
        toggled: choice.current
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        onClicked: {
            if (!choice.current)
                DefaultApps.assign(choice.groupKey, choice.entry.id);
            root.openRow = "";
        }

        contentItem: RowLayout {
            spacing: 12

            IconImage {
                Layout.leftMargin: 10
                implicitSize: 24
                source: Quickshell.iconPath(choice.entry.icon, "application-x-executable")
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    text: choice.entry.name
                    elide: Text.ElideRight
                    color: choice.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }
                // Two applications can carry the same name. Where they do, the id
                // is the only thing that tells them apart.
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    visible: choice.entry.ambiguous
                    text: choice.entry.id.replace(".desktop", "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            // Said out loud, because choosing a partial handler is how a category
            // asked to agree ends up more split than it started.
            StyledText {
                visible: choice.entry.covers < choice.entry.total
                text: Translation.tr("%1 of %2").arg(choice.entry.covers).arg(choice.entry.total)
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }

            MaterialSymbol {
                Layout.rightMargin: 10
                visible: choice.current
                text: "check"
                iconSize: 18
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            PageNote {
                visible: DefaultApps.error.length > 0
                text: DefaultApps.error
                color: Appearance.m3colors.m3error
            }

            PageNote {
                visible: !DefaultApps.ready && DefaultApps.error.length === 0
                text: Translation.tr("Reading what is installed...")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: DefaultApps.ready

                Repeater {
                    model: DefaultApps.groups

                    delegate: ColumnLayout {
                        id: groupRow
                        required property var modelData
                        required property int index
                        readonly property bool open: root.openRow === modelData.key
                        readonly property var chosen: modelData.candidates.find(entry => entry.id === modelData.current) ?? null

                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: groupRow.index > 0
                        }

                        // The whole row opens it. A chevron alone is a target the
                        // width of a fingernail on a row the width of the window.
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.openRow = groupRow.open ? "" : groupRow.modelData.key

                            contentItem: RowLayout {
                                spacing: 12

                                MaterialSymbol {
                                    Layout.leftMargin: 8
                                    text: groupRow.modelData.icon
                                    iconSize: Appearance.font.pixelSize.hugeass
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    text: Translation.tr(groupRow.modelData.name)
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnLayer2
                                }

                                // The application when the category agrees on one,
                                // and an honest word when it does not: naming one
                                // of several would hide the split.
                                StyledText {
                                    Layout.maximumWidth: 220
                                    text: groupRow.modelData.agreed
                                        ? (groupRow.chosen?.name ?? groupRow.modelData.current)
                                        : Translation.tr("several")
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }

                                MaterialSymbol {
                                    Layout.rightMargin: 10
                                    text: "expand_more"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                    rotation: groupRow.open ? 180 : 0
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }
                        }

                        Revealer {
                            id: revealer
                            Layout.fillWidth: true
                            vertical: true
                            reveal: groupRow.open

                            ColumnLayout {
                                width: revealer.width
                                spacing: 6

                                // What the category is made of, shown only when the
                                // answer is not one word.
                                PageNote {
                                    Layout.leftMargin: 8
                                    visible: !groupRow.modelData.agreed
                                    text: Object.keys(groupRow.modelData.perType)
                                        .filter(type => groupRow.modelData.perType[type].length > 0)
                                        .map(type => `${type} -> ${groupRow.modelData.perType[type].replace(".desktop", "")}`)
                                        .join("\n")
                                }

                                PageNote {
                                    Layout.leftMargin: 8
                                    visible: groupRow.modelData.missing.length > 0
                                    text: Translation.tr("Nothing is set for: %1").arg(groupRow.modelData.missing.join(", "))
                                }

                                PageNote {
                                    Layout.leftMargin: 8
                                    visible: groupRow.modelData.candidates.length === 0
                                    text: Translation.tr("No installed application declares these types.")
                                }

                                PageNote {
                                    Layout.leftMargin: 8
                                    visible: groupRow.modelData.candidates.length > 0
                                    text: Translation.tr("Whole-category handlers first. A number means the application takes only part of the group and leaves the rest where they are.")
                                }

                                Repeater {
                                    model: groupRow.modelData.candidates

                                    delegate: ApplicationChoice {
                                        required property var modelData
                                        entry: modelData
                                        groupKey: groupRow.modelData.key
                                        current: modelData.id === groupRow.modelData.current
                                    }
                                }

                                Item {
                                    Layout.preferredHeight: 6
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
