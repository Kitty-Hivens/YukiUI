import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs.blueberry.looks

// One tray icon. A left click does what the application asks of it, or opens
// its menu when the menu is all it has, the middle button its second action,
// and a right click its menu. Pulled with the left button, it is carried.
Item {
    id: root

    /** Null for the moment between the icon leaving the tray and this going. */
    required property SystemTrayItem item
    /**
     * Where a carried icon stands: "" for none being carried, "carried" for
     * the one picked up, still where it was taken from, "gap" for where it
     * would land, held open for it.
     */
    property string carryState: ""

    signal menuRequested(Item button)
    signal carryStarted
    signal carryFinished(bool dropped)

    implicitWidth: 32
    implicitHeight: 32
    opacity: root.carryState === "gap" ? 0 : root.carryState === "carried" ? 0.35 : 1

    // Carried as a drag-and-drop, the one grab Wayland gives a client that
    // follows the pointer from the dock into the popup the chevron opens and
    // back.
    Item {
        id: carrier

        anchors.fill: parent
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction
        Drag.mimeData: ({ "application/x-yuki-tray": root.item?.id ?? "" })
        Drag.imageSource: root.item?.icon ?? ""
        Drag.imageSourceSize: Qt.size(24, 24)
        Drag.hotSpot.x: 12
        Drag.hotSpot.y: 12
        Drag.onDragFinished: dropAction => {
            carrier.Drag.active = false;
            root.carryFinished(dropAction === Qt.MoveAction);
        }
    }

    MouseArea {
        id: mouse

        property point pressedAt
        property bool carrying: false

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onPressed: event => {
            mouse.pressedAt = Qt.point(event.x, event.y);
            mouse.carrying = false;
        }
        onPositionChanged: event => {
            if (mouse.carrying || !(mouse.pressedButtons & Qt.LeftButton))
                return;
            if (Math.hypot(event.x - mouse.pressedAt.x, event.y - mouse.pressedAt.y) < 6)
                return;
            mouse.carrying = true;
            root.carryStarted();
            carrier.Drag.active = true;
        }
        onClicked: event => {
            if (mouse.carrying || !root.item)
                return;
            if (event.button === Qt.RightButton) {
                if (root.item.hasMenu)
                    root.menuRequested(root);
            } else if (event.button === Qt.MiddleButton) {
                root.item.secondaryActivate();
            } else if (root.item.onlyMenu && root.item.hasMenu) {
                root.menuRequested(root);
            } else {
                root.item.activate();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: ExLooks.radius.control
        color: "transparent"

        ExStateLayer {
            ink: ExLooks.colors.text
            hovered: mouse.containsMouse
            pressed: mouse.pressed
        }
    }

    /**
     * A symbolic icon of the icon theme, which whatever shows it is to draw in
     * its own text colour. As it comes it is light, made for a dark panel, and
     * on a light dock it could not be seen.
     */
    readonly property bool symbolic: /^image:\/\/icon\/[^?]*-symbolic(\?|$)/.test(root.item?.icon ?? "")

    IconImage {
        id: icon

        anchors.centerIn: parent
        implicitSize: 18
        source: root.item?.icon ?? ""
        visible: !root.symbolic
        // An icon of the icon theme is coloured by the palette as it is drawn,
        // so one kept from before the palette changed keeps the other mode's
        // colours.
        Component.onCompleted: icon.backer.cache = false
    }

    // Drawn anew when the system palette changes, with the light or dark mode.
    SystemPalette {
        id: systemPalette
    }
    Connections {
        target: systemPalette

        function onPaletteChanged() {
            icon.source = "";
            icon.source = Qt.binding(() => root.item?.icon ?? "");
        }
    }

    Loader {
        anchors.fill: icon
        active: root.symbolic

        sourceComponent: ColorOverlay {
            source: icon
            color: ExLooks.colors.text
        }
    }

    // An application asking to be looked at, a chat with unread messages say.
    Rectangle {
        visible: root.item?.status === Status.NeedsAttention
        x: root.width - width - 5
        y: 5
        width: 8
        height: 8
        radius: 4
        color: ExLooks.colors.accent
        border.width: 1.5
        border.color: ExLooks.colors.surface
    }
}
