pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.core.services
import qs.core
import qs.common.widgets
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

                // Leaves the screen to a fullscreen window on this monitor, which is what
                // lets Hyprland hand the game the screen whole (its solitary path, which
                // is what VRR pacing wants and which direct scanout is not required for).
                // The bar parks and stops drawing to do it, and keeps its window.
                property bool fullscreenOnThisMonitor: GameMode.fullscreenOn(barLoader.modelData.name)
                property bool hideForFullscreen: (Config?.options.bar.hideWhenFullscreen ?? false) && barRoot.fullscreenOnThisMonitor
                /// Whether the game has kept this screen long enough for the window to
                /// be worth giving up as well. See GameMode.standDownOn.
                property bool standDownForFullscreen: barRoot.hideForFullscreen && GameMode.standDownOn(barLoader.modelData.name)
                visible: barRoot.mapped

                /// Whether the bar is on screen at all. Seeded from the state at build
                /// time, then driven by the handler below.
                property bool mapped: !barRoot.standDownForFullscreen

                /**
                 * Whether the content is standing off the screen edge it is anchored to.
                 *
                 * This is how the bar leaves a game, and by default it is the whole of it:
                 * the content slides off, nothing of the bar is drawn over the game, and
                 * the window is left alone, so stepping back out is a slide in on a live
                 * window and costs nothing. Where the delay is set, the window is given up
                 * once the game has held the screen that long, and by then the content is
                 * parked already, so there is nothing to see in it. See
                 * GameMode.standDownOn for what that second step buys and what it costs.
                 *
                 * Seeded from the state at build time so a bar built while a game already
                 * holds the screen comes up parked instead of sliding out in front of it.
                 */
                property bool parked: barRoot.hideForFullscreen

                /**
                 * Whether the bar has stopped drawing.
                 *
                 * Nothing of it is on screen once it is parked, so there is nothing for
                 * the shell to render there, and every frame it submits anyway is a frame
                 * the compositor has to collect instead of handing the screen to the game.
                 * With updates off the window stays where it is, holding its last frame,
                 * and costs the game nothing but the compositing of one transparent strip.
                 *
                 * Only after the slide has finished, or the bar freezes half way out.
                 */
                property bool drawingStopped: false
                updatesEnabled: !barRoot.drawingStopped

                Timer {
                    id: stopDrawingTimer
                    interval: Appearance.animation.elementMoveFast.duration + 50
                    onTriggered: barRoot.drawingStopped = true
                }

                /// Where the content is: away for a game, and away for autoHide until
                /// something asks the bar back.
                property bool contentAway: barRoot.parked || (Config?.options.bar.autoHide.enable && !barRoot.mustShow)

                /**
                 * Both halves of leaving, in one place, because the two signals they
                 * answer to can change in the same breath.
                 *
                 * The window's state goes first whenever it changes, because it gates the
                 * slide (see the behaviours on the content's margins): with the bar off
                 * screen the park is taken at once rather than played to nobody, and on the
                 * way back the window is up, still parked, before the slide is armed.
                 */
                function syncFullscreenHide() {
                    if (barRoot.hideForFullscreen) {
                        if (barRoot.standDownForFullscreen) {
                            slideStarter.running = false;
                            slideDeadline.stop();
                            stopDrawingTimer.stop();
                            barRoot.mapped = false;
                        } else {
                            stopDrawingTimer.restart();
                        }
                        barRoot.parked = true;
                        return;
                    }
                    // Drawing comes back before anything else. A window mapped with its
                    // updates off never renders, and a slide nobody draws is not a slide.
                    stopDrawingTimer.stop();
                    barRoot.drawingStopped = false;
                    const wasGone = !barRoot.mapped;
                    barRoot.mapped = true;
                    if (!barRoot.parked)
                        return;
                    // A window nobody gave up has nothing to rebuild, so there is no stall
                    // to wait out and the slide starts here.
                    if (!wasGone) {
                        barRoot.startSlide();
                        return;
                    }
                    slideStarter.running = true;
                    slideDeadline.restart();
                }
                onHideForFullscreenChanged: barRoot.syncFullscreenHide()
                onStandDownForFullscreenChanged: barRoot.syncFullscreenHide()

                /**
                 * Lets the bar back in on the first frame that arrives on time, rather
                 * than at the moment the window is mapped.
                 *
                 * Leaving a fullscreen window, the shell's first two frames land 98ms and
                 * 53ms apart, measured on a screen that otherwise paces them at 4ms, and a
                 * slide started into that gap is spent before anything is drawn of it: one
                 * recording has the content going from off screen to a pixel short of home
                 * in two steps, which is a bar that simply appears. Waiting for the pacing
                 * to come back costs about a sixth of a second of no bar and buys the whole
                 * slide.
                 */
                FrameAnimation {
                    id: slideStarter
                    running: false
                    onTriggered: {
                        if (slideStarter.frameTime > 0.025)
                            return;
                        barRoot.startSlide();
                    }
                }

                /// A bar whose frames never come back on time still has to come back.
                /// Anything pacing slower than forty a second lands here and gets what it
                /// got before any of this: a bar that is simply there.
                Timer {
                    id: slideDeadline
                    interval: 400
                    onTriggered: barRoot.startSlide()
                }

                function startSlide() {
                    slideStarter.running = false;
                    slideDeadline.stop();
                    barRoot.parked = false;
                }

                /// Named to the shared grab only while it is on screen. Hyprland drops a
                /// grab that names an unmapped surface, and the drop reaches the shell as a
                /// dismissal, which closes every panel that answers to one. See the same
                /// guard on the media controls.
                function syncGrabRegistration() {
                    if (barRoot.visible)
                        GlobalFocusGrab.addPersistent(barRoot);
                    else
                        GlobalFocusGrab.removePersistent(barRoot);
                }
                onVisibleChanged: barRoot.syncGrabRegistration()

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
                    Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                WlrLayershell.namespace: "quickshell:bar"
                implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                mask: Region {
                    // Nothing to reach for while the bar is parked for a game. The sliver
                    // the hover region leaves at the edge belongs to autoHide, and over a
                    // game it would only take the pointer.
                    item: barRoot.parked ? null : hoverMaskRegion
                }
                color: "transparent"

                // Positioning
                anchors {
                    top: !Config.options.bar.bottom
                    bottom: Config.options.bar.bottom
                    left: true
                    right: true
                }

                margins {
                    right: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                    bottom: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                }

                // Include in focus grab
                Component.onCompleted: {
                    // A bar built while a game already holds the screen comes up parked,
                    // and nothing changes afterwards to stop its drawing, so that is
                    // started here. Locking the session is the way in: it takes the bar
                    // down and hands back a new one with the game still on the screen.
                    //
                    // Through the timer rather than at once, because a window whose
                    // updates are off from birth never commits a buffer, and a layer
                    // surface with no buffer is not on the screen at all, which is where
                    // the strip it reserves for itself comes from.
                    if (barRoot.parked)
                        stopDrawingTimer.restart();
                    barRoot.syncGrabRegistration();
                }
                Component.onDestruction: {
                    GlobalFocusGrab.removePersistent(barRoot);
                }

                MouseArea  {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        fill: parent
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * 1
                    }

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            topMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            bottomMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    BarContent {
                        id: barContent
                        
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: barRoot.contentAway ? -Appearance.sizes.barHeight : 0
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.bottom) * -1
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable && barRoot.anchors.right) * -1
                        }
                        // Only ever animated while the bar is on screen. Off it, the
                        // margin is the parked position and is taken as one.
                        Behavior on anchors.topMargin {
                            enabled: barRoot.mapped
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on anchors.bottomMargin {
                            enabled: barRoot.mapped
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: barRoot.contentAway ? -Appearance.sizes.barHeight : 0
                            }
                        }
                    }

                    // Round decorators
                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: showBarBackground && Config.options.bar.cornerStyle === 0 // Hug

                        states: State {
                            name: "bottom"
                            when: Config.options.bar.bottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                }

                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    right: parent.right
                                    top: !Config.options.bar.bottom ? parent.top : undefined
                                    bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: showBarBackground ? Appearance.colors.colLayer0 : "transparent"

                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: Config.options.bar.bottom
                                    PropertyChanges {
                                        rightCorner.corner: RoundCorner.CornerEnum.BottomRight
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
