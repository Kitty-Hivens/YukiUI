import QtQuick
import QtQuick.Controls

/**
 * A word about whatever the pointer rests on, a moment after it comes to rest.
 *
 * Over the item it belongs to, centred on it, or under it where there is no
 * room above. Drawn in the window of that item, so it reaches no further than
 * the window does.
 */
ToolTip {
    id: root

    /** The first line, in full: a name that was cut short where it is shown. */
    property string title: ""
    /** A line under it, dimmed. Left out when empty. */
    property string detail: ""

    delay: 600
    timeout: -1
    padding: ExLooks.spacing.s + 2
    margins: ExLooks.spacing.s
    x: Math.round((parent ? parent.width - root.width : 0) / 2)
    y: -root.height - ExLooks.spacing.xs

    contentItem: Column {
        spacing: 2

        ExText {
            width: Math.min(implicitWidth, 320)
            text: root.title
            wrapMode: Text.Wrap
        }
        ExText {
            width: Math.min(implicitWidth, 320)
            visible: root.detail.length > 0
            text: root.detail
            role: "caption"
            dim: true
            wrapMode: Text.Wrap
        }
    }

    background: ExSurface {
        radius: ExLooks.radius.menuItem
        elevation: 1
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: ExLooks.motion.fast
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: ExLooks.motion.fast
        }
    }
}
