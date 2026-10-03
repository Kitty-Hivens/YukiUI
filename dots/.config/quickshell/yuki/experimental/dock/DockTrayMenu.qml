import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

import qs.experimental.looks

// A tray icon's menu, as the application describes it over DBusMenu. A submenu
// opens in place of the menu it belongs to, with a way back at the top, the
// way GNOME's menus go deeper, rather than as a cascade of windows.
ExPopup {
    id: root

    property var trayItem: null
    /**
     * The submenus gone into, innermost last. Empty at the top. A plain var:
     * a list<var> held the entries as bare pointers, and one whose program
     * had quit was read through anyway on the way back.
     */
    property var trail: []
    // The program gone, its menu goes with it. Opened from the arrow, the
    // menu belongs to no icon that would go away and take it along.
    readonly property bool itemGone: root.trayItem !== null && !SystemTray.items.values.includes(root.trayItem)
    onItemGoneChanged: {
        if (root.itemGone && root.open)
            root.open = false;
    }
    readonly property var current: root.trail.length > 0 ? root.trail[root.trail.length - 1] : (root.trayItem?.menu ?? null)

    function openFor(item, button: Item) {
        if (root.open && root.trayItem === item) {
            root.open = false;
            return;
        }
        root.trail = [];
        root.trayItem = item;
        root.opener = button;
        root.anchor.updateAnchor();
        root.open = true;
    }

    // Menus mark a mnemonic with an underscore and a literal one with two.
    function label(text: string): string {
        return (text ?? "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
    }

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    QsMenuOpener {
        id: entries
        menu: root.current
    }

    Column {
        width: ExLooks.sizes.menuWidth

        ExMenuItem {
            visible: root.trail.length > 0
            glyph: "arrow_back"
            text: root.label(root.trail[root.trail.length - 1]?.text ?? "")
            onClicked: root.trail = root.trail.slice(0, -1)
        }
        ExMenuSeparator {
            visible: root.trail.length > 0
        }

        Repeater {
            model: entries.children

            Loader {
                id: slot

                required property var modelData

                width: parent.width
                sourceComponent: slot.modelData.isSeparator ? separator : entry

                Component {
                    id: separator
                    ExMenuSeparator {}
                }

                Component {
                    id: entry
                    ExMenuItem {
                        readonly property var source: slot.modelData
                        readonly property bool checkBox: source.buttonType === QsMenuButtonType.CheckBox
                        readonly property bool radio: source.buttonType === QsMenuButtonType.RadioButton
                        readonly property bool marked: source.checkState === Qt.Checked

                        text: root.label(source.text)
                        enabled: source.enabled
                        hasSubmenu: source.hasChildren
                        glyph: checkBox ? (marked ? "check_box" : "check_box_outline_blank")
                            : radio ? (marked ? "radio_button_checked" : "radio_button_unchecked")
                            : ""
                        iconSource: checkBox || radio ? "" : source.icon
                        onClicked: {
                            if (source.hasChildren) {
                                root.trail = [...root.trail, source];
                                return;
                            }
                            source.triggered();
                            root.open = false;
                        }
                    }
                }
            }
        }
    }
}
