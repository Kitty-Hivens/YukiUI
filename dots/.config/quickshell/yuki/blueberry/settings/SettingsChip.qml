import QtQuick

import qs.blueberry.looks

// A glyph on a disc: in a category's colour, or plain for a setting on a page.
Rectangle {
    id: root

    property string glyph: ""
    /** A category's hue in degrees, or a negative number for none. */
    property real hue: -1
    property real size: ExLooks.settings.rowChip
    /** The disc in the category's ink and the glyph in its fill: on, chosen. */
    property bool inverted: false

    readonly property var colours: root.hue >= 0 ? ExLooks.hue(root.hue) : null

    implicitWidth: root.size
    implicitHeight: root.size
    radius: root.size / 2
    // Chosen without a colour of its own, it takes the accent's.
    color: root.inverted ? (root.colours?.ink ?? ExLooks.colors.accent) : (root.colours?.fill ?? ExLooks.settings.sunken)

    ExGlyph {
        anchors.centerIn: parent
        text: root.glyph
        // Glyph sizes the font is drawn for: 16 on the small discs, 20 on the rest.
        size: root.size <= 28 ? 16 : root.size >= 44 ? 24 : 20
        fill: root.inverted ? 1 : 0
        color: root.inverted ? (root.colours?.fill ?? ExLooks.colors.accentInk) : (root.colours?.ink ?? ExLooks.colors.text)
    }
}
