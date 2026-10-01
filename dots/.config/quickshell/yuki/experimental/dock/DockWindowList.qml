import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core.services
import qs.experimental.looks

// The windows of an application that has several on the workspace, opened from
// its dock button as a row of live thumbnails, the way a Windows taskbar shows
// them. Picking one brings it up, restores it if it was minimised, or minimises
// it when it is the one already in front. The cross on a hovered card closes
// that window.
ExPopup {
    id: root

    readonly property var windows: root.opener?.windows ?? []
    readonly property string appId: root.opener?.entry?.appId ?? ""
    readonly property bool vertical: root.edge === "left" || root.edge === "right"

    readonly property real thumbWidth: 200
    readonly property real thumbHeight: 116

    padding: ExLooks.spacing.s
    surfaceRadius: ExLooks.radius.tile

    onDismissRequested: root.open = false
    // Nothing left to pick from once the group is down to one window or none.
    onWindowsChanged: {
        if (root.open && root.windows.length < 2)
            root.open = false;
    }

    // As many cards in a row as the screen has room for, then another row: a
    // single row of nine ran off the screen. Down a side dock, as many in a
    // column as fit, then another column.
    readonly property real cardWidth: root.thumbWidth + 2 * ExLooks.spacing.s
    readonly property real cardHeight: 24 + root.thumbHeight + 3 * ExLooks.spacing.s
    readonly property real room: (root.vertical ? root.dockWindow.height : root.dockWindow.width) - 2 * (root.padding + root.gap + ExLooks.spacing.l)
    readonly property int perLine: Math.max(1, Math.floor((root.room + ExLooks.spacing.xs) / ((root.vertical ? root.cardHeight : root.cardWidth) + ExLooks.spacing.xs)))

    Grid {
        columns: root.vertical ? Math.max(1, Math.ceil(root.windows.length / root.perLine)) : Math.max(1, Math.min(root.windows.length, root.perLine))
        spacing: ExLooks.spacing.xs

        Repeater {
            model: root.windows

            AbstractButton {
                id: card

                required property var modelData
                readonly property bool minimized: TaskbarApps.isMinimized(card.modelData)
                readonly property bool front: card.modelData.activated && !card.minimized

                implicitWidth: root.thumbWidth + 2 * ExLooks.spacing.s
                implicitHeight: header.height + root.thumbHeight + 3 * ExLooks.spacing.s
                hoverEnabled: true

                onClicked: {
                    TaskbarApps.toggleWindow(card.modelData);
                    root.open = false;
                }

                background: Rectangle {
                    radius: ExLooks.radius.control
                    color: card.front ? ExLooks.colors.tonal : "transparent"

                    ExStateLayer {
                        ink: ExLooks.colors.text
                        hovered: card.hovered
                        pressed: card.down
                    }
                }

                contentItem: Item {
                    RowLayout {
                        id: header

                        x: ExLooks.spacing.s
                        y: ExLooks.spacing.s
                        width: root.thumbWidth
                        height: 24
                        spacing: ExLooks.spacing.s

                        IconImage {
                            implicitSize: 16
                            source: AppSearch.iconFor(root.appId)
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: card.modelData.title
                            role: "label"
                            dim: card.minimized
                        }
                        // Shown on the card under the pointer, where the title makes room for it.
                        ExButton {
                            visible: card.hovered
                            kind: "flat"
                            implicitWidth: 24
                            implicitHeight: 24
                            onClicked: TaskbarApps.closeWindow(card.modelData)

                            ExGlyph {
                                anchors.centerIn: parent
                                text: "close"
                                size: 16
                            }
                        }
                    }

                    Rectangle {
                        x: ExLooks.spacing.s
                        y: header.y + header.height + ExLooks.spacing.s
                        width: root.thumbWidth
                        height: root.thumbHeight
                        radius: ExLooks.radius.menuItem
                        color: ExLooks.colors.surfaceSunken
                        clip: true

                        // Captured only while the list is open. A minimised window
                        // is not drawn at all, so it has no picture to show and gets
                        // its application's icon instead of an empty frame.
                        ScreencopyView {
                            anchors.centerIn: parent
                            visible: !card.minimized
                            captureSource: root.open && !card.minimized ? card.modelData : null
                            live: true
                            paintCursor: false
                            constraintSize: Qt.size(root.thumbWidth, root.thumbHeight)
                        }
                        IconImage {
                            anchors.centerIn: parent
                            visible: card.minimized
                            implicitSize: 48
                            source: AppSearch.iconFor(root.appId)
                            opacity: 0.6
                        }
                    }
                }
            }
        }
    }
}
