import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs.core
import qs.core.services
import qs.experimental.looks

// Volume and brightness as they change, in a pill over the dock on the screen
// in focus. It takes no clicks, and it goes after a moment without change.
Scope {
    id: root

    property string kind: "volume"
    property bool shown: false

    readonly property var screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    readonly property bool muted: Audio.sink?.audio?.muted ?? false
    readonly property real value: root.kind === "brightness"
        ? (Brightness.getMonitorForScreen(root.screen)?.brightness ?? 0)
        : (Audio.sink?.audio?.volume ?? 0)
    readonly property string glyph: root.kind === "brightness" ? "brightness_6"
        : root.muted ? "volume_off"
        : root.value > 0.5 ? "volume_up"
        : root.value > 0 ? "volume_down"
        : "volume_mute"

    function show(kind: string) {
        root.kind = kind;
        root.shown = true;
        loader.active = true;
        hide.restart();
    }

    Timer {
        id: hide
        interval: Config.options?.osd.timeout ?? 1000
        onTriggered: root.shown = false
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.show("brightness");
        }
    }

    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (Audio.ready)
                root.show("volume");
        }
        function onMutedChanged() {
            if (Audio.ready)
                root.show("volume");
        }
    }

    Loader {
        id: loader
        active: false

        sourceComponent: PanelWindow {
            id: window

            readonly property string edge: Config.options.experimental.dock.edge
            readonly property real shadowRoom: 24

            screen: root.screen
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                bottom: window.edge === "bottom"
                top: window.edge === "top"
                left: window.edge === "left"
                right: window.edge === "right"
            }
            implicitWidth: surface.width + 2 * window.shadowRoom
            implicitHeight: surface.height + 2 * window.shadowRoom
            // Seen, never clicked.
            mask: Region {}

            ExFlyoutSurface {
                id: surface

                open: root.shown
                edge: window.edge
                restX: window.shadowRoom
                restY: window.shadowRoom
                width: 300
                height: 52
                radius: height / 2
                onProgressChanged: {
                    if (progress === 0 && !root.shown)
                        loader.active = false;
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: ExLooks.spacing.l
                    anchors.rightMargin: ExLooks.spacing.l
                    spacing: ExLooks.spacing.m

                    ExGlyph {
                        text: root.glyph
                        color: root.muted && root.kind === "volume" ? ExLooks.colors.textDim : ExLooks.colors.text
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: ExLooks.sizes.sliderTrack
                        radius: height / 2
                        color: ExLooks.colors.sliderTrack

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.value))
                            height: parent.height
                            radius: parent.radius
                            color: root.muted && root.kind === "volume" ? ExLooks.colors.textDim : ExLooks.colors.accent

                            Behavior on width {
                                NumberAnimation { duration: ExLooks.motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                            }
                        }
                    }
                    ExText {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.value * 100)
                        role: "label"
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osd"
        function trigger(): void {
            root.show(root.kind);
        }
    }

    GlobalShortcut {
        name: "osdTrigger"
        description: "Shows the volume or brightness display"
        onPressed: root.show(root.kind)
    }
}
