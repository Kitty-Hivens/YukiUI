import QtQuick
import qs.blueberry.looks

// The three ways the dock can stand, on a horizontal and a vertical edge.
Item {
    id: page

    readonly property real frameScale: 0.4
    readonly property var styles: ["attached", "floating", "island"]
    readonly property var edges: ["bottom", "left"]

    implicitWidth: grid.implicitWidth + 48
    implicitHeight: grid.implicitHeight + 48

    Grid {
        id: grid
        x: 24
        y: 24
        columns: page.styles.length
        spacing: ExLooks.spacing.m

        Repeater {
            model: page.edges.length * page.styles.length

            Column {
                id: cell
                required property int index
                readonly property string edge: page.edges[Math.floor(index / page.styles.length)]
                readonly property string dockStyle: page.styles[index % page.styles.length]
                spacing: ExLooks.spacing.xs

                GalleryCaption { text: cell.dockStyle + ", " + cell.edge }
                Item {
                    width: 1200 * page.frameScale
                    height: 700 * page.frameScale

                    MockScreen {
                        scale: page.frameScale
                        transformOrigin: Item.TopLeft
                        edge: cell.edge
                        dockStyle: cell.dockStyle
                        previewProgress: 0
                    }
                }
            }
        }
    }
}
