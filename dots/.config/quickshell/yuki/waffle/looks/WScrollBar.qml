import QtQuick
import QtQuick.Controls
import qs.core
import qs.common.widgets
import qs.core.functions

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded

    /// Whether the scrollbar shows at all. `active` is the view moving, the pointer
    /// being on the bar, or a drag of the thumb -- a menu that opens with more content
    /// than fits shows nothing until one of those happens, which is what was measured.
    readonly property bool shown: root.active && root.size < 1.0
    /// A hovered scrollbar is the only one with a track, and its thumb is three times
    /// as wide as the thread left behind otherwise.
    readonly property bool expanded: root.hovered || root.pressed

    /// Twelve of track and one clear pixel between it and the panel's edge. The thumb
    /// centres in the track, which is what puts its own edge four in.
    implicitWidth: 13
    rightPadding: 1

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: root.rightPadding
            // The track stops short of the ends of the area it scrolls rather than
            // running into them.
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            radius: width / 2
            color: Looks.colors.scrollTrack
            opacity: root.shown && root.expanded ? 1 : 0
            Behavior on opacity {
                animation: Looks.transition.opacity.createObject(this)
            }
        }
    }

    contentItem: Item {
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            animation: Looks.transition.opacity.createObject(this)
        }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
            }
            width: root.expanded ? 6 : 2
            radius: width / 2
            color: Looks.colors.controlStrongFill
            Behavior on width {
                animation: Looks.transition.resize.createObject(this)
            }
        }
    }
}
