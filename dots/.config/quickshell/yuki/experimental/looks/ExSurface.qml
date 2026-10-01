import QtQuick
import QtQuick.Effects

/**
 * A raised plane: panels, menus, tiles that float.
 *
 * The shadow sits in the item's own margin, so whatever holds a surface has to
 * leave room around it or the shadow is cut off at the window's edge.
 */
Item {
    id: root

    property alias color: plane.color
    property real radius: ExLooks.radius.panel
    property real elevation: 1
    /** The hairline all the way round. Off for a plane that meets the screen edge. */
    property bool bordered: true
    default property alias content: plane.data

    RectangularShadow {
        anchors.fill: plane
        radius: plane.radius
        offset: Qt.vector2d(0, 2 + 4 * root.elevation)
        blur: 8 + 16 * root.elevation
        spread: 0
        color: ExLooks.colors.shadow
        visible: root.elevation > 0
    }

    Rectangle {
        id: plane
        anchors.fill: parent
        radius: root.radius
        color: ExLooks.colors.surface
        border.width: root.bordered ? 1 : 0
        border.color: ExLooks.colors.hairline
    }
}
