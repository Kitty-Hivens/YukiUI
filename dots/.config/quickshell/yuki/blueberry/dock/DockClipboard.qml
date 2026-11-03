pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// The clipboard history on Win+V, out of the middle of the dock: what was
// copied lately, newest first, text, pictures and files alike. A click, or
// Enter, puts one back on the clipboard and pastes it into the window that was
// in use. Each can be pinned to stay, or deleted, and the rest cleared. The
// arrows, Enter, Delete and Escape work as they look, the keys reaching it
// through the dock as a password field in quick settings does.
ExPopup {
    id: root

    /** The entry the keys are on. */
    property int current: 0

    /** What the dock hands the keys to while this is open. */
    readonly property Item keyTarget: root.open ? keys : null

    onOpenChanged: {
        ExClipboardHistory.open = root.open;
        if (root.open)
            root.current = 0;
    }

    padding: ExLooks.spacing.m
    motion: "panel"
    onDismissRequested: root.open = false

    Item {
        id: keys

        Keys.onPressed: event => {
            const entries = ExClipboardHistory.entries;
            if (event.key === Qt.Key_Escape) {
                root.open = false;
            } else if (event.key === Qt.Key_Down && entries.length > 0) {
                root.current = Math.min(entries.length - 1, root.current + 1);
            } else if (event.key === Qt.Key_Up && entries.length > 0) {
                root.current = Math.max(0, root.current - 1);
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && entries.length > 0) {
                ExClipboardHistory.choose(entries[root.current].id);
            } else if (event.key === Qt.Key_Delete && entries.length > 0) {
                ExClipboardHistory.run("delete", entries[root.current].id);
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    // One entry: what it holds, and pin and delete over its corner while it
    // is pointed at or chosen.
    component Card: Item {
        id: card

        required property var modelData
        required property int index
        readonly property bool here: card.index === root.current
        readonly property bool pinned: card.modelData.pinned === true

        width: ListView.view.width
        implicitHeight: Math.max(48, body.implicitHeight + 2 * ExLooks.spacing.m)

        Rectangle {
            id: plate

            anchors.fill: parent
            radius: ExLooks.radius.card
            color: card.here ? ExLooks.colors.tonal : ExLooks.colors.surfaceSunken

            ExStateLayer {
                ink: ExLooks.colors.text
                hovered: press.containsMouse
                pressed: press.pressed
            }
        }

        MouseArea {
            id: press

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onEntered: root.current = card.index
            onClicked: ExClipboardHistory.choose(card.modelData.id)
        }

        ColumnLayout {
            id: body

            x: ExLooks.spacing.m
            y: ExLooks.spacing.m
            width: card.width - 2 * ExLooks.spacing.m
            spacing: ExLooks.spacing.xs

            ExText {
                visible: card.modelData.kind === "text"
                Layout.fillWidth: true
                text: card.modelData.preview.trim()
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            ClippingRectangle {
                id: thumbnail

                readonly property real ratio: picture.implicitWidth > 0 ? picture.implicitHeight / picture.implicitWidth : 0.6

                visible: card.modelData.kind === "image"
                Layout.preferredWidth: Math.min(body.width, 112 / Math.max(0.01, thumbnail.ratio))
                Layout.preferredHeight: Math.min(112, body.width * thumbnail.ratio)
                radius: ExLooks.radius.menuItem
                color: ExLooks.colors.control

                Image {
                    id: picture
                    anchors.fill: parent
                    source: thumbnail.visible ? FileUtils.fileUrl(card.modelData.image) : ""
                    sourceSize.width: 480
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            Repeater {
                model: card.modelData.kind === "files" ? card.modelData.preview.split("\n").slice(0, 3) : []

                RowLayout {
                    required property string modelData

                    Layout.fillWidth: true
                    spacing: ExLooks.spacing.s

                    ExGlyph {
                        text: "draft"
                        size: 18
                        color: ExLooks.colors.textDim
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideMiddle
                    }
                }
            }
            ExText {
                readonly property int more: card.modelData.kind === "files" ? card.modelData.preview.split("\n").length - 3 : 0
                visible: more > 0
                text: Translation.tr("and %1 more").arg(more)
                role: "caption"
                dim: true
            }
        }

        // Pinned, it says so in its corner while nothing points at it.
        ExGlyph {
            visible: card.pinned && !tools.visible
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ExLooks.spacing.s
            text: "keep"
            size: 16
            fill: 1
            color: ExLooks.colors.accent
        }

        Rectangle {
            id: tools

            visible: card.here || press.containsMouse
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ExLooks.spacing.xs
            width: row.implicitWidth + 4
            height: row.implicitHeight + 4
            radius: ExLooks.radius.control
            color: plate.color

            Row {
                id: row

                anchors.centerIn: parent
                spacing: 2

                ExToolButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    glyph: "keep"
                    toggled: card.pinned
                    onClicked: ExClipboardHistory.run("pin", card.modelData.id, card.pinned ? "0" : "1")
                }
                ExToolButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    glyph: "delete"
                    onClicked: ExClipboardHistory.run("delete", card.modelData.id)
                }
            }
        }
    }

    ColumnLayout {
        width: 360
        spacing: ExLooks.spacing.s

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: ExLooks.spacing.xs

            ExText {
                Layout.fillWidth: true
                text: Translation.tr("Clipboard")
                role: "label"
                font.weight: ExLooks.font.weightTitle
            }
            ExButton {
                kind: "flat"
                implicitHeight: 30
                text: Translation.tr("Clear all")
                enabled: ExClipboardHistory.entries.some(entry => !entry.pinned)
                onClicked: ExClipboardHistory.run("clear")
            }
        }

        // Nothing yet.
        ColumnLayout {
            visible: ExClipboardHistory.entries.length === 0
            Layout.fillWidth: true
            Layout.topMargin: ExLooks.spacing.l
            Layout.bottomMargin: ExLooks.spacing.l
            spacing: ExLooks.spacing.xs

            ExGlyph {
                Layout.alignment: Qt.AlignHCenter
                text: "content_paste"
                size: 32
                color: ExLooks.colors.textDim
            }
            ExText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Nothing copied yet")
                role: "label"
            }
            ExText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Copy something to see it here.")
                role: "caption"
                dim: true
            }
        }

        ListView {
            id: list

            visible: ExClipboardHistory.entries.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(440, list.contentHeight)
            spacing: ExLooks.spacing.xs
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ExClipboardHistory.entries
            currentIndex: root.current
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

            delegate: Card {}
        }
    }
}
