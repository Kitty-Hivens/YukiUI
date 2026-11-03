import QtQuick
import qs.blueberry.looks

// The flyout at rest, then frozen at points along the way in, so the motion can
// be judged from a still.
Item {
    id: page

    property string edge: "bottom"
    property string dockStyle: "attached"
    readonly property var frames: [0.15, 0.35, 0.55, 0.75, 0.9]
    readonly property real frameScale: 0.19

    implicitWidth: 1248
    implicitHeight: column.implicitHeight + 48

    Column {
        id: column
        x: 24
        y: 24
        spacing: ExLooks.spacing.s

        GalleryCaption { text: "Открыта, край: " + page.edge + ", док: " + page.dockStyle }
        MockScreen {
            edge: page.edge
            dockStyle: page.dockStyle
            previewProgress: 1
        }
        GalleryCaption { text: "Вход, кадры на 15, 35, 55, 75 и 90 %" }
        Row {
            spacing: ExLooks.spacing.m

            Repeater {
                model: page.frames
                Item {
                    required property real modelData
                    width: 1200 * page.frameScale
                    height: 700 * page.frameScale

                    MockScreen {
                        scale: page.frameScale
                        transformOrigin: Item.TopLeft
                        edge: page.edge
                        dockStyle: page.dockStyle
                        previewProgress: parent.modelData
                    }
                }
            }
        }
    }
}
