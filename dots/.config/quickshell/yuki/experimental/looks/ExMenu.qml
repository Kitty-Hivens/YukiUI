import QtQuick

/** The plane a context menu is drawn on. Placement and dismissal come later. */
ExSurface {
    id: root

    default property alias items: column.data

    radius: ExLooks.radius.menu
    elevation: 1
    implicitWidth: ExLooks.sizes.menuWidth
    implicitHeight: column.implicitHeight + 2 * ExLooks.sizes.menuPadding

    Column {
        id: column
        anchors.fill: parent
        anchors.margins: ExLooks.sizes.menuPadding
    }
}
