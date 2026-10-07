pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.core
import qs.core.functions
import qs.core.services
import qs.experimental.looks

// The clipboard history on Win+V, as Windows 11 has it: what was copied
// lately, newest first, text, pictures and files alike, by the pointer. A
// click, or Enter, puts it back on the clipboard and pastes it into the window
// that was in use. Each can be pinned to stay, or deleted, and the rest
// cleared.
//
// Every form an entry was copied in is kept, and goes back on with it, so
// files copied in the file manager paste as files again. scripts/clipboard/
// history.py keeps them, as they are copied, and leaves out anything a
// password manager marks as secret.
Scope {
    id: root

    readonly property string script: FileUtils.trimFileProtocol(`${Directories.scriptPath}/clipboard/history.py`)
    readonly property string indexFile: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/clipboard/index.json`

    property bool open: false
    property var entries: []
    /** The entry the keys are on. */
    property int current: 0

    // Where it opens: by the pointer, on the screen the pointer is on, and
    // the window it pastes into, as they were when it opened.
    property string screenName: ""
    property point at: Qt.point(0, 0)
    property string target: ""
    property string targetClass: ""

    /** Terminals take a paste on Ctrl+Shift+V, Ctrl+V being a key of their own. */
    readonly property var terminals: ["kitty", "foot", "footclient", "Alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty",
        "org.gnome.Ptyxis", "org.gnome.Console", "org.kde.konsole", "xterm"]

    function show() {
        if (GlobalStates.screenLocked)
            return;
        root.current = 0;
        cursor.running = true;
    }
    function close() {
        root.open = false;
    }
    function toggle() {
        if (root.open)
            root.close();
        else
            root.show();
    }

    // Asked of the compositor as it opens, the pointer and the window in use
    // together.
    Process {
        id: cursor
        command: ["sh", "-c", 'printf "[%s,%s]" "$(hyprctl -j cursorpos)" "$(hyprctl -j activewindow)"']
        stdout: StdioCollector {
            id: cursorOut
            onStreamFinished: {
                let point = { x: 0, y: 0 };
                let window = {};
                try {
                    [point, window] = JSON.parse(cursorOut.text);
                } catch (error) {}
                root.target = window?.address ?? "";
                root.targetClass = window?.class ?? "";
                const monitor = Hyprland.monitors.values.find(m => point.x >= m.x && point.x < m.x + m.width / (m.scale || 1)
                    && point.y >= m.y && point.y < m.y + m.height / (m.scale || 1)) ?? Hyprland.focusedMonitor;
                root.screenName = monitor?.name ?? Quickshell.screens[0]?.name ?? "";
                root.at = Qt.point(point.x - (monitor?.x ?? 0), point.y - (monitor?.y ?? 0));
                root.open = true;
            }
        }
    }

    /** Puts an entry back on the clipboard, and pastes it where the person was. */
    function choose(id: string) {
        root.close();
        offer.command = ["python3", root.script, "offer", id];
        offer.running = true;
    }
    Process {
        id: offer
        onExited: exitCode => {
            if (exitCode === 0 && root.target.length > 0)
                pasteLater.restart();
        }
    }
    // Once the window has the keyboard back.
    Timer {
        id: pasteLater
        interval: 250
        onTriggered: {
            const mods = root.terminals.includes(root.targetClass) ? "CTRL SHIFT" : "CTRL";
            Hyprland.dispatch(`hl.dsp.send_shortcut({ mods = "${mods}", key = "V", window = "address:${root.target}" })`);
        }
    }

    /** Pins, deletes or clears, and reads the history again once done. */
    function run(...words) {
        action.createObject(root, { command: ["python3", root.script, ...words] }).running = true;
    }
    Component {
        id: action
        Process {
            id: job
            onExited: {
                index.reload();
                job.destroy();
            }
        }
    }

    // What is copied is kept as it is copied, while this desktop is up. Each
    // copy kept says so with a line, and the history is read again: a file
    // that was not there as the shell started is not watched for changes.
    Process {
        running: true
        command: ["wl-paste", "--watch", "sh", "-c", 'python3 "$1" store; echo kept', "clipboard-history", root.script]
        stdout: SplitParser {
            onRead: index.reload()
        }
    }

    FileView {
        id: index
        path: root.indexFile
        watchChanges: true
        printErrors: false
        onFileChanged: index.reload()
        onLoaded: {
            try {
                root.entries = JSON.parse(index.text());
            } catch (error) {
                root.entries = [];
            }
            root.current = Math.max(0, Math.min(root.current, root.entries.length - 1));
        }
        onLoadFailed: root.entries = []
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.close();
        }
    }

    Variants {
        model: root.open ? Quickshell.screens.filter(screen => screen.name === root.screenName).slice(0, 1) : []

        PanelWindow {
            id: window

            required property var modelData

            readonly property real shadowRoom: 32

            screen: window.modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:clipboard"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                left: true
            }
            // By the pointer, kept on the screen.
            margins {
                left: Math.max(0, Math.min(root.at.x - window.shadowRoom, window.screen.width - window.implicitWidth))
                top: Math.max(0, Math.min(root.at.y - window.shadowRoom, window.screen.height - window.implicitHeight))
            }
            implicitWidth: plane.width + 2 * window.shadowRoom
            implicitHeight: plane.height + 2 * window.shadowRoom
            mask: Region {
                item: plane
            }

            readonly property string focusOwner: "exClipboard"
            Component.onCompleted: FocusReturn.remember(window.focusOwner)
            Component.onDestruction: FocusReturn.restore(window.focusOwner)

            // A click anywhere else puts it away.
            HyprlandFocusGrab {
                active: true
                windows: [window]
                onCleared: root.close()
            }

            ExSurface {
                id: plane

                x: window.shadowRoom
                y: window.shadowRoom
                width: 380
                height: Math.min(520, column.implicitHeight + 2 * ExLooks.spacing.m)
                radius: ExLooks.radius.menu
                elevation: 2
                focus: true

                opacity: 0
                Component.onCompleted: plane.opacity = 1
                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }

                Keys.onPressed: event => {
                    const count = root.entries.length;
                    if (event.key === Qt.Key_Escape) {
                        root.close();
                    } else if (event.key === Qt.Key_Down && count > 0) {
                        root.current = Math.min(count - 1, root.current + 1);
                    } else if (event.key === Qt.Key_Up && count > 0) {
                        root.current = Math.max(0, root.current - 1);
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && count > 0) {
                        root.choose(root.entries[root.current].id);
                    } else if (event.key === Qt.Key_Delete && count > 0) {
                        root.run("delete", root.entries[root.current].id);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                ColumnLayout {
                    id: column

                    x: ExLooks.spacing.m
                    y: ExLooks.spacing.m
                    width: plane.width - 2 * ExLooks.spacing.m
                    height: plane.height - 2 * ExLooks.spacing.m
                    spacing: ExLooks.spacing.s

                    RowLayout {
                        Layout.fillWidth: true

                        ExText {
                            Layout.fillWidth: true
                            text: Translation.tr("Clipboard")
                            role: "title"
                        }
                        ExButton {
                            kind: "flat"
                            text: Translation.tr("Clear all")
                            enabled: root.entries.some(entry => !entry.pinned)
                            onClicked: root.run("clear")
                        }
                    }

                    // Nothing yet.
                    ColumnLayout {
                        visible: root.entries.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: ExLooks.spacing.l
                        Layout.bottomMargin: ExLooks.spacing.l
                        spacing: ExLooks.spacing.xs

                        ExGlyph {
                            Layout.alignment: Qt.AlignHCenter
                            text: "content_paste"
                            size: 32
                            color: ExLooks.colors.textDim
                        }
                        ExText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Nothing copied yet")
                            role: "label"
                        }
                        ExText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Copy something to see it here.")
                            role: "caption"
                            dim: true
                        }
                    }

                    ListView {
                        id: list

                        visible: root.entries.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: list.contentHeight
                        spacing: ExLooks.spacing.s
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.entries
                        currentIndex: root.current
                        highlightFollowsCurrentItem: false
                        onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

                        delegate: Card {}
                    }
                }
            }
        }
    }

    // One entry: what it holds, and its pin and delete buttons on the side.
    component Card: Rectangle {
        id: card

        required property var modelData
        required property int index
        readonly property bool here: card.index === root.current

        width: ListView.view.width
        implicitHeight: Math.max(56, body.implicitHeight + 2 * ExLooks.spacing.m)
        radius: ExLooks.radius.card
        color: ExLooks.colors.surfaceSunken
        border.width: card.here ? 2 : 0
        border.color: ExLooks.colors.accent

        MouseArea {
            id: press

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            onEntered: root.current = card.index
            onClicked: root.choose(card.modelData.id)
        }
        ExStateLayer {
            radius: card.radius
            ink: ExLooks.colors.text
            hovered: press.containsMouse
            pressed: press.pressed
        }

        ColumnLayout {
            id: body

            x: ExLooks.spacing.m
            y: ExLooks.spacing.m
            width: card.width - 2 * ExLooks.spacing.m - tools.width - ExLooks.spacing.s
            spacing: ExLooks.spacing.xs

            ExText {
                visible: card.modelData.kind === "text"
                Layout.fillWidth: true
                text: card.modelData.preview.trim()
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            Image {
                visible: card.modelData.kind === "image"
                Layout.maximumWidth: body.width
                Layout.maximumHeight: 140
                Layout.preferredWidth: Math.min(body.width, implicitWidth * 140 / Math.max(1, implicitHeight))
                Layout.preferredHeight: Math.min(140, implicitHeight * body.width / Math.max(1, implicitWidth))
                source: visible ? FileUtils.fileUrl(card.modelData.image) : ""
                sourceSize.width: 640
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Repeater {
                model: card.modelData.kind === "files" ? card.modelData.preview.split("\n").slice(0, 3) : []

                RowLayout {
                    required property string modelData

                    Layout.fillWidth: true
                    spacing: ExLooks.spacing.s

                    ExGlyph {
                        text: "draft"
                        size: 18
                        color: ExLooks.colors.textDim
                    }
                    ExText {
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideMiddle
                    }
                }
            }
            ExText {
                readonly property int more: card.modelData.kind === "files" ? card.modelData.preview.split("\n").length - 3 : 0
                visible: more > 0
                text: Translation.tr("and %1 more").arg(more)
                role: "caption"
                dim: true
            }
        }

        Column {
            id: tools

            anchors.right: parent.right
            anchors.rightMargin: ExLooks.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            // Shown while it is pointed at or chosen, and always once pinned.
            opacity: card.here || press.containsMouse || card.modelData.pinned ? 1 : 0

            ExToolButton {
                implicitWidth: 32
                implicitHeight: 32
                glyph: "keep"
                toggled: card.modelData.pinned
                onClicked: root.run("pin", card.modelData.id, card.modelData.pinned ? "0" : "1")
            }
            ExToolButton {
                implicitWidth: 32
                implicitHeight: 32
                glyph: "delete"
                onClicked: root.run("delete", card.modelData.id)
            }
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Opens or closes the clipboard history"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "clipboardHistory"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.close();
        }
        function isOpen(): bool {
            return root.open;
        }
        function entries(): string {
            return JSON.stringify(root.entries.map(entry => ({ id: entry.id, kind: entry.kind, preview: entry.preview, pinned: entry.pinned,
                forms: entry.forms.map(form => form.type) })));
        }
        function choose(index: int): void {
            const entry = root.entries[index];
            if (entry)
                root.choose(entry.id);
        }
    }
}
