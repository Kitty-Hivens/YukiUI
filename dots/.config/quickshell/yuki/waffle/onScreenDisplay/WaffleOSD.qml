import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.waffle.looks
import qs.waffle

Scope {
    id: root

    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "VolumeOSD.qml",
            globalStateValue: "osdVolumeOpen"
        },
        {
            id: "brightness",
            sourceUrl: "BrightnessOSD.qml",
            globalStateValue: "osdBrightnessOpen"
        },
    ]

    function triggerBrightnessOsd() {
        root.currentIndicator = "brightness";
        WStates.osdBrightnessOpen = true;
    }

    function triggerVolumeOSD() {
        root.currentIndicator = "volume";
        WStates.osdVolumeOpen = true;
    }

    // Shows whichever indicator was last in view, the way asking for "the OSD"
    // without naming one reads.
    function trigger() {
        if (root.currentIndicator === "brightness")
            root.triggerBrightnessOsd();
        else
            root.triggerVolumeOSD();
    }

    // Listen to brightness changes
    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.triggerBrightnessOsd();
        }
    }

    // Listen to volume changes
    Connections {
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (Audio.ready)
                root.triggerVolumeOSD();
        }
        function onMutedChanged() {
            if (Audio.ready)
                root.triggerVolumeOSD();
        }
    }

    // Open when global state changes
    Connections {
        target: GlobalStates

        function onOsdBrightnessOpenChanged() {
            if (WStates.osdBrightnessOpen)
                panelLoader.active = true;
        }
        function onOsdVolumeOpenChanged() {
            if (WStates.osdVolumeOpen)
                panelLoader.active = true;
        }
    }

    // The actual thing
    Loader {
        id: panelLoader
        active: false
        onActiveChanged: {
            if (active) return;
            root.indicators.forEach(i => {
                GlobalStates[i.globalStateValue] = false;
            });
        }
        sourceComponent: PanelWindow {
            id: panelWindow

            screen: root.focusedScreen

            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wOnScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.waffles.bar.bottom
                bottom: Config.options.waffles.bar.bottom
            }
            mask: Region {
                item: osdIndicatorLoader
            }

            implicitWidth: osdIndicatorLoader.implicitWidth
            implicitHeight: osdIndicatorLoader.implicitHeight

            Loader {
                id: osdIndicatorLoader
                anchors.fill: parent
                source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl

                Connections {
                    target: osdIndicatorLoader.item
                    function onClosed() {
                        panelLoader.active = false;
                        GlobalStates[root.indicators.find(i => i.id === root.currentIndicator)?.globalStateValue] = false;
                    }
                }

                Behavior on source {
                    id: switchBehavior

                    SequentialAnimation {
                        id: switchAnim
                        // Animate close of current indicator
                        ScriptAction {
                            script: {
                                osdIndicatorLoader.item?.close();
                            }
                        }
                        // Wait for close anim
                        PauseAnimation {
                            duration: osdIndicatorLoader.item?.closeAnimDuration ?? 0
                        }
                        PropertyAction {} // The source change happens here
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osd"

        function trigger(): void {
            root.trigger();
        }
    }

    GlobalShortcut {
        name: "osdTrigger"
        description: "Triggers OSD display"

        onPressed: root.trigger()
    }
}
