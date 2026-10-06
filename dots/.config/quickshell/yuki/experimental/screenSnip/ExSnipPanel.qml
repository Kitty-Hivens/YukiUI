pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs.core
import qs.core.functions
import qs.core.services
import qs.core.utils
import qs.experimental.looks

// The snipping tool on one screen: the screen as it was when the tool opened,
// dimmed except for what would be taken, and on the screen it opened on, the
// toolbar.
PanelWindow {
    id: window

    required property var modelData
    /** The tool, whose state every screen shares. */
    required property var snip

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(window.modelData)
    readonly property real monitorScale: window.monitor?.scale ?? 1
    /** Where this screen starts in the layout, which windows are placed in. */
    readonly property int originX: window.monitor?.x ?? 0
    readonly property int originY: window.monitor?.y ?? 0
    /** The screen the toolbar and the keyboard are on. */
    readonly property bool leading: window.snip.screenName === window.modelData.name

    // The screen as it is, taken before anything is drawn over it. What is
    // snipped is cut from this picture, so it is what was on screen as the
    // tool opened, not the tool itself.
    readonly property string capturePath: `${Directories.screenshotTemp}/image-${window.modelData.name}`
    property bool ready: false
    TempScreenshotProcess {
        screen: window.modelData
        screenshotPath: window.capturePath
        onExited: window.ready = true
    }

    screen: window.modelData
    visible: window.ready && frozen.status === Image.Ready
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:snip"
    WlrLayershell.layer: WlrLayer.Overlay
    // Taken rather than asked for, on the one screen: a fullscreen window
    // holds on to a keyboard only asked for, and two screens taking it would
    // hand it back and forth.
    WlrLayershell.keyboardFocus: window.leading ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Noted as the screen goes up, while the window it covers still has the
    // keyboard, and given back as it goes.
    readonly property string focusOwner: `exSnip:${window.modelData.name}`
    property bool remembered: false
    onReadyChanged: {
        if (window.ready && window.leading) {
            FocusReturn.remember(window.focusOwner);
            window.remembered = true;
        }
    }
    Component.onDestruction: {
        if (window.remembered)
            FocusReturn.restore(window.focusOwner);
    }

    // Where a drag started and where the pointer is, in this screen.
    property point start: Qt.point(0, 0)
    property point end: Qt.point(0, 0)
    property bool drawing: false
    readonly property rect drawn: Qt.rect(Math.min(window.start.x, window.end.x), Math.min(window.start.y, window.end.y),
        Math.abs(window.end.x - window.start.x), Math.abs(window.end.y - window.start.y))

    /**
     * The window under the pointer on the workspace this screen shows, in this
     * screen's coordinates: of those there, the one last used, which is the
     * one in front.
     */
    readonly property var windowUnder: {
        if (window.snip.area !== "window" || !pointer.containsMouse)
            return null;
        const workspace = window.monitor?.activeWorkspace?.id ?? -1;
        const x = pointer.mouseX + window.originX;
        const y = pointer.mouseY + window.originY;
        const found = HyprlandData.windowList
            .filter(client => client.workspace.id === workspace && client.mapped !== false && !client.hidden)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)
            .find(client => x >= client.at[0] && x < client.at[0] + client.size[0] && y >= client.at[1] && y < client.at[1] + client.size[1]);
        return found ? Qt.rect(found.at[0] - window.originX, found.at[1] - window.originY, found.size[0], found.size[1]) : null;
    }

    /** What would be taken now, in this screen's coordinates, or null. */
    readonly property var target: window.snip.area === "rect" ? (window.drawn.width >= 4 && window.drawn.height >= 4 ? window.drawn : null)
        : window.snip.area === "window" ? window.windowUnder
        : (pointer.containsMouse ? Qt.rect(0, 0, window.width, window.height) : null)

    /** Takes a part of this screen, as the tool is set. */
    function take(area) {
        const action = window.snip.action();
        // A picture is cut from this screen's own capture, in its pixels. A
        // video is recorded from a part of the whole layout, in its points.
        const video = action === ScreenshotAction.Action.Record || action === ScreenshotAction.Action.RecordWithSound;
        const factor = video ? 1 : window.monitorScale;
        const x = (area.x + (video ? window.originX : 0)) * factor;
        const y = (area.y + (video ? window.originY : 0)) * factor;
        window.snip.run(ScreenshotAction.getCommand(x, y, area.width * factor, area.height * factor,
            window.capturePath, action, Config.options.screenSnip.savePath));
    }

    // The picture the snip is cut from, shown as it is. A frozen screen copy
    // was taken as the window first showed, and so held the window's own
    // dimming under the dimming drawn over it.
    Image {
        id: frozen
        anchors.fill: parent
        source: window.ready ? FileUtils.fileUrl(window.capturePath) : ""
        cache: false
        smooth: true
        fillMode: Image.Stretch
    }

    Item {
        anchors.fill: parent
        focus: window.leading
        Keys.onEscapePressed: window.snip.close()

        // The dimming, in four pieces round what would be taken, so that it
        // shows as it is.
        readonly property color veil: "#80000000"
        readonly property rect hole: window.target ?? Qt.rect(0, 0, 0, 0)
        readonly property bool open: window.target !== null

        Rectangle {
            width: parent.width
            height: parent.open ? parent.hole.y : parent.height
            color: parent.veil
        }
        Rectangle {
            visible: parent.open
            y: parent.hole.y + parent.hole.height
            width: parent.width
            height: parent.height - y
            color: parent.veil
        }
        Rectangle {
            visible: parent.open
            y: parent.hole.y
            width: parent.hole.x
            height: parent.hole.height
            color: parent.veil
        }
        Rectangle {
            visible: parent.open
            x: parent.hole.x + parent.hole.width
            y: parent.hole.y
            width: parent.width - x
            height: parent.hole.height
            color: parent.veil
        }
        Rectangle {
            visible: parent.open
            x: parent.hole.x - 1
            y: parent.hole.y - 1
            width: parent.hole.width + 2
            height: parent.hole.height + 2
            color: "transparent"
            border.width: 2
            border.color: ExLooks.colors.accent
        }

        // The size of a rectangle being drawn, just outside its far corner.
        Rectangle {
            visible: window.drawing && parent.open
            x: Math.max(8, Math.min(parent.width - width - 8, parent.hole.x + parent.hole.width - width))
            y: parent.hole.y + parent.hole.height + 8 + height > parent.height
                ? parent.hole.y - height - 8 : parent.hole.y + parent.hole.height + 8
            width: sizeLabel.implicitWidth + 2 * ExLooks.spacing.s
            height: 26
            radius: ExLooks.radius.menuItem
            color: ExLooks.colors.accent

            ExText {
                id: sizeLabel
                anchors.centerIn: parent
                text: `${Math.round(parent.parent.hole.width * window.monitorScale)} × ${Math.round(parent.parent.hole.height * window.monitorScale)}`
                role: "label"
                color: ExLooks.colors.accentInk
            }
        }

        MouseArea {
            id: pointer

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: window.snip.area === "rect" ? Qt.CrossCursor : Qt.PointingHandCursor

            onPressed: event => {
                if (event.button === Qt.RightButton) {
                    window.snip.close();
                    return;
                }
                if (window.snip.area !== "rect")
                    return;
                window.start = Qt.point(event.x, event.y);
                window.end = window.start;
                window.drawing = true;
            }
            onPositionChanged: event => {
                if (window.drawing)
                    window.end = Qt.point(Math.max(0, Math.min(width, event.x)), Math.max(0, Math.min(height, event.y)));
            }
            onReleased: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                const area = window.target;
                window.drawing = false;
                if (area)
                    window.take(area);
            }
        }

        ExSnipToolbar {
            visible: window.leading
            anchors.horizontalCenter: parent.horizontalCenter
            y: ExLooks.spacing.xl
            snip: window.snip
        }
    }
}
