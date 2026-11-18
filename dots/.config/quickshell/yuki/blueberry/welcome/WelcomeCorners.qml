pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// Rounds the corners of a picture by laying the tone behind it over them,
// rather than by clipping, which takes a shader: drawn without one, a clipped
// picture did not draw at all. Placed over the picture, filling it.
Item {
    id: root

    property color color
    property real radius: 10

    anchors.fill: parent

    Repeater {
        model: 4

        Shape {
            id: cap

            required property int index

            x: cap.index % 2 === 0 ? 0 : root.width - root.radius
            y: cap.index < 2 ? 0 : root.height - root.radius
            width: root.radius
            height: root.radius
            rotation: [0, 90, 270, 180][cap.index]

            ShapePath {
                strokeWidth: -1
                fillColor: root.color
                startX: 0
                startY: 0
                PathLine { x: root.radius; y: 0 }
                PathArc { x: 0; y: root.radius; radiusX: root.radius; radiusY: root.radius; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
        }
    }
}
