import QtQuick
import qs.core
import qs.core.functions
import qs.common

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left

    /**
     * A Canvas repaints when asked whether or not anyone can see it, and these
     * are fed by a poller that runs for as long as the shell does, so a graph
     * in a widget that is closed, or on a tab nobody is on, went on redrawing
     * itself once a tick. Drawn on the way onto the screen instead, so it still
     * shows the values it sat out, and drawn once it is ready as well: a request
     * made while the canvas has nowhere to draw is dropped, and the next value
     * is a poll interval away.
     */
    function repaintIfVisible() {
        if (root.visible) root.requestPaint();
    }
    onValuesChanged: root.repaintIfVisible()
    onVisibleChanged: root.repaintIfVisible()
    onAvailableChanged: root.repaintIfVisible()
    Component.onCompleted: root.repaintIfVisible()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        var dx = width / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2
        ctx.beginPath()
        var firstX = -1
        var lastX = 0
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            if (valueIndex < 0 || valueIndex >= root.values.length) {
                continue; // No data for this point
            }
            var x = i * dx
            var norm = root.values[valueIndex] // already in 0-1 range
            var y = height - norm * height
            if (firstX < 0) {
                firstX = x
                ctx.moveTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
            lastX = x
        }
        if (firstX < 0)
            return
        // Only the readings are stroked. Dropping to the baseline before the
        // stroke drew a hard vertical line wherever the data began, which reads
        // as a measurement rather than as the edge of the drawing.
        ctx.stroke()
        ctx.lineTo(lastX, height)
        ctx.lineTo(firstX, height)
        ctx.closePath()
        ctx.fill()
    }
}
