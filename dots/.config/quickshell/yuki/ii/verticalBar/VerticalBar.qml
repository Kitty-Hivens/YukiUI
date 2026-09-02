import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.common
import qs.ii

Scope {
    id: bar
    property bool showBarBackground: Config.options.bar.showBackground

    Variants {
        // For each monitor
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }
        LazyLoader {
            id: barLoader
            active: IiStates.barOpen && !GlobalStates.screenLocked
            required property ShellScreen modelData
            component: PanelWindow { // Bar window
                id: barRoot
                screen: barLoader.modelData

                property var brightnessMonitor: Brightness.getMonitorForScreen(barLoader.modelData)
                
                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: {
                        barRoot.superShow = true
                    }
                }
                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
                        if (GlobalStates.superDown) showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            barRoot.superShow = false;
                        }
                    }
                }
                property bool superShow: false
                property bool mustShow: hoverRegion.containsMouse || superShow
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows)) ? 0 :
                    Appearance.sizes.baseVerticalBarWidth + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                WlrLayershell.namespace: "quickshell:verticalBar"
                // WlrLayershell.layer: WlrLayer.Overlay // TODO enable this when bar can hide when fullscreen

                // Steps aside for a fullscreen window on its own monitor, the way the
                // horizontal bar does. It did not, so the setting that says the bar gets
                // out of the way of a game did nothing at all in this layout, and the
                // strip it reserves stayed reserved.
                property bool fullscreenOnThisMonitor: GameMode.fullscreenOn(barLoader.modelData.name)
                visible: !(Config?.options.bar.hideWhenFullscreen && fullscreenOnThisMonitor)
                implicitWidth: Appearance.sizes.verticalBarWidth + Appearance.rounding.screenRounding
                mask: Region {
                    item: hoverMaskRegion
                }
                color: "transparent"

                // Positioning
                anchors {
                    left: !Config.options.bar.bottom
                    right: Config.options.bar.bottom
                    top: true
                    bottom: true
                }

                /// Named to the shared grab only while it is on screen, for the reason
                /// spelled out on the media controls: Hyprland drops a grab that names an
                /// unmapped surface, and that drop reaches the shell as a dismissal.
                function syncGrabRegistration() {
                    if (barRoot.visible)
                        GlobalFocusGrab.addPersistent(barRoot);
                    else
                        GlobalFocusGrab.removePersistent(barRoot);
                }
                onVisibleChanged: barRoot.syncGrabRegistration()
                Component.onCompleted: {
                    barRoot.syncGrabRegistration();
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            rightMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    VerticalBarContent {
                        id: barContent
                        
                        implicitWidth: Appearance.sizes.verticalBarWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: undefined
                            leftMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.verticalBarWidth : 0
                            rightMargin: 0
                        }
                        Behavior on anchors.leftMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: parent.right
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.rightMargin: (Config?.options.bar.autoHide.enable && !mustShow) ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 // Hug

                        states: State {
                            name: "right"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        topCorner.corner: RoundCorner.CornerEnum.TopRight
                                    }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !Config.options.bar.bottom ? parent.left : undefined
                                    right: Config.options.bar.bottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        bottomCorner.corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            IiStates.barOpen = !IiStates.barOpen
        }

        function close(): void {
            IiStates.barOpen = false
        }

        function open(): void {
            IiStates.barOpen = true
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            IiStates.barOpen = !IiStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            IiStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            IiStates.barOpen = false;
        }
    }
}
