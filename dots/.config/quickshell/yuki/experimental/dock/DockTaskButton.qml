import QtQuick
import Quickshell
import Quickshell.Widgets

import qs.core
import qs.core.services
import qs.experimental.looks

// One application on the dock. Its windows are the ones it has on the
// workspace on screen, minimised ones included.
Item {
    id: root

    required property var entry
    required property int workspaceId
    required property string edge
    /** What the application announces for its button: a count, progress, a request for attention. */
    property var status: null
    readonly property bool showsProgress: root.status?.progressVisible ?? false
    readonly property bool showsCount: (root.status?.countVisible ?? false) && (root.status?.count ?? 0) > 0

    /** Which of the application's windows this dock shows, or null for those on the workspace. */
    property var showsWindow: null
    // The entry is gone for a moment before the button is, while the dock lets go of it.
    readonly property var windows: !root.entry ? []
        : root.showsWindow ? root.entry.toplevels.filter(toplevel => root.showsWindow(toplevel))
        : TaskbarApps.windowsOn(root.entry, root.workspaceId)
    readonly property bool running: windows.length > 0
    // A window minimised last keeps its activated flag once focus is let go of,
    // since nothing takes it over, so being out of sight has to rule it out.
    readonly property bool focused: windows.some(toplevel => toplevel.activated && !TaskbarApps.isMinimized(toplevel))
    readonly property bool minimized: running && windows.every(toplevel => TaskbarApps.isMinimized(toplevel))
    readonly property bool vertical: edge === "left" || edge === "right"

    /** Several windows: the dock shows them to pick from. */
    signal groupRequested
    /** A right click. */
    signal menuRequested

    /** What a left click does, also reached by number through the dock's IPC. */
    function activate() {
        if (!root.running)
            TaskbarApps.launch(root.entry.appId);
        else if (root.windows.length === 1)
            TaskbarApps.toggleWindow(root.windows[0]);
        else
            root.groupRequested();
    }

    implicitWidth: ExLooks.dock.cell
    implicitHeight: ExLooks.dock.cell

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.menuRequested();
            else if (event.button === Qt.MiddleButton)
                TaskbarApps.launch(root.entry.appId);
            else
                root.activate();
        }
    }

    // Several windows are drawn as a stack: the plate steps back from its far
    // end and the edge of a second one shows behind it. As on Windows the stack
    // shows while the button is in front or under the pointer, and at rest a
    // group looks like any other button. The icon keeps its place on the front
    // plate either way, so it does not shift as the stack comes and goes.
    readonly property bool group: windows.length > 1
    readonly property real stackStep: group ? 4 : 0
    readonly property bool raised: root.focused || mouse.containsMouse

    Rectangle {
        visible: root.group && root.raised
        x: root.vertical ? 0 : root.stackStep
        y: root.vertical ? root.stackStep : 0
        width: root.width - x
        height: root.height - y
        radius: ExLooks.radius.control
        color: root.focused ? ExLooks.colors.tonalDeep : ExLooks.colors.control
    }

    Rectangle {
        width: root.width - (root.vertical ? 0 : root.stackStep)
        height: root.height - (root.vertical ? root.stackStep : 0)
        radius: ExLooks.radius.control
        color: root.focused ? ExLooks.colors.tonal
            : (root.group && root.raised ? ExLooks.colors.surfaceSunken : "transparent")

        Behavior on color {
            ColorAnimation { duration: ExLooks.motion.fast }
        }

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: mouse.containsMouse
            pressed: mouse.pressed
        }
    }

    IconImage {
        id: icon

        anchors.centerIn: parent
        // On the front plate of a stack, not on the whole cell.
        anchors.horizontalCenterOffset: root.vertical ? 0 : -root.stackStep / 2
        anchors.verticalCenterOffset: root.vertical ? -root.stackStep / 2 : 0
        implicitSize: ExLooks.dock.icon
        source: AppSearch.iconFor(root.entry?.appId ?? "")
        // A pressed icon sinks a little, the way a key does.
        scale: mouse.pressed ? 0.86 : 1
        opacity: root.minimized ? 0.55 : 1

        Behavior on scale {
            NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
        Behavior on opacity {
            NumberAnimation { duration: ExLooks.motion.fast }
        }
    }

    // A count in the icon's corner, or a dot when the application asks to be
    // looked at without one, the way the tray marks it.
    Rectangle {
        visible: Config.options.experimental.dock.badges && (root.showsCount || (root.status?.urgent ?? false))
        x: icon.x + icon.width - width / 2 - 2
        y: icon.y - height / 2 + 2
        width: root.showsCount ? Math.max(height, countText.implicitWidth + 8) : 10
        height: root.showsCount ? 16 : 10
        radius: height / 2
        color: ExLooks.colors.accent
        border.width: 1.5
        border.color: ExLooks.colors.surface

        ExText {
            id: countText

            anchors.centerIn: parent
            visible: root.showsCount
            text: (root.status?.count ?? 0) > 99 ? "99+" : String(root.status?.count ?? 0)
            font.pixelSize: 10
            font.weight: 700
            color: ExLooks.colors.accentInk
        }
    }

    // Progress, where the running mark would be, for as long as there is some.
    Rectangle {
        readonly property real length: 24

        visible: root.showsProgress
        width: root.vertical ? 3 : length
        height: root.vertical ? length : 3
        radius: 1.5
        x: root.vertical ? (root.edge === "left" ? 1 : root.width - width - 1) : (root.width - root.stackStep - width) / 2
        y: root.vertical ? (root.height - root.stackStep - height) / 2 : (root.edge === "top" ? 1 : root.height - height - 1)
        color: ExLooks.colors.sliderTrack

        Rectangle {
            width: root.vertical ? parent.width : parent.width * (root.status?.progress ?? 0)
            // Fills from the top down on a dock at the side.
            height: root.vertical ? parent.height * (root.status?.progress ?? 0) : parent.height
            radius: parent.radius
            color: ExLooks.colors.accent

            Behavior on width {
                NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }
            Behavior on height {
                NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
            }
        }
    }

    // Running, and in front when long. Drawn on the side facing the screen edge.
    Rectangle {
        readonly property real length: root.focused ? 16 : 6

        visible: root.running && !root.showsProgress
        width: root.vertical ? 3 : length
        height: root.vertical ? length : 3
        radius: 1.5
        x: root.vertical ? (root.edge === "left" ? 1 : root.width - width - 1) : (root.width - root.stackStep - width) / 2
        y: root.vertical ? (root.height - root.stackStep - height) / 2 : (root.edge === "top" ? 1 : root.height - height - 1)
        color: root.focused ? ExLooks.colors.accent : ExLooks.colors.textDim
        opacity: root.minimized ? 0.5 : 1

        Behavior on width {
            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
        Behavior on height {
            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
        }
    }
}
