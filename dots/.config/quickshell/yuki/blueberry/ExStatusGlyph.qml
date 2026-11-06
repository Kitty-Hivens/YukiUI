import QtQuick

import qs.blueberry.looks

// A status glyph, by its name in Material Symbols, with a smaller mark in its
// lower corner when it has one, and breathing while something is under way.
//
// As wide as it is tall, or, given every glyph it can show, as wide as the ink of
// the widest of them, which leaves out the empty sides a narrow glyph such as the
// battery has in a square. Each is set against the left edge by its own ink: the
// font centres every glyph in its square, so a speaker moved left as it gained a
// wave, and the dock moved under the pointer with it.
//
// One glyph fades into the next, the font having no way to turn one shape into
// another. What it can do is fill: a glyph left hollow fills as it comes on.
Item {
    id: root

    property string name: ""
    /** Every glyph it can show, by name, to be as wide as their ink rather than square. */
    property var variants: []
    /** The mark in the corner, by name, or empty. */
    property string badge: ""
    property real size: ExLooks.sizes.icon
    property color color: ExLooks.colors.text
    /** What the mark is cut out of, so it reads over the glyph: the colour behind. */
    property color plate: "transparent"
    /** Fades in and out, for a connection being made. */
    property bool pulse: false
    /** Drawn as an outline, for something not on: muted, or still connecting. */
    property bool hollow: false
    /** A glyph drawn faintly under it, by name, or empty: the full speaker, whose waves not reached stay as a shadow. */
    property string ghost: ""

    /** Heavier than the glyphs around it: at this size and on its own a status has to read at a glance. */
    readonly property int weight: 500
    property real fill: root.hollow ? 0 : 1
    Behavior on fill {
        NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
    }

    /** The one on show, and the one it is fading from. */
    property string current: ""
    property string previous: ""
    property real arrival: 1

    onNameChanged: {
        root.previous = root.current;
        root.current = root.name;
        if (root.previous.length === 0 || !root.visible) {
            root.previous = "";
            root.arrival = 1;
            return;
        }
        arrive.restart();
    }
    Component.onCompleted: root.current = root.name

    NumberAnimation {
        id: arrive
        target: root
        property: "arrival"
        from: 0
        to: 1
        duration: ExLooks.motion.fast
        onFinished: root.previous = ""
    }

    /** From the left of the leftmost ink of the variants to the right of the rightmost, each from its own left. */
    readonly property real inkWidth: {
        let widest = 0;
        for (const name of root.variants)
            widest = Math.max(widest, metrics.tightBoundingRect(name).width);
        return widest;
    }

    /** How far a glyph is moved for its ink to start at the left edge, in a place given its variants. */
    function shiftOf(name: string): real {
        return root.variants.length > 0 ? -Math.floor(metrics.tightBoundingRect(name).x) : 0;
    }

    implicitWidth: root.inkWidth > 0 ? Math.ceil(root.inkWidth) : Math.ceil(root.size)
    implicitHeight: Math.ceil(root.size)

    // Measured at the full fill: an outline is no wider, and asked again at every
    // step of a fill the dock would be measuring all through it.
    FontMetrics {
        id: metrics
        font.family: ExLooks.font.glyphs
        font.pixelSize: root.size
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({ "FILL": 1, "opsz": 20, "wght": root.weight })
    }

    component Glyph: Text {
        anchors.verticalCenter: parent.verticalCenter
        color: root.color
        renderType: Text.NativeRendering
        font.family: ExLooks.font.glyphs
        font.pixelSize: root.size
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({ "FILL": root.fill, "opsz": 20, "wght": root.weight })
    }

    Item {
        id: body

        anchors.fill: parent

        SequentialAnimation on opacity {
            running: root.pulse
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    body.opacity = 1;
            }
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        }

        Glyph {
            visible: root.ghost.length > 0
            x: root.shiftOf(root.ghost)
            text: root.ghost
            opacity: 0.3
        }
        Glyph {
            visible: root.previous.length > 0
            x: root.shiftOf(root.previous)
            text: root.previous
            opacity: 1 - root.arrival
        }
        Glyph {
            x: root.shiftOf(root.current)
            text: root.current
            opacity: root.arrival
        }
    }

    Rectangle {
        visible: root.badge.length > 0
        x: root.width - width * 0.7
        y: root.height - height * 0.8
        width: Math.round(root.size * 0.62)
        height: width
        radius: width / 2
        color: root.plate

        Text {
            anchors.centerIn: parent
            text: root.badge
            color: root.color
            renderType: Text.NativeRendering
            font.family: ExLooks.font.glyphs
            font.pixelSize: Math.round(root.size * 0.56)
            font.hintingPreference: Font.PreferNoHinting
            font.variableAxes: ({ "FILL": 1, "opsz": 20, "wght": 700 })
        }
    }
}
