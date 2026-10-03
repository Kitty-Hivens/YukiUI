import QtQuick
import QtQuick.Layouts
import qs.experimental.looks

// A stand-in screen: a wallpaper, a dock on one edge and the quick settings
// its status block opens. Launcher and apps sit in the middle of the dock, the
// status block at its far end, where the tray lives. A drawing of the dock,
// for the gallery, not ExDock itself.
Rectangle {
    id: screen

    property string edge: "bottom"
    /**
     * "attached" runs the whole edge and touches it, "floating" runs the whole
     * edge but stands off it, "island" stands off it and is only as long as
     * what it holds.
     */
    property string dockStyle: "attached"
    property real previewProgress: -1
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool detached: dockStyle !== "attached"
    readonly property real gap: detached ? ExLooks.dock.floatingGap : 0

    readonly property real islandLength: (vertical ? apps.implicitHeight + opener.height : apps.implicitWidth + opener.width) + 3 * ExLooks.spacing.s
    readonly property real dockLength: dockStyle === "island" ? islandLength : (vertical ? height : width) - 2 * gap

    implicitWidth: 1200
    implicitHeight: 700
    clip: true
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#c7d3f7" }
        GradientStop { position: 0.55; color: "#e4e1f4" }
        GradientStop { position: 1; color: "#f3dfe8" }
    }

    ExSurface {
        id: dock
        width: screen.vertical ? ExLooks.dock.thickness : screen.dockLength
        height: screen.vertical ? screen.dockLength : ExLooks.dock.thickness
        x: screen.edge === "right" ? screen.width - width - screen.gap
            : screen.edge === "left" ? screen.gap
            : (screen.width - width) / 2
        y: screen.edge === "bottom" ? screen.height - height - screen.gap
            : screen.edge === "top" ? screen.gap
            : (screen.height - height) / 2
        radius: screen.detached ? ExLooks.dock.floatingRadius : 0
        elevation: screen.detached ? 1 : 0
        color: "#e6ffffff"

        GridLayout {
            id: apps
            columns: screen.vertical ? 1 : 16
            rowSpacing: ExLooks.dock.spacing
            columnSpacing: ExLooks.dock.spacing
            // An island has no middle to centre on: everything it holds is
            // packed from its start.
            x: screen.vertical ? (parent.width - width) / 2
                : (screen.dockStyle === "island" ? ExLooks.spacing.s : (parent.width - width) / 2)
            y: screen.vertical ? (screen.dockStyle === "island" ? ExLooks.spacing.s : (parent.height - height) / 2)
                : (parent.height - height) / 2

            ExButton {
                kind: "flat"
                implicitWidth: ExLooks.dock.cell
                implicitHeight: ExLooks.dock.cell

                ExGlyph {
                    anchors.centerIn: parent
                    text: "apps"
                    size: ExLooks.dock.launcherGlyph
                    color: ExLooks.colors.accent
                }
            }
            Repeater {
                model: ["#4f6bed", "#e8704f", "#3fae6a", "#9a5ae0", "#e0a43a"]
                Item {
                    required property string modelData
                    implicitWidth: ExLooks.dock.cell
                    implicitHeight: ExLooks.dock.cell
                    Rectangle {
                        anchors.centerIn: parent
                        width: ExLooks.dock.icon
                        height: ExLooks.dock.icon
                        radius: 8
                        color: parent.modelData
                    }
                }
            }
        }

        // Drawn as held down, since the panel it opened is showing.
        Rectangle {
            id: opener
            width: status.implicitWidth + (screen.vertical ? 12 : 20)
            height: status.implicitHeight + (screen.vertical ? 20 : 12)
            x: screen.vertical ? (parent.width - width) / 2 : parent.width - width - ExLooks.spacing.s
            y: screen.vertical ? parent.height - height - ExLooks.spacing.s : (parent.height - height) / 2
            radius: ExLooks.radius.control
            color: ExLooks.colors.control

            GridLayout {
                id: status
                anchors.centerIn: parent
                columns: screen.vertical ? 1 : 3
                rowSpacing: 6
                columnSpacing: 8

                ExGlyph { text: "wifi"; size: 18 }
                ExGlyph { text: "volume_up"; size: 18 }
                ExGlyph { text: "battery_5_bar"; size: 18 }
            }
        }
    }

    ExFlyout {
        anchors.fill: parent
        edge: screen.edge
        open: true
        previewProgress: screen.previewProgress
        dockRect: Qt.rect(dock.x, dock.y, dock.width, dock.height)
        anchorRect: Qt.rect(dock.x + opener.x, dock.y + opener.y, opener.width, opener.height)

        QuickSettingsMock {}
    }
}
