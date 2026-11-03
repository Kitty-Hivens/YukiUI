pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// The bar along the top: a button for each widget, game mode, the time, and
// closing.
ExSurface {
    id: root

    /** The game bar, whose widgets the buttons show and hide. */
    required property var bar

    readonly property var gameMode: ExQuickTiles.info("gameMode")

    /** On screen: it comes down from the top. */
    property bool shown: false
    property real arrival: root.shown ? 1 : 0
    Behavior on arrival {
        NumberAnimation {
            duration: ExLooks.motion.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ExLooks.motion.decelerate
        }
    }
    opacity: root.arrival
    transform: Translate {
        y: -(1 - root.arrival) * 16
    }

    implicitWidth: tools.implicitWidth + 2 * ExLooks.spacing.s
    implicitHeight: tools.implicitHeight + 2 * ExLooks.spacing.s
    color: ExLooks.colors.glass
    radius: ExLooks.radius.panel
    elevation: 1

    component Rule: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 1
        implicitHeight: 24
        color: ExLooks.colors.border
    }

    // A click on the bar between its buttons is not a click beside it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    RowLayout {
        id: tools

        anchors.centerIn: parent
        spacing: ExLooks.spacing.xs

        Repeater {
            model: [
                { key: "capture", glyph: "screen_record" },
                { key: "audio", glyph: "volume_up" },
                { key: "performance", glyph: "monitoring" }
            ]

            ExToolButton {
                required property var modelData

                glyph: modelData.glyph
                toggled: root.bar.isShown(modelData.key)
                onClicked: root.bar.setShown(modelData.key, !toggled)
            }
        }

        Rule {}

        ExToolButton {
            glyph: "sports_esports"
            text: root.gameMode.text
            toggled: root.gameMode.checked
            onClicked: ExQuickTiles.run("gameMode")
        }

        Rule {}

        ExText {
            Layout.leftMargin: ExLooks.spacing.s
            Layout.rightMargin: ExLooks.spacing.s
            text: DateTime.time
            role: "title"
            font.features: ({ "tnum": 1 })
        }

        Rule {}

        ExToolButton {
            glyph: "close"
            onClicked: root.bar.close()
        }
    }
}
