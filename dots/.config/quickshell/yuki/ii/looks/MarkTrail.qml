import QtQuick
import qs.core
import qs.common

/**
 * Waiting, drawn with the three circles of the Illogical Impulse mark.
 *
 * The circles sit level and evenly spaced, and what travels is the size: one is
 * large while the other two are small, and the large one moves along the row and
 * comes back to the front. The mark sets the amplitude -- its smallest circle is
 * 56 parts and its largest 112, so the large one is twice the small one.
 *
 * A trail rather than a bar because there is nothing to measure: an indeterminate
 * bar borrows the shape of progress for something that has none.
 */
Item {
    id: root

    property color color: Appearance.colors.colPrimary
    property bool running: true
    /// Diameter of a circle at rest. The travelling one reaches twice this.
    property real unit: 7
    property int count: 3
    property int cycle: 1150

    readonly property real pitch: root.unit * 2.6

    implicitWidth: root.pitch * (root.count - 1) + root.unit * 2
    implicitHeight: root.unit * 2

    // One phase for the whole row rather than an animation per circle: what is
    // being drawn is a single thing moving, and three animations kept in step by
    // their delays is that thing only for as long as they stay in step.
    property real phase: 0
    NumberAnimation on phase {
        running: root.running && root.visible
        loops: Animation.Infinite
        from: 0
        to: root.count
        duration: root.cycle
    }

    Repeater {
        model: root.count

        delegate: Rectangle {
            id: dot
            required property int index

            // Distance to the travelling swell, the short way round, so it
            // leaves the last circle and arrives at the first without a jump.
            readonly property real gap: {
                const straight = Math.abs(root.phase - dot.index);
                return Math.min(straight, root.count - straight);
            }
            readonly property real rise: {
                const near = Math.max(0, 1 - dot.gap);
                // Eased rather than linear: a swell that grows at a constant rate
                // reads as a size step passed from one circle to the next.
                return near * near * (3 - 2 * near);
            }
            readonly property real size: root.unit * (1 + dot.rise)

            width: dot.size
            height: dot.size
            radius: dot.size / 2
            color: root.color
            opacity: 0.4 + 0.6 * dot.rise
            x: dot.index * root.pitch + root.unit - dot.size / 2
            y: (root.height - dot.size) / 2
        }
    }
}
