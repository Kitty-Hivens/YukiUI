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

    readonly property real shadowBlur: 8 + 16 * root.elevation
    readonly property real shadowOffset: 2 + 4 * root.elevation
    // A shadow is drawn under the whole plane, and through a plane that lets
    // the screen show it would darken the plane itself. There it is cut out
    // where the plane is.
    readonly property bool seeThrough: plane.color.a < 0.999
    readonly property real shadowRoom: root.shadowBlur + root.shadowOffset

    Item {
        id: shadowHolder

        visible: root.elevation > 0
        // Large enough for all of the shadow, which a layer cuts at its own edge.
        x: -root.shadowRoom
        y: -root.shadowRoom
        width: root.width + 2 * root.shadowRoom
        height: root.height + 2 * root.shadowRoom
        layer.enabled: root.seeThrough
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: hole
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        RectangularShadow {
            x: root.shadowRoom
            y: root.shadowRoom
            width: root.width
            height: root.height
            radius: plane.radius
            offset: Qt.vector2d(0, root.shadowOffset)
            blur: root.shadowBlur
            spread: 0
            color: ExLooks.colors.shadow
        }
    }

    // The plane's shape, in the shadow's coordinates, for cutting it out.
    Item {
        id: hole

        visible: false
        x: shadowHolder.x
        y: shadowHolder.y
        width: shadowHolder.width
        height: shadowHolder.height
        layer.enabled: root.seeThrough

        Rectangle {
            x: root.shadowRoom
            y: root.shadowRoom
            width: root.width
            height: root.height
            radius: plane.radius
        }
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
