import QtQuick

/**
 * The plane a flyout is drawn on, and the way it comes and goes.
 *
 * Open and closed are the two ends of one number, and that number is animated
 * towards whichever end is asked for. A second click halfway through therefore
 * turns the panel round from where it is instead of starting it over.
 *
 * Whoever holds it says where it rests. It arrives from the dock side, a little
 * way off, growing out of the edge that faces the dock.
 */
ExSurface {
    id: root

    property bool open: false
    /** "bottom", "top", "left" or "right": the screen edge the dock stands on. */
    property string edge: "bottom"
    property real restX: 0
    property real restY: 0
    /**
     * "menu" comes quickly and a short way, as a menu does. "panel" is for the
     * larger flyouts, notifications and quick settings: it rises from the dock
     * over a longer way and settles slowly, the way Windows 11 brings them in,
     * so that it reads as arriving rather than as appearing.
     */
    property string motion: "menu"
    readonly property bool panel: root.motion === "panel"
    /** Holds the animation at one point, for the gallery. Negative leaves it alone. */
    property real previewProgress: -1

    // Starts shut and is bound once the surface exists. A binding that already
    // read 1 when the surface was made, as for one loaded in the moment it is
    // opened, gave the animation nothing to run from, so it only ever left.
    property real openness: 0
    Component.onCompleted: Qt.callLater(() => root.openness = Qt.binding(() => root.open ? 1 : 0))
    readonly property real progress: previewProgress >= 0 ? previewProgress : openness
    readonly property real travel: root.panel ? 64 : 20
    readonly property real slide: (1 - progress) * travel

    Behavior on openness {
        NumberAnimation {
            // Scaled by what is left of the way, so turning round halfway
            // takes half as long rather than a whole run.
            duration: (root.open ? (root.panel ? ExLooks.motion.slow : ExLooks.motion.normal) : (root.panel ? ExLooks.motion.normal : ExLooks.motion.fast)) * Math.max(0.35, Math.abs((root.open ? 1 : 0) - root.openness))
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? (root.panel ? ExLooks.motion.decelerate : ExLooks.motion.enter) : ExLooks.motion.exit
        }
    }

    radius: ExLooks.radius.panel
    elevation: 1
    visible: progress > 0
    x: restX + (edge === "left" ? -slide : (edge === "right" ? slide : 0))
    y: restY + (edge === "bottom" ? slide : (edge === "top" ? -slide : 0))
    opacity: Math.min(1, progress * (root.panel ? 2.5 : 1.8))
    // A panel keeps its size and only travels: grown as well, it looked like a
    // pop rather than a movement.
    scale: root.panel ? 1 : 0.94 + 0.06 * progress
    transformOrigin: edge === "left" ? Item.Left
        : edge === "right" ? Item.Right
        : edge === "top" ? Item.Top
        : Item.Bottom

    // Takes the presses that land on the panel but on nothing in it.
    MouseArea {
        anchors.fill: parent
    }
}
