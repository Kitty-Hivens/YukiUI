import QtQuick

import qs.experimental.looks

// A status glyph, by its name in ExStatusGlyphs, with a smaller mark in its
// lower corner when it has one, and breathing while something is under way.
Item {
    id: root

    property string name: ""
    /** The mark in the corner, by name, or empty. */
    property string badge: ""
    property real size: ExLooks.sizes.icon
    property color color: ExLooks.colors.text
    /** What the mark is cut out of, so it reads over the glyph: the colour behind. */
    property color plate: "transparent"
    /** Fades in and out, for a connection being made. */
    property bool pulse: false

    implicitWidth: glyph.implicitWidth
    implicitHeight: root.size

    Text {
        id: glyph

        anchors.centerIn: parent
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
        x: glyph.x + glyph.width - width * 0.7
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
