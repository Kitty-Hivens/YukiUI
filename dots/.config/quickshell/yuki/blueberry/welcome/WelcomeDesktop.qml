pragma ComponentBehavior: Bound

import QtQuick

import qs.core
import qs.core.functions
import qs.blueberry.looks

// The desktop in miniature: the wallpaper in use, two windows over it in the
// mode chosen, and the dock where it stands and as it is drawn, all read from
// the settings as they are, so a choice made beside it shows here at once.
// Drawn in plain items rather than a picture of the screen, which would show
// whatever is open on it, this window among them.
Item {
    id: root

    /** The tone the miniature sits on, which its rounded corners are cut in. */
    property color backdrop: ExLooks.settings.pane
    property real radius: 14

    readonly property var dock: Config.options.blueberry.dock
    readonly property bool horizontal: root.dock.edge === "bottom" || root.dock.edge === "top"
    /**
     * The real screen drawn this much smaller, and the dock a little less so,
     * to be read at all: in a small miniature never thinner than about a
     * third of the real one.
     */
    readonly property real ratio: root.width / 1920
    readonly property real dockScale: Math.max(root.ratio * 1.5, 0.32)
    readonly property real thickness: Math.round(ExLooks.dock.thickness * root.dockScale)
    readonly property real gap: root.dock.style === "attached" ? 0 : Math.round(ExLooks.dock.floatingGap * root.dockScale)
    readonly property real cell: ExLooks.dock.cell * root.dockScale
    readonly property int apps: 6

    readonly property var easing: ExLooks.motion.standard

    implicitWidth: 560
    implicitHeight: Math.round(root.width * 9 / 16)
    // A rectangle clip, which needs no shader, for the attached dock's overhang below.
    clip: true

    Rectangle {
        anchors.fill: parent
        color: ExLooks.colors.surfaceSunken
    }
    Image {
        anchors.fill: parent
        source: Config.options.background.wallpaperPath.length > 0 ? FileUtils.fileUrl(FileUtils.trimFileProtocol(String(Config.options.background.wallpaperPath))) : ""
        sourceSize: Qt.size(1120, 630)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // What the dock leaves of the screen, where the windows stand.
    Item {
        id: work

        readonly property real taken: root.dock.autoHide ? 0 : root.thickness + 2 * root.gap

        x: root.dock.edge === "left" ? work.taken : 0
        y: root.dock.edge === "top" ? work.taken : 0
        width: root.width - (root.horizontal ? 0 : work.taken)
        height: root.height - (root.horizontal ? work.taken : 0)

        MiniWindow {
            x: work.width * 0.08
            y: work.height * 0.1
            width: work.width * 0.5
            height: work.height * 0.62
            front: false
        }
        MiniWindow {
            x: work.width * 0.38
            y: work.height * 0.26
            width: work.width * 0.52
            height: work.height * 0.6
            front: true
        }

        Behavior on x { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on y { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on width { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on height { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
    }

    // The dock: the plate, the applications in it and the clock at its end.
    Item {
        id: dockItem

        readonly property real appsLength: root.apps * root.cell
        readonly property real trayLength: root.cell * 1.6
        readonly property real padding: root.cell * 0.25
        /** Along the edge: the whole of it, or only what an island holds. */
        readonly property real length: root.dock.style === "island"
            ? dockItem.appsLength + dockItem.trayLength + 3 * dockItem.padding
            : (root.horizontal ? root.width : root.height) - 2 * root.gap
        readonly property real start: root.dock.style === "island" && root.dock.alignment === "center"
            ? ((root.horizontal ? root.width : root.height) - dockItem.length) / 2
            : root.gap

        /**
         * An attached dock stands a pixel past the edge, cut off by the clip:
         * at a fractional scale its outer edge and the miniature's fell on
         * different device pixels, and the wallpaper showed in a line between.
         */
        readonly property real overhang: root.dock.style === "attached" ? 1 : 0

        visible: !root.dock.autoHide
        x: root.horizontal ? dockItem.start : (root.dock.edge === "left" ? root.gap - dockItem.overhang : root.width - root.thickness - root.gap + dockItem.overhang)
        y: !root.horizontal ? dockItem.start : (root.dock.edge === "top" ? root.gap - dockItem.overhang : root.height - root.thickness - root.gap + dockItem.overhang)
        width: root.horizontal ? dockItem.length : root.thickness
        height: root.horizontal ? root.thickness : dockItem.length

        Behavior on x { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on y { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on width { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }
        Behavior on height { NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: root.easing } }

        Rectangle {
            anchors.fill: parent
            radius: root.dock.style === "attached" ? 0 : ExLooks.dock.floatingRadius * root.dockScale
            color: ExLooks.colors.dockPlate
            border.width: 1
            border.color: ExLooks.colors.hairline
        }

        // The applications, from the start or around the middle, the first of
        // them the launcher.
        Grid {
            id: appsRow

            readonly property real offset: root.dock.style === "island" || root.dock.alignment === "start"
                ? dockItem.padding
                : (dockItem.length - dockItem.appsLength) / 2

            x: root.horizontal ? appsRow.offset : 0
            y: root.horizontal ? 0 : appsRow.offset
            columns: root.horizontal ? root.apps : 1
            spacing: 0

            Repeater {
                model: root.apps

                Item {
                    id: cellItem

                    required property int index

                    width: root.horizontal ? root.cell : root.thickness
                    height: root.horizontal ? root.thickness : root.cell

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.cell * 0.66
                        height: width
                        radius: width * 0.28
                        visible: cellItem.index > 0
                        // A few applications' colours, soft enough to sit on either mode.
                        color: ["#5b8def", "#f2a33a", "#47b881", "#e5626a", "#9b7be0"][(cellItem.index - 1) % 5]
                    }
                    ExGlyph {
                        anchors.centerIn: parent
                        visible: cellItem.index === 0
                        text: "apps"
                        size: root.cell * 0.62
                        color: ExLooks.colors.accentText
                    }
                    // The open one, marked under its icon.
                    Rectangle {
                        visible: cellItem.index === 1 || cellItem.index === 2
                        x: root.horizontal ? (parent.width - width) / 2 : (root.dock.edge === "left" ? 1 : parent.width - width - 1)
                        y: root.horizontal ? (root.dock.edge === "top" ? 1 : parent.height - height - 1) : (parent.height - height) / 2
                        width: root.horizontal ? (cellItem.index === 2 ? root.cell * 0.36 : root.cell * 0.14) : 2
                        height: root.horizontal ? 2 : (cellItem.index === 2 ? root.cell * 0.36 : root.cell * 0.14)
                        radius: 1
                        color: cellItem.index === 2 ? ExLooks.colors.accent : ExLooks.colors.textDim
                    }
                }
            }
        }

        // The clock and the tray, at the far end.
        Item {
            x: root.horizontal ? (root.dock.style === "island" ? appsRow.offset + dockItem.appsLength + dockItem.padding : dockItem.length - dockItem.trayLength - dockItem.padding) : 0
            y: root.horizontal ? 0 : (root.dock.style === "island" ? appsRow.offset + dockItem.appsLength + dockItem.padding : dockItem.length - dockItem.trayLength - dockItem.padding)
            width: root.horizontal ? dockItem.trayLength : root.thickness
            height: root.horizontal ? root.thickness : dockItem.trayLength

            Column {
                anchors.centerIn: parent
                spacing: Math.max(2, root.thickness * 0.1)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.horizontal ? root.cell * 0.9 : root.thickness * 0.5
                    height: Math.max(2, root.thickness * 0.12)
                    radius: height / 2
                    color: ExLooks.colors.text
                    opacity: 0.7
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.horizontal ? root.cell * 0.6 : root.thickness * 0.34
                    height: Math.max(2, root.thickness * 0.1)
                    radius: height / 2
                    color: ExLooks.colors.text
                    opacity: 0.35
                }
            }
        }
    }

    WelcomeCorners {
        color: root.backdrop
        radius: root.radius
    }

    // An application's window: a bar across its top, a list down its side and
    // a few lines of content, in the mode chosen.
    component MiniWindow: Item {
        id: miniWindow

        property bool front: true
        readonly property real corner: Math.max(3, 8 * root.dockScale)

        Rectangle {
            x: 0
            y: miniWindow.height * 0.03
            width: parent.width
            height: parent.height
            radius: miniWindow.corner
            color: ExLooks.colors.shadow
            opacity: miniWindow.front ? 0.9 : 0.5
        }
        Rectangle {
            anchors.fill: parent
            radius: miniWindow.corner
            color: ExLooks.colors.surface
            border.width: 1
            border.color: ExLooks.colors.hairline

            Behavior on color { ColorAnimation { duration: ExLooks.motion.normal } }

            // The list down the side.
            Rectangle {
                x: 1
                y: 1
                width: parent.width * 0.28
                height: parent.height - 2
                topLeftRadius: miniWindow.corner - 1
                bottomLeftRadius: miniWindow.corner - 1
                color: ExLooks.colors.surfaceSunken

                Column {
                    x: parent.width * 0.14
                    y: parent.height * 0.16
                    spacing: parent.height * 0.07

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index
                            width: (index === 0 ? 0.72 : 0.56) * miniWindow.width * 0.28 * 0.8
                            height: Math.max(2, miniWindow.height * 0.035)
                            radius: height / 2
                            color: index === 0 ? ExLooks.colors.accent : ExLooks.colors.text
                            opacity: index === 0 ? 0.9 : 0.22
                        }
                    }
                }
            }
            // The content: a heading, lines, and a button.
            Column {
                x: parent.width * 0.34
                y: parent.height * 0.16
                spacing: parent.height * 0.06

                Rectangle {
                    width: miniWindow.width * 0.32
                    height: Math.max(3, miniWindow.height * 0.055)
                    radius: height / 2
                    color: ExLooks.colors.text
                    opacity: 0.75
                }
                Repeater {
                    model: 3

                    Rectangle {
                        required property int index
                        width: miniWindow.width * [0.52, 0.46, 0.3][index]
                        height: Math.max(2, miniWindow.height * 0.035)
                        radius: height / 2
                        color: ExLooks.colors.text
                        opacity: 0.2
                    }
                }
                Rectangle {
                    width: miniWindow.width * 0.14
                    height: Math.max(5, miniWindow.height * 0.09)
                    radius: height / 2
                    color: ExLooks.colors.accent
                }
            }
        }
    }
}
