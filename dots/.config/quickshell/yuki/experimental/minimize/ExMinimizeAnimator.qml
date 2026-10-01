pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

import qs.core.services
import qs.experimental
import qs.experimental.looks

// Windows going into the dock and coming back out of it.
//
// Hyprland has no minimising and so nothing to draw it with. A picture of the
// window is taken instead and flown over everything into its application's
// button, and the window itself is moved out of sight the moment the picture
// covers it. Coming back, a new picture flies out of the button to where the
// window stood, and the window returns once it is there. A minimised window
// can still be pictured, so nothing is kept in between.
//
// The overlay a screen draws this on exists only while something is in the
// air. A layer left over a fullscreen game, even an empty one, would keep the
// game from being shown on its own.
Scope {
    id: root

    /** What is in the air, one entry per window. */
    property var flights: []
    property int nextId: 0

    property int duration: 300

    /** A batch of windows whose pictures are all in place: they can go now. */
    signal released(var batch)

    function toplevelOf(address: string): var {
        const bare = address.replace(/^0x/, "");
        return ToplevelManager.toplevels.values.find(toplevel => (toplevel.HyprlandToplevel?.address ?? "") === bare) ?? null;
    }

    /**
     * Where a window stands, in the coordinates of its screen. One coming back
     * lands where it stood before it was minimised, when that was kept.
     */
    function placeOf(win, kind: string): var {
        const monitor = HyprlandData.monitors.find(candidate => candidate.id === win.monitor);
        if (!monitor)
            return null;
        const at = (kind === "restore" ? Minimize.placeOf(win.address) : null) ?? win.at;
        return { screen: monitor.name, x: at[0] - monitor.x, y: at[1] - monitor.y, w: win.size[0], h: win.size[1] };
    }

    function buttonOf(screen: string, appId: string, address: string): var {
        const dock = ExStates.dockWindows.find(candidate => candidate.screen?.name === screen);
        return dock ? dock.buttonRect(appId, address) : null;
    }

    /** What the dock knows the window's application by. */
    function appIdOf(win, toplevel): string {
        return (toplevel?.appId || win.class || "").toLowerCase();
    }

    function minimize(windows, go) {
        root.launch("minimize", windows, go);
    }

    function restore(windows, go) {
        root.launch("restore", windows, go);
    }

    function launch(kind: string, windows, go) {
        const batch = { left: 0, go: go, released: false };
        const added = [];
        for (const win of windows) {
            const toplevel = root.toplevelOf(win.address);
            const place = root.placeOf(win, kind);
            const appId = root.appIdOf(win, toplevel);
            const button = place ? root.buttonOf(place.screen, appId, win.address) : null;
            // Only a window on the workspace its screen shows is seen going or
            // coming. One asking to be minimised from a workspace out of sight,
            // or put back onto one, just goes.
            // Read from Quickshell, which follows workspace changes, where the
            // monitor list the window data comes with is only refreshed when
            // monitors change.
            const monitor = Hyprland.monitors.values.find(candidate => candidate.id === win.monitor);
            const workspace = kind === "minimize" ? win.workspace.id : Minimize.originOf(win);
            if (!monitor || monitor.activeWorkspace?.id !== workspace)
                continue;
            // Nothing to fly from or to: that window just goes.
            if (!toplevel || !place || !button || win.fullscreen > 0)
                continue;
            batch.left++;
            added.push({
                id: root.nextId++,
                kind: kind,
                screen: place.screen,
                window: place,
                button: button,
                toplevel: toplevel,
                icon: AppSearch.iconFor(appId),
                batch: batch
            });
        }
        if (added.length === 0) {
            go();
            return;
        }
        root.flights = [...root.flights, ...added];
    }

    /** One window of a batch is ready: pictured on the way in, arrived on the way out. */
    function ready(flight) {
        const batch = flight.batch;
        batch.left--;
        if (batch.left > 0 || batch.released)
            return;
        batch.released = true;
        batch.go();
        root.released(batch);
    }

    function land(flight) {
        root.flights = root.flights.filter(other => other.id !== flight.id);
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope

            required property var modelData
            readonly property var mine: root.flights.filter(flight => flight.screen === screenScope.modelData.name)

            // Made for each round of flights and dropped after it. A layer
            // window hidden and shown again did not draw the second time.
            Loader {
                active: screenScope.mine.length > 0

                sourceComponent: PanelWindow {
                    id: overlay

                    readonly property var mine: screenScope.mine

                    screen: screenScope.modelData
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:minimize"
                    WlrLayershell.layer: WlrLayer.Overlay
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    // Seen, never clicked.
                    mask: Region {}

                    Repeater {
                        model: ScriptModel {
                            values: overlay.mine
                            objectProp: "id"
                        }

                        Item {
                            id: flight

                            required property var modelData
                            readonly property bool leaving: flight.modelData.kind === "minimize"
                            readonly property var win: flight.modelData.window
                            readonly property var button: flight.modelData.button
                            // The picture keeps the window's shape all the way, only
                            // smaller, so it fits into the button rather than being
                            // squashed to its square.
                            readonly property real small: Math.min(flight.button.w / flight.win.w, flight.button.h / flight.win.h) * 0.7
                            /** Set off: with its picture, or without once waiting for one is over. */
                            property bool started: false

                            /** 0 where the window stands, 1 in the button. */
                            property real travel: flight.leaving ? 0 : 1

                            x: flight.win.x + (flight.button.x + flight.button.w / 2 - flight.win.x - flight.win.w / 2) * flight.travel
                            y: flight.win.y + (flight.button.y + flight.button.h / 2 - flight.win.y - flight.win.h / 2) * flight.travel
                            width: flight.win.w
                            height: flight.win.h
                            scale: 1 + (flight.small - 1) * flight.travel
                            opacity: 1 - Math.pow(flight.travel, 3)
                            // Nothing shows before it sets off. A window coming
                            // back would otherwise sit in the button as a dot.
                            visible: flight.leaving || flight.started

                            function setOff() {
                                if (flight.started)
                                    return;
                                flight.started = true;
                                fly.start();
                            }

                            NumberAnimation {
                                id: fly
                                target: flight
                                property: "travel"
                                to: flight.leaving ? 1 : 0
                                duration: root.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: flight.leaving ? ExLooks.motion.exit : ExLooks.motion.enter
                                onFinished: {
                                    if (flight.leaving) {
                                        root.land(flight.modelData);
                                    } else {
                                        root.ready(flight.modelData);
                                        settle.start();
                                    }
                                }
                            }

                            // The window is asked back when the picture arrives and
                            // takes a moment to show, so the picture stays over it
                            // until it has.
                            Timer {
                                id: settle
                                interval: 150
                                onTriggered: root.land(flight.modelData)
                            }

                            ScreencopyView {
                                id: shot

                                anchors.fill: parent
                                captureSource: flight.modelData.toplevel
                                live: false
                                paintCursor: false
                                onHasContentChanged: {
                                    if (!shot.hasContent)
                                        return;
                                    if (flight.leaving)
                                        shown.start();
                                    else
                                        flight.setOff();
                                }
                            }

                            // Leaving: the window is let go once its picture is on
                            // screen over it, two frames after it arrived, and a
                            // moment later the picture sets off, so it does not
                            // leave the window behind in plain sight.
                            Timer {
                                id: shown
                                interval: 34
                                onTriggered: root.ready(flight.modelData)
                            }
                            Connections {
                                target: root
                                function onReleased(batch) {
                                    if (batch === flight.modelData.batch && flight.leaving)
                                        startDelay.start();
                                }
                            }
                            Timer {
                                id: startDelay
                                interval: 40
                                onTriggered: flight.setOff()
                            }

                            // A picture that does not come in time: a window
                            // leaving goes without one, and one coming back
                            // flies out as its application's icon on a card.
                            Timer {
                                interval: 200
                                running: true
                                onTriggered: {
                                    if (shot.hasContent)
                                        return;
                                    if (flight.leaving) {
                                        root.ready(flight.modelData);
                                        root.land(flight.modelData);
                                    } else {
                                        flight.setOff();
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: !flight.leaving && !shot.hasContent
                                radius: ExLooks.radius.tile / Math.max(0.05, flight.scale)
                                color: ExLooks.colors.surface
                                border.width: 1
                                border.color: ExLooks.colors.hairline

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: Math.min(parent.width, parent.height) * 0.3
                                    source: flight.modelData.icon ?? ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
