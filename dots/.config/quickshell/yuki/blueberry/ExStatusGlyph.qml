import QtQuick

import qs.blueberry.looks

// A status glyph, by its name in ExStatusGlyphs, with a smaller mark in its
// lower corner when it has one, and breathing while something is under way.
//
// Never as wide as what it shows now: the font gives every glyph its own
// width, and the dock moved under the pointer as a speaker gained a wave. As
// wide as it is tall, or, given every glyph it can show, as wide as the ink of
// the widest of them, which leaves out the empty sides a narrow glyph such as
// the battery has in a square. Set against the left edge, so a speaker or a
// battery stays where it is and its waves or its bolt are added to the right
// of it.
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
    /** A glyph drawn faintly under it, by name, or empty: the full speaker, whose waves not reached stay as a shadow. */
    property string ghost: ""

    /** From the left of the leftmost ink of the variants to the right of the rightmost, or null without them. */
    readonly property var ink: {
        if (root.variants.length === 0)
            return null;
        let left = Infinity;
        let right = -Infinity;
        for (const name of root.variants) {
            const bounds = metrics.tightBoundingRect(ExStatusGlyphs.text(name));
            if (bounds.width <= 0)
                continue;
            left = Math.min(left, bounds.x);
            right = Math.max(right, bounds.x + bounds.width);
        }
        return right > left ? { left: left, right: right } : null;
    }

    implicitWidth: root.ink ? Math.ceil(root.ink.right - root.ink.left) : Math.ceil(root.size)
    implicitHeight: Math.ceil(root.size)

    FontMetrics {
        id: metrics
        font: glyph.font
    }

    Text {
        visible: root.ghost.length > 0
        x: glyph.x
        anchors.verticalCenter: parent.verticalCenter
        text: ExStatusGlyphs.text(root.ghost)
        color: root.color
        opacity: 0.3
        renderType: Text.NativeRendering
        font: glyph.font
    }

    Text {
        id: glyph

        x: root.ink ? -Math.floor(root.ink.left) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: ExStatusGlyphs.text(root.name)
        color: root.color
        renderType: Text.NativeRendering
        font.family: ExStatusGlyphs.family
        font.pixelSize: root.size
        font.hintingPreference: Font.PreferNoHinting

        SequentialAnimation on opacity {
            running: root.pulse
            loops: Animation.Infinite
            onRunningChanged: {
                if (!running)
                    glyph.opacity = 1;
            }
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
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
            text: ExStatusGlyphs.text(root.badge)
            color: root.color
            renderType: Text.NativeRendering
            font.family: ExStatusGlyphs.family
            font.pixelSize: Math.round(root.size * 0.5)
        }
    }
}
