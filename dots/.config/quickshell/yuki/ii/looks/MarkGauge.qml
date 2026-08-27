import QtQuick
import QtQuick.Shapes
import qs.core
import qs.core.functions
import qs.common

/**
 * A bounded value drawn the way the Illogical Impulse mark draws its ring: an
 * arc that does not close, cut square at both ends, with the gap at the bottom
 * and a triangular index riding at the value.
 *
 * For a number with a ceiling and no history -- a charge, a filled disk. Where
 * there is history the graph stays, because the shape of the last minute answers
 * a question the number does not.
 *
 * Colour is not taken from the mark. The skin is repainted from the wallpaper,
 * so what is borrowed here is the form.
 */
Item {
    id: root

    property real value: 0
    property real thickness: Math.max(3, width * 0.1)
    /// The mark's triangle. Off by default: at the sizes a settings card gives a
    /// ring, it is a few pixels wedged between the arc and the number, and reads
    /// as a defect rather than as an index. Worth having only on a large one.
    property bool index: false
    property color color: Appearance.colors.colPrimary
    property color trackColor: ColorUtils.transparentize(root.color, 0.86)

    /// The opening of the mark's ring, at the bottom, in degrees.
    readonly property real gap: 44
    readonly property real from: 90 + root.gap / 2
    readonly property real span: 360 - root.gap
    readonly property real radius: (Math.min(width, height) - root.thickness) / 2
    readonly property real fraction: Math.max(0, Math.min(1, root.value))
    readonly property real angle: (root.from + root.span * root.fraction) * Math.PI / 180

    implicitWidth: 120
    implicitHeight: 120

    // On the value rather than on what is derived from it: a reading that moves
    // should be seen to move, and what is derived cannot be animated because it
    // is not written to.
    Behavior on value {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.from
                sweepAngle: root.span
            }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.from
                sweepAngle: root.span * root.fraction
            }
        }
    }

    // The mark's triangle, used as it is used there: an index inside the ring,
    // pointing out at where the value stands.
    Shape {
        id: pointer
        anchors.fill: parent
        visible: root.index && root.width > 70
        preferredRendererType: Shape.CurveRenderer

        readonly property real seat: root.radius - root.thickness / 2 - root.thickness * 0.55
        readonly property real reach: root.thickness * 0.72
        readonly property real half: root.thickness * 0.42
        readonly property real ux: Math.cos(root.angle)
        readonly property real uy: Math.sin(root.angle)

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            startX: root.width / 2 + (pointer.seat) * pointer.ux
            startY: root.height / 2 + (pointer.seat) * pointer.uy
            PathLine {
                x: root.width / 2 + (pointer.seat - pointer.reach) * pointer.ux + pointer.half * -pointer.uy
                y: root.height / 2 + (pointer.seat - pointer.reach) * pointer.uy + pointer.half * pointer.ux
            }
            PathLine {
                x: root.width / 2 + (pointer.seat - pointer.reach) * pointer.ux - pointer.half * -pointer.uy
                y: root.height / 2 + (pointer.seat - pointer.reach) * pointer.uy - pointer.half * pointer.ux
            }
        }
    }
}
