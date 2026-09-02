pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import qs.core

Singleton {
    id: root
    
    signal requestCenter(string identifier)

    /**
     * The widgets there are, and the objects that stand for them.
     *
     * Held as a var rather than a list<var> because the identity of the entries
     * is load bearing. Reading a list<var> marshals it through a variant list
     * and hands back fresh objects every time, so the model that lists the open
     * widgets saw every row as changed on every evaluation. Its reconciliation
     * answers that by overwriting rows positionally without looking at the key
     * again, which leaves a delegate built for one widget holding another one's
     * entry: a widget drawn with its own contents under someone else's title, at
     * someone else's saved position. With the identity stable the comparison
     * reaches the key and the rows are moved and removed instead.
     */
    readonly property var availableWidgets: [
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
     * before any widget exists, and it still answers for a widget that has
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
