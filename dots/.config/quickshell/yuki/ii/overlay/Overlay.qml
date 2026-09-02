import qs
import qs.core
import qs.common.widgets
import qs.core.services
import qs.common
import qs.ii
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property Component regionComponent: Component {
        Region {}
    }

    function toggle() {
        // Nothing of this desktop belongs over the lock screen, and the window
        // below is unmapped there anyway, and a flag left on would come back up
        // with the session and with a focus grab nobody asked for.
        if (GlobalStates.screenLocked) return;
        IiStates.overlayOpen = !IiStates.overlayOpen;
    }

    /**
     * One input region per clickable pinned widget, rebuilt when that set changes.
     *
     * Built here rather than inside the mask's own binding: an object created in a
     * binding is parented to it and outlives every re-evaluation, so each re-run
     * left a whole set of them behind, for as long as the window lived.
     */
    property list<var> widgetRegions: []
    function rebuildWidgetRegions() {
        const stale = root.widgetRegions;
        // A widget destroyed while registered reads back as null, and a null item
        // is a region over the whole window rather than none.
        root.widgetRegions = OverlayContext.clickableWidgets
            .filter(widget => widget)
            .map(widget => root.regionComponent.createObject(root, {
                item: widget
            }));
        stale.forEach(region => region.destroy());
    }
    Connections {
        target: OverlayContext
        function onClickableWidgetsChanged() {
            root.rebuildWidgetRegions();
        }
    }

    /**
     * Built once and hidden, not built on demand.
     *
     * The window used to be a Loader gated on the same flag that opens the
     * overlay, so everything inside it that listened for that flag was created by
     * the very change it wanted to hear, and Qt does not deliver a signal to a
     * connection made while it is being emitted. The focus grab below was
     * therefore never armed on a plain open, and the overlay closed on a click
     * outside only because the canvas behind the widgets happens to cover the
     * screen. It armed only when the window already existed, which is to say only
     * when something was pinned, so the same key behaved differently depending on
     * what had been done earlier in the session.
     */
    PanelWindow {
        id: overlayWindow
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        // Use OnDemand for pinned widgets to allow focus switching with mouse clicks
        WlrLayershell.keyboardFocus: IiStates.overlayOpen ? WlrKeyboardFocus.Exclusive : (OverlayContext.clickableWidgets.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
        visible: (IiStates.overlayOpen || OverlayContext.hasPinnedWidgets) && !GlobalStates.screenLocked
        color: "transparent"

        mask: Region {
            item: IiStates.overlayOpen ? contentLoader.item : null
            regions: root.widgetRegions
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        HyprlandFocusGrab {
            id: grab
            windows: [overlayWindow]
            active: false
            onCleared: () => {
                // The grab is already down by the time this arrives, so there is
                // nothing left to read in `active`. What decides is whether this
                // window is on screen at all: it is unmapped for the lock screen
                // and while nothing is open or pinned, and being told about a grab
                // then is not the user dismissing anything.
                if (!overlayWindow.visible) return;
                IiStates.overlayOpen = false;
            }
        }

        Connections {
            target: IiStates
            function onOverlayOpenChanged() {
                // Named to the service that hands focus back, for the same reason
                // the overview is: with no_focus_fallback nothing takes focus when
                // this closes, and a fullscreen game reads the dead input as a
                // freeze until its pointer lock is re-armed. Being a named owner
                // also holds off another panel's handback while this one is up --
                // that dispatch would otherwise refocus a window out from under
                // the grab, which Hyprland answers by dropping the grab, which
                // closed the overlay on its own.
                if (IiStates.overlayOpen)
                    FocusReturn.remember("overlay");
                else
                    FocusReturn.restore("overlay");
                delayedGrabTimer.restart();
            }
        }

        Timer {
            id: delayedGrabTimer
            interval: Appearance.animation.elementMoveFast.duration
            onTriggered: {
                grab.active = IiStates.overlayOpen;
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            focus: true
            // Nothing to draw while the window is down, and the widgets behind it
            // poll: a graph redraws itself unseen, a mixer keeps its subscription.
            active: overlayWindow.visible
            sourceComponent: OverlayContent {}
        }
    }

    IpcHandler {
        target: "overlay"

        function toggle(): void {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "overlayToggle"
        description: "Toggles overlay on press"

        onPressed: {
            root.toggle();
        }
    }
}
