import QtQuick
import QtQuick.Shapes

import qs.experimental.looks

// Readings over time, newest on the right, from 0 at the bottom to 1 at the
// top: a line, and under it a wash of the same colour fading to nothing. It
// has no plate of its own and is drawn on whatever holds it.
Item {
    id: graph

    /** The readings, oldest first, each from 0 to 1. */
    property var values: []
    /** How many readings fill the width. */
    property int points: 60
    property color ink: ExLooks.colors.accent

    readonly property real step: graph.width / Math.max(1, graph.points - 1)
    readonly property var line: {
        const count = graph.values.length;
        const top = 2;
        const span = graph.height - 2 * top;
        const points = [];
        for (let i = 0; i < count; i++) {
            const value = Math.max(0, Math.min(1, graph.values[i]));
            points.push(Qt.point(graph.width - (count - 1 - i) * graph.step, top + (1 - value) * span));
        }
        return points;
    }

    clip: true

    Shape {
        anchors.fill: parent
        visible: graph.line.length > 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: graph.height
                GradientStop { position: 0; color: Qt.alpha(graph.ink, 0.32) }
                GradientStop { position: 1; color: Qt.alpha(graph.ink, 0) }
            }

            PathPolyline {
                path: graph.line.length > 1 ? [Qt.point(graph.line[0].x, graph.height), ...graph.line, Qt.point(graph.width, graph.height)] : []
            }
        }
        ShapePath {
            strokeWidth: 2
            strokeColor: graph.ink
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathPolyline {
                path: graph.line
            }
        }
    }
}
