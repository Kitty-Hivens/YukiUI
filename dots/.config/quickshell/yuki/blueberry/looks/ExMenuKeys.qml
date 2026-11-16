import QtQuick

/**
 * The keys of a menu, given to whatever holds the keyboard for it: the dock,
 * for the menus that come out of it.
 *
 * Up and Down go from entry to entry, past separators and entries that cannot
 * be chosen, and round from one end to the other; Home and End go to the ends.
 * Enter and Space choose, Escape closes. Right goes into a submenu and Left
 * back out of one, for menus whose submenus open in their place. A letter goes
 * to the next entry starting with it.
 *
 * The entry the keys are on and the one under the pointer are one: the pointer
 * moves it too, so the menu never shows two. Opened with the mouse, none is
 * picked until a key is pressed.
 */
Item {
    id: root

    /** What the entries are found in. */
    required property Item menu
    /** The entry picked, or null. */
    property Item current: null
    /** Takes a submenu opened in place back to the menu it belongs to. Empty for a menu without one. */
    property var back: null

    signal closeRequested

    focus: true

    /**
     * The entries that can be chosen, top to bottom. Each found is handed
     * this navigator, so it lights up as picked and picks itself under the
     * pointer, the entries of a submenu made a moment ago among them.
     */
    function entries(): var {
        const found = [];
        const walk = item => {
            for (const child of item?.children ?? []) {
                if (!child.visible)
                    continue;
                if (child.navigator !== undefined && child.hasSubmenu !== undefined) {
                    child.navigator = root;
                    if (child.enabled)
                        found.push(child);
                    continue;
                }
                walk(child);
            }
        };
        walk(root.menu);
        return found.sort((a, b) => a.mapToItem(root.menu, 0, 0).y - b.mapToItem(root.menu, 0, 0).y);
    }

    function step(by: int) {
        const list = root.entries();
        if (list.length === 0)
            return;
        const at = list.indexOf(root.current);
        if (at < 0)
            root.current = by > 0 ? list[0] : list[list.length - 1];
        else
            root.current = list[(at + by + list.length) % list.length];
    }

    function pickFirst() {
        const list = root.entries();
        root.current = list.length > 0 ? list[0] : null;
    }

    // Entering a submenu from the keys picks its first entry once it is drawn.
    property bool pickAfterChange: false

    function choose() {
        if (!root.current)
            return;
        root.pickAfterChange = root.current.hasSubmenu;
        root.current.click();
        if (root.pickAfterChange)
            Qt.callLater(() => {
                root.pickFirst();
                root.pickAfterChange = false;
            });
    }

    function goBack() {
        if (typeof root.back !== "function")
            return false;
        root.back();
        Qt.callLater(root.pickFirst);
        return true;
    }

    function jump(letter: string) {
        const list = root.entries();
        if (list.length === 0)
            return;
        const start = list.indexOf(root.current);
        for (let i = 1; i <= list.length; i++) {
            const entry = list[(start + i + list.length) % list.length];
            if ((entry.text ?? "").toLowerCase().startsWith(letter)) {
                root.current = entry;
                return;
            }
        }
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down:
            root.step(1);
            break;
        case Qt.Key_Up:
            root.step(-1);
            break;
        case Qt.Key_Home:
            root.pickFirst();
            break;
        case Qt.Key_End:
            root.current = root.entries().slice(-1)[0] ?? null;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.choose();
            break;
        case Qt.Key_Right:
            if (root.current?.hasSubmenu)
                root.choose();
            break;
        case Qt.Key_Left:
            if (!root.goBack()) {
                event.accepted = false;
                return;
            }
            break;
        case Qt.Key_Escape:
            root.closeRequested();
            break;
        default:
            if (event.text.length === 1 && /\S/.test(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                root.jump(event.text.toLowerCase());
                break;
            }
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }
}
