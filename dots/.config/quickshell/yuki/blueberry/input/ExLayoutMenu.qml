import QtQuick

import qs.core.services
import qs.blueberry.looks

// The keyboard layouts to switch between, opened from the language on the
// dock. The one in use is ticked.
ExPopup {
    id: root

    required property ExLayouts layouts

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    Column {
        width: 220

        Repeater {
            model: root.layouts.codes

            ExMenuItem {
                required property string modelData
                required property int index

                text: root.layouts.name(modelData)
                glyph: index === root.layouts.current ? "check" : ""
                shortcut: root.layouts.fullCode(index)
                onClicked: {
                    root.open = false;
                    root.layouts.select(index);
                }
            }
        }
    }
}
