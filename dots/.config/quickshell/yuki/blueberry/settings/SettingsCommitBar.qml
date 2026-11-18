import QtQuick
import QtQuick.Layouts

import qs.blueberry.looks

// Changes a page holds back until they are applied as a whole, said on a
// raised plate at the foot of the page's area. It stands over the page
// rather than in it: put in among the cards, it pushed everything under it
// down a row as it came and pulled it back up as it went, and scrolled away
// from the controls whose changes it applies.
//
// A page gives it the settings window's overlay as its parent and leaves
// room at its own foot, so its last rows can be scrolled out from under it.
Item {
    id: root

    property bool shown: false
    property string text: ""
    /** What stands in the way of applying, said in place of the text. */
    property string problem: ""
    /** Whether there is anything of the page's own to apply or discard. */
    property bool pending: true
    property bool canApply: true
    property bool busy: false
    property string applyText: ""
    property string busyText: ""
    property string discardText: ""

    signal applied()
    signal discarded()

    readonly property var metrics: ExLooks.settings
    readonly property bool blocked: root.problem.length > 0
    /** Between the plate and the pane's rounded foot. */
    readonly property real footGap: root.metrics.rowPadding
    /** Over which the page fades out above the plate. */
    readonly property real fade: root.metrics.groupGap
    /** How much of the page's foot it covers when up, gap under it included. */
    readonly property real footprint: plate.height + root.footGap + root.metrics.labelGap

    anchors.left: parent?.left
    anchors.right: parent?.right
    anchors.bottom: parent?.bottom
    height: root.footprint
    visible: root.lift > 0

    property real lift: root.shown ? 1 : 0
    Behavior on lift {
        NumberAnimation {
            duration: ExLooks.motion.normal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? ExLooks.motion.decelerate : ExLooks.motion.standard
        }
    }

    // What is hidden under the bar is out of reach as well as out of sight.
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        acceptedButtons: Qt.AllButtons
    }

    // The page goes under the bar and fades out above it, so a card scrolled
    // there neither shows round the plate's foot nor runs into it as another
    // card would.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.footprint + root.fade
        opacity: root.lift
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(root.metrics.pane, 0) }
            GradientStop { position: root.fade / (root.footprint + root.fade); color: root.metrics.pane }
            GradientStop { position: 1; color: root.metrics.pane }
        }
    }

    ExSurface {
        id: plate

        x: 0
        y: root.metrics.labelGap + (1 - root.lift) * (root.height - root.metrics.labelGap)
        width: parent.width
        height: content.implicitHeight + 2 * ExLooks.spacing.m
        opacity: root.lift
        radius: root.metrics.plateRadius
        color: root.metrics.plate
        elevation: 2

        RowLayout {
            id: content

            anchors.fill: parent
            anchors.leftMargin: root.metrics.rowPadding
            anchors.rightMargin: root.metrics.rowPadding
            spacing: root.metrics.rowPadding

            SettingsChip {
                glyph: root.blocked ? "error" : "info"
            }
            ExText {
                Layout.fillWidth: true
                text: root.blocked ? root.problem : root.text
                font.pixelSize: root.metrics.body
                color: root.blocked ? ExLooks.colors.destructive : ExLooks.colors.text
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            ExButton {
                visible: root.pending
                kind: "control"
                text: root.discardText
                onClicked: root.discarded()
            }
            ExButton {
                visible: root.pending
                kind: "accent"
                // Left at full strength while it applies, saying so: dimmed,
                // it read as refused rather than at work. A press then is
                // turned away by the service, which is busy.
                enabled: root.canApply && !root.blocked
                text: root.busy ? root.busyText : root.applyText
                onClicked: root.applied()
            }
        }
    }
}
