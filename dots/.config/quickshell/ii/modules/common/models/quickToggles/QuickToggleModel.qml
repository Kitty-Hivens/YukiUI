import QtQuick

QtObject {
    // Textual info
    required property string name
    property string statusText
    property string tooltipText: ""
    property string icon: "close"

    // State
    property bool hasStatusText: true
    property bool available: true
    property bool toggled: false

    /**
     * The glyph to use in a given family, by family id, where `icon` is wrong
     * for it.
     *
     * Only contributed toggles need this. A toggle written into a family picks
     * its glyph at the point it is rendered, but one arriving from a plugin is
     * rendered by a branch that knows nothing about it, and the two families do
     * not draw from the same icon set.
     */
    property var familyIcons: ({})

    // Interactions
    required property var mainAction
    property bool hasMenu: false
    property var altAction: null

    // Allow stuff like Processes to be declared freely
    default property list<QtObject> data
}
