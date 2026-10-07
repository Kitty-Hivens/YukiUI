pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.core.services
import qs.experimental.looks

// The game bar on its screen: the dimming, the bar along the top, and the
// widgets where they were left.
PanelWindow {
    id: window

    required property var modelData
    /** The bar, whose state this window shows. */
    required property var bar

    screen: window.modelData
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:gamebar"
    WlrLayershell.layer: WlrLayer.Overlay
    // Taken rather than asked for: a fullscreen window holds on to a keyboard
    // only asked for.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Noted before the window is up, while the game still has the keyboard,
    // and handed back to it as the bar goes: nothing takes the keyboard on
    // its own when a surface over everything closes, and a game with nothing
    // focused reads its dead input as a freeze.
    readonly property string focusOwner: "exGameBar"
    Component.onCompleted: FocusReturn.remember(window.focusOwner)
    Component.onDestruction: FocusReturn.restore(window.focusOwner)

    Item {
        id: stage

        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.bar.close()

        opacity: 0
        Component.onCompleted: stage.opacity = 1
        Behavior on opacity {
            NumberAnimation {
                duration: ExLooks.motion.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ExLooks.motion.standard
            }
        }

        Rectangle {
            anchors.fill: parent
            color: ExLooks.colors.scrim
        }
        // A click beside the widgets puts the bar away.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: window.bar.close()
        }

        ExGameBarHome {
            id: home

            anchors.horizontalCenter: parent.horizontalCenter
            y: ExLooks.spacing.xl
            bar: window.bar
        }

        // Where the widgets first go, as Windows has them: taking pictures in
        // the top left, the sound under it, and the readings on the right.
        readonly property real widgetsTop: home.y + home.height + ExLooks.spacing.xl

        ExGameBarWidget {
            id: capture

            bar: window.bar
            key: "capture"
            title: Translation.tr("Capture")
            glyph: "screen_record"
            defaultX: ExLooks.spacing.xl
            defaultY: stage.widgetsTop

            ExGameBarCapture {
                bar: window.bar
            }
        }
        ExGameBarWidget {
            bar: window.bar
            key: "audio"
            title: Translation.tr("Audio")
            glyph: "volume_up"
            defaultX: ExLooks.spacing.xl
            defaultY: stage.widgetsTop + capture.height + ExLooks.spacing.l

            ExGameBarAudio {}
        }
        ExGameBarWidget {
            id: performance

            bar: window.bar
            key: "performance"
            title: Translation.tr("Performance")
            glyph: "monitoring"
            defaultX: stage.width - performance.width - ExLooks.spacing.xl
            defaultY: stage.widgetsTop

            ExGameBarPerformance {
                watching: performance.visible
            }
        }
    }
}
