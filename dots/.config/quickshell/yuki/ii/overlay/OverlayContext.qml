pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import qs.core

Singleton {
    id: root
    
    signal requestCenter(string identifier)

    readonly property list<var> availableWidgets: [
        { identifier: "crosshair", materialSymbol: "point_scan" },
        { identifier: "fpsLimiter", materialSymbol: "animation" },
        { identifier: "floatingImage", materialSymbol: "imagesmode" },
        { identifier: "recorder", materialSymbol: "screen_record" },
        { identifier: "resources", materialSymbol: "browse_activity" },
        { identifier: "notes", materialSymbol: "note_stack" },
        { identifier: "volumeMixer", materialSymbol: "volume_up" },
    ]

    /**
     * Which of the open widgets stay on screen once the overlay is dismissed.
     *
     * Read from the saved state rather than from the widgets. The widgets are
     * drawn inside the window this answer decides whether to build, so asking
     * them was circular: nothing counted as pinned until the window was up, and
     * the window only went up because something counted as pinned. A pinned
     * widget was therefore gone after every restart of the shell until the
     * overlay had been opened by hand once, which is not what pinning promises.
     *
     * The state file is written the moment a pin is toggled, so it can answer
     * before any widget exists -- and it still answers for a widget that has
     * just been destroyed, which the widgets themselves cannot do.
     */
    readonly property list<string> pinnedWidgetIdentifiers: Persistent.states.overlay.open
        .filter(identifier => Persistent.states.overlay[identifier]?.pinned ?? false)

    readonly property bool hasPinnedWidgets: root.pinnedWidgetIdentifiers.length > 0

    property list<var> clickableWidgets: []

    function registerClickableWidget(widget: var, clickable = true) {
        if (clickable) {
            if (!root.clickableWidgets.includes(widget)) {
                root.clickableWidgets.push(widget)
            }
        } else {
            root.clickableWidgets = root.clickableWidgets.filter(w => w !== widget)
        }
    }
}
