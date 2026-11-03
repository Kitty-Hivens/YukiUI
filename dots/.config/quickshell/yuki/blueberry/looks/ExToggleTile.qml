import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A quick setting: a state that is on or off, and optionally a page behind it.
 *
 * With a page, the tile is two buttons in one plate, as on Windows: most of it
 * switches the state, and the part with the arrow at its end opens the page.
 */
AbstractButton {
    id: root

    ExPrimaryOnly {
        z: 1
    }

    property string glyph: ""
    property string subtitle: ""
    property bool hasMenu: false
    property string previewState: ""
    /** The plate while off. */
    property color restFill: ExLooks.colors.control

    signal menuRequested

    readonly property color fill: checked ? ExLooks.colors.accent : root.restFill
    readonly property color ink: checked ? ExLooks.colors.accentInk : ExLooks.colors.controlInk
    readonly property real menuWidth: 44

    checkable: true
    hoverEnabled: true
    implicitHeight: ExLooks.sizes.tileHeight
    implicitWidth: 180

    background: Rectangle {
        radius: ExLooks.radius.tile
        color: root.fill

        Behavior on color {
            ColorAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }

        // The wash of the switching part, which stops where the arrow begins.
        Rectangle {
            x: 0
            width: root.hasMenu ? parent.width - root.menuWidth : parent.width
            height: parent.height
            topLeftRadius: parent.radius
            bottomLeftRadius: parent.radius
            topRightRadius: root.hasMenu ? 0 : parent.radius
            bottomRightRadius: root.hasMenu ? 0 : parent.radius
            color: root.ink
            readonly property bool showPress: root.previewState === "pressed" || (root.previewState === "" && root.down)
            readonly property bool showHover: root.previewState === "hover" || (root.previewState === "" && root.hovered && !more.hovered)
            opacity: showPress ? ExLooks.colors.pressOpacity : (showHover ? ExLooks.colors.hoverOpacity : 0)

            Behavior on opacity {
                NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }
        }
    }

    contentItem: RowLayout {
        spacing: ExLooks.spacing.m

        ExGlyph {
            Layout.leftMargin: ExLooks.spacing.m + 2
            text: root.glyph
            fill: root.checked ? 1 : 0
            color: root.ink
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.rightMargin: root.hasMenu ? root.menuWidth : ExLooks.spacing.m
            spacing: 0
            ExText {
                Layout.fillWidth: true
                text: root.text
                role: "label"
                color: root.ink
            }
            ExText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                role: "caption"
                color: root.ink
                opacity: 0.8
            }
        }
    }

    // The page behind it.
    AbstractButton {
        id: more

        ExPrimaryOnly {
            z: 1
        }

        visible: root.hasMenu
        anchors.right: parent.right
        width: root.menuWidth
        height: parent.height
        hoverEnabled: true
        onClicked: root.menuRequested()

        background: Item {
            Rectangle {
                anchors.fill: parent
                topRightRadius: ExLooks.radius.tile
                bottomRightRadius: ExLooks.radius.tile
                color: root.ink
                opacity: more.down ? ExLooks.colors.pressOpacity : (more.hovered ? ExLooks.colors.hoverOpacity : 0)

                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }
            }
            // A short rule between the two parts.
            Rectangle {
                width: 1
                height: parent.height * 0.5
                anchors.verticalCenter: parent.verticalCenter
                color: root.ink
                opacity: 0.2
            }
        }
        contentItem: Item {
            ExGlyph {
                anchors.centerIn: parent
                text: "chevron_right"
                color: root.ink
                size: 20
            }
        }
    }
}
