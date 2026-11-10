import QtQuick

/**
 * The plane a flyout is drawn on, and the way it comes and goes.
 *
 * Open and closed are the two ends of one number, and that number is animated
 * towards whichever end is asked for. A second click halfway through therefore
 * turns the panel round from where it is instead of starting it over.
 *
 * Whoever holds it says where it rests. It arrives from the dock side, a little
 * way off, growing out of the edge that faces the dock, and leaves towards the
 * dock, fading as it goes. A panel in a corner of the screen comes in from the
 * screen's edge instead and goes back out through it, see `entry`.
 */
ExSurface {
    id: root

    property bool open: false
    /** "bottom", "top", "left" or "right": the screen edge the dock stands on. */
    property string edge: "bottom"
    property real restX: 0
    property real restY: 0
    /**
     * "menu" comes quickly, as a menu does, and grows a little as it comes.
     * "panel" is for the larger flyouts, notifications and quick settings: it
     * comes in over a longer time and settles slowly, so that it reads as
     * arriving rather than as appearing.
     */
    property string motion: "menu"
    readonly property bool panel: root.motion === "panel"
    /** Holds the animation at one point, for the gallery. Negative leaves it alone. */
    property real previewProgress: -1
    /** How far it moves towards the dock and back. */
    property real travel: 20
    /**
     * The screen edge it comes in from and goes out through, "left", "right",
     * "top" or "bottom", or empty to rise from the dock. Set for a panel
     * standing in a corner of the screen: it slides from past the screen's
     * edge, which hides it on the way, whole and at full strength, as Waffle's
     * notification center does, and on Waffle's timing.
     */
    property string entry: ""
    /** How far it travels from that edge: far enough to be out of sight at the far end, its shadow too. */
    property real entryTravel: 0
    readonly property int slideInDuration: 200
    readonly property int slideOutDuration: 150
    readonly property var slideIn: [0.1, 0.9, 0.2, 1, 1, 1]
    readonly property var slideOut: [0.7, 0, 1, 0.5, 1, 1]

    property real openness: 0
    /** How far it still is from rest along `entry`. */
    property real shift: 0
    readonly property real progress: previewProgress >= 0 ? previewProgress : openness
    readonly property real slide: (1 - progress) * root.travel

    // Starts shut and sets off once the surface exists. Set off as it was
    // made, as for one loaded in the moment it is opened, it had nothing to
    // run from, so it only ever left.
    onOpenChanged: root.go()
    Component.onCompleted: {
        if (root.open)
            Qt.callLater(root.go);
    }

    // Durations are scaled by what is left of the way, so turning round
    // halfway takes half as long rather than a whole run. Leaving towards the
    // dock starts at speed: over the few pixels to the dock, an ease that set
    // off slowly held the panel still for the first ninety milliseconds after
    // the click and then dropped it at once.
    function go() {
        const away = Math.max(1, root.entryTravel);
        if (root.open) {
            if (root.openness === 0 && root.entry !== "" && root.previewProgress < 0) {
                fadeAnimation.stop();
                root.openness = 1;
                root.shift = root.entryTravel;
            }
            if (root.shift !== 0)
                root.animate(shiftAnimation, 0, root.slideInDuration * Math.max(0.35, root.shift / away), root.slideIn);
            if (root.openness !== 1)
                root.animate(fadeAnimation, 1, (root.panel ? ExLooks.motion.slow : ExLooks.motion.normal) * Math.max(0.35, 1 - root.openness),
                    root.panel ? ExLooks.motion.decelerate : ExLooks.motion.enter);
        } else if (root.entry !== "" && root.openness === 1 && root.previewProgress < 0) {
            root.animate(shiftAnimation, root.entryTravel, root.slideOutDuration * Math.max(0.35, 1 - root.shift / away), root.slideOut);
        } else {
            shiftAnimation.stop();
            root.animate(fadeAnimation, 0, (root.panel ? ExLooks.motion.normal : ExLooks.motion.fast) * Math.max(0.35, root.openness), ExLooks.motion.decelerate);
        }
    }

    function animate(animation: NumberAnimation, to: real, duration: real, curve: var) {
        animation.stop();
        animation.to = to;
        animation.duration = duration;
        animation.easing.bezierCurve = curve;
        animation.start();
    }

    NumberAnimation {
        id: fadeAnimation
        target: root
        property: "openness"
        easing.type: Easing.BezierSpline
    }
    NumberAnimation {
        id: shiftAnimation
        target: root
        property: "shift"
        easing.type: Easing.BezierSpline
        // Out of sight past the screen's edge, it is gone. Only on a run that
        // ends by itself: one stopped by opening again leaves it there.
        onFinished: {
            if (!root.open && root.shift !== 0)
                root.openness = 0;
        }
    }

    radius: ExLooks.radius.panel
    elevation: 1
    visible: progress > 0
    x: restX + (edge === "left" ? -slide : (edge === "right" ? slide : 0)) + (entry === "right" ? shift : (entry === "left" ? -shift : 0))
    y: restY + (edge === "bottom" ? slide : (edge === "top" ? -slide : 0)) + (entry === "bottom" ? shift : (entry === "top" ? -shift : 0))
    opacity: Math.min(1, progress * (root.panel ? 1.5 : 1.8))
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
