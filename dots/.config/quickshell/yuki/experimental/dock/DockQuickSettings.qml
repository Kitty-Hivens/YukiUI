import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower

import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.input
import qs.experimental.looks

// Quick settings, opened from the status block: the switches worth reaching
// without opening anything, in pages, sound and brightness, and the battery.
ExPopup {
    id: root

    readonly property var brightness: Brightness.getMonitorForScreen(root.dockWindow.screen)

    function runTile(key: string) {
        // A tile that acts on the screen has quick settings out of the way first.
        if (ExQuickTiles.info(key).closes)
            root.open = false;
        ExQuickTiles.run(key);
    }

    /** Arranging the tiles: unpinning, adding, and dragging them into order. */
    property bool editing: false
    /** Adding a tile: the list of those not pinned is open. */
    property bool adding: false

    function startEditing() {
        editor.keys = ExQuickTiles.pinned.slice();
        editor.order = ExQuickTiles.pinned.slice();
        root.adding = false;
        root.editing = true;
    }
    function stopEditing() {
        root.editing = false;
        root.adding = false;
    }

    /**
     * The page behind a tile's arrow, "wifi" or "bluetooth", or behind the
     * volume's, "sound", or empty for the switches. It slides in over the switches and keeps their size, so the
     * window does not change shape under the pointer.
     */
    property string page: ""
    /** The page still drawn while it slides away. */
    property string drawnPage: ""
    /** From the switches (0) to a page (1). */
    property real shift: root.page.length > 0 ? 1 : 0
    Behavior on shift {
        enabled: root.visible
        NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
    }
    onShiftChanged: {
        if (root.shift === 0)
            root.drawnPage = "";
    }

    function openPage(key: string) {
        root.drawnPage = key;
        root.page = key;
        root.leftPage = "";
    }

    /** The page last gone back from, for the mouse's forward button. */
    property string leftPage: ""

    function goBack() {
        if (root.page.length === 0)
            return;
        root.leftPage = root.page;
        root.page = "";
    }

    function openSettings(key: string) {
        root.open = false;
        Surfaces.open("settings", key);
    }

    // Opened again, it opens on the switches.
    onVisibleChanged: {
        if (!root.visible) {
            root.page = "";
            root.drawnPage = "";
            root.leftPage = "";
            root.stopEditing();
        }
    }

    /**
     * A password field being typed into, which the dock takes the keyboard for
     * and hands the keys to. Null when there is none.
     */
    readonly property Item keyTarget: root.open && root.page === "wifi" ? wifiPage.keyTarget : null

    padding: ExLooks.spacing.l

    motion: "panel"
    onDismissRequested: root.open = false

    Item {
        width: 400
        height: column.implicitHeight
        clip: root.shift > 0 && root.shift < 1

        ExNavigationButtons {
            z: 1
            onBack: root.goBack()
            onForward: {
                if (root.page.length === 0 && root.leftPage.length > 0)
                    root.openPage(root.leftPage);
            }
        }

        DockWifiPage {
            id: wifiPage
            width: parent.width
            height: parent.height
            x: (1 - root.shift) * 48
            opacity: root.shift
            visible: root.drawnPage === "wifi"
            shown: root.page === "wifi" && root.open
            onBack: root.goBack()
            onSettingsRequested: root.openSettings("wifi")
        }
        DockBluetoothPage {
            width: parent.width
            height: parent.height
            x: (1 - root.shift) * 48
            opacity: root.shift
            visible: root.drawnPage === "bluetooth"
            shown: root.page === "bluetooth" && root.open
            onBack: root.goBack()
            onSettingsRequested: root.openSettings("bluetooth")
        }
        DockSoundPage {
            width: parent.width
            height: parent.height
            x: (1 - root.shift) * 48
            opacity: root.shift
            visible: root.drawnPage === "sound"
            shown: root.page === "sound" && root.open
            onBack: root.goBack()
            onSettingsRequested: root.openSettings("sound")
        }

        ColumnLayout {
            id: column

            width: 400
            x: -root.shift * 48
            opacity: 1 - root.shift
            visible: root.shift < 1
            spacing: ExLooks.spacing.s

            // What is playing, over the switches, as on Windows 11. Out of the
            // way while the tiles are arranged.
            DockMediaCard {
                Layout.fillWidth: true
                Layout.bottomMargin: ExLooks.spacing.xs
                active: root.open
                visible: shown && !root.editing
            }

            // Three rows of switches at most, and pages beyond that, turned by
            // dragging, by scrolling or with the dots under them.
            ListView {
                id: pager

                readonly property int perPage: 6
                readonly property real tileRows: 3

                Layout.fillWidth: true
                Layout.preferredHeight: pager.tileRows * ExLooks.sizes.tileHeight + (pager.tileRows - 1) * ExLooks.spacing.s
                visible: !root.editing
                orientation: ListView.Horizontal
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: ExLooks.motion.normal
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                model: Math.ceil(ExQuickTiles.pinned.length / pager.perPage)

                // Scrolling up or down turns the page too, since a mouse has no
                // sideways wheel. Taken above the pages, since the list takes a
                // wheel for its own sideways scrolling and snaps straight back.
                // What a touchpad sends in small steps is added up to one notch,
                // and a page turns at most every quarter second, so one stroke
                // turns one page. Clicks and drags pass through.
                MouseArea {
                    property real scrolled: 0

                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        event.accepted = true;
                        if (turnPause.running)
                            return;
                        scrolled += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                        if (Math.abs(scrolled) < 120)
                            return;
                        if (scrolled < 0)
                            pager.incrementCurrentIndex();
                        else
                            pager.decrementCurrentIndex();
                        scrolled = 0;
                        turnPause.restart();
                    }

                    Timer {
                        id: turnPause
                        interval: 250
                    }
                }

                delegate: GridLayout {
                    id: page

                    required property int index

                    width: pager.width
                    height: pager.height
                    columns: 2
                    columnSpacing: ExLooks.spacing.s
                    rowSpacing: ExLooks.spacing.s

                    Repeater {
                        model: ExQuickTiles.pinned.slice(page.index * pager.perPage, (page.index + 1) * pager.perPage)

                        // State comes from the system, so a click asks for the
                        // change and the tile follows what actually happened.
                        ExToggleTile {
                            required property string modelData
                            readonly property var info: ExQuickTiles.info(modelData)

                            // Half the page each, even alone in its row.
                            Layout.preferredWidth: (page.width - page.columnSpacing) / 2
                            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                            checkable: false
                            glyph: info.glyph
                            text: info.text
                            subtitle: info.subtitle
                            checked: info.checked
                            hasMenu: info.hasPage ?? false
                            onClicked: root.runTile(modelData)
                            onMenuRequested: root.openPage(modelData)
                        }
                    }
                }
            }

            // The pinned tiles laid out for arranging, all of them at once
            // rather than in pages. Placed by hand rather than by a layout: a
            // tile dragged to another place moves there as it goes, and a
            // layout fed a new order made every tile anew, the dragged one
            // and its drag with it.
            Item {
                id: editor

                /** The tiles arranged, made once as editing starts. */
                property var keys: []
                /** Where each stands now, as the drag goes. */
                property var order: []
                property string dragged: ""

                readonly property real gap: ExLooks.spacing.s
                readonly property real cellWidth: (width - gap) / 2
                readonly property real cellHeight: ExLooks.sizes.tileHeight
                readonly property int rows: Math.ceil(editor.order.length / 2)

                function slotX(index: int): real {
                    return (index % 2) * (editor.cellWidth + editor.gap);
                }
                function slotY(index: int): real {
                    return Math.floor(index / 2) * (editor.cellHeight + editor.gap);
                }
                /** The place under a point, within the tiles there are. */
                function slotAt(x: real, y: real): int {
                    const column = x < editor.cellWidth + editor.gap / 2 ? 0 : 1;
                    const row = Math.max(0, Math.min(editor.rows - 1, Math.floor((y + editor.gap / 2) / (editor.cellHeight + editor.gap))));
                    return Math.min(editor.order.length - 1, row * 2 + column);
                }
                function moveTo(key: string, index: int) {
                    const next = editor.order.filter(other => other !== key);
                    next.splice(index, 0, key);
                    editor.order = next;
                }
                function remove(key: string) {
                    editor.order = editor.order.filter(other => other !== key);
                    editor.keys = editor.keys.filter(other => other !== key);
                    ExQuickTiles.unpin(key);
                }
                function add(key: string) {
                    editor.keys = [...editor.keys, key];
                    editor.order = [...editor.order, key];
                    ExQuickTiles.pin(key);
                }

                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(editor.cellHeight, editor.rows * (editor.cellHeight + editor.gap) - editor.gap)
                visible: root.editing

                Repeater {
                    model: editor.keys

                    Item {
                        id: slot

                        required property string modelData
                        readonly property int at: editor.order.indexOf(slot.modelData)
                        readonly property bool lifted: editor.dragged === slot.modelData
                        readonly property var info: ExQuickTiles.info(slot.modelData)
                        property point held: Qt.point(0, 0)
                        property point pointer: Qt.point(0, 0)

                        visible: slot.at >= 0
                        width: editor.cellWidth
                        height: editor.cellHeight
                        x: slot.lifted ? slot.pointer.x - slot.held.x : editor.slotX(slot.at)
                        y: slot.lifted ? slot.pointer.y - slot.held.y : editor.slotY(slot.at)
                        z: slot.lifted ? 2 : 1
                        scale: slot.lifted ? 1.04 : 1

                        Behavior on x {
                            enabled: !slot.lifted
                            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                        }
                        Behavior on y {
                            enabled: !slot.lifted
                            NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: ExLooks.motion.fast }
                        }

                        // Shown as it is, and taking no clicks: here a press
                        // starts a drag.
                        ExToggleTile {
                            anchors.fill: parent
                            enabled: false
                            checkable: false
                            glyph: slot.info.glyph
                            text: slot.info.text
                            subtitle: slot.info.subtitle
                            checked: slot.info.checked
                        }

                        DragHandler {
                            id: drag

                            target: null
                            acceptedButtons: Qt.LeftButton
                            onActiveChanged: {
                                if (drag.active) {
                                    slot.held = drag.centroid.pressPosition;
                                    slot.pointer = editor.mapFromItem(null, drag.centroid.scenePosition.x, drag.centroid.scenePosition.y);
                                    editor.dragged = slot.modelData;
                                } else {
                                    editor.dragged = "";
                                    ExQuickTiles.setPinned(editor.order);
                                }
                            }
                            onCentroidChanged: {
                                if (!drag.active)
                                    return;
                                slot.pointer = editor.mapFromItem(null, drag.centroid.scenePosition.x, drag.centroid.scenePosition.y);
                                const target = editor.slotAt(slot.pointer.x, slot.pointer.y);
                                if (target !== slot.at)
                                    editor.moveTo(slot.modelData, target);
                            }
                        }

                        // Unpins the tile, as the pin badge does on Windows.
                        AbstractButton {
                            id: unpin

                            ExPrimaryOnly {
                                z: 1
                            }

                            visible: !slot.lifted
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: -6
                            width: 24
                            height: 24
                            hoverEnabled: true
                            onClicked: editor.remove(slot.modelData)

                            background: Rectangle {
                                radius: 12
                                color: ExLooks.colors.surface
                                border.width: 1
                                border.color: ExLooks.colors.border

                                ExStateLayer {
                                    radius: 12
                                    ink: ExLooks.colors.text
                                    hovered: unpin.hovered
                                    pressed: unpin.down
                                }
                            }
                            contentItem: Item {
                                ExGlyph {
                                    anchors.centerIn: parent
                                    text: "keep_off"
                                    size: 14
                                    color: ExLooks.colors.text
                                }
                            }
                        }
                    }
                }
            }

            // The tiles that could be added, opened from the button below.
            ExMenu {
                Layout.fillWidth: true
                visible: root.editing && root.adding
                elevation: 0
                color: ExLooks.colors.surfaceSunken

                Repeater {
                    model: ExQuickTiles.unpinned

                    ExMenuItem {
                        required property string modelData
                        readonly property var info: ExQuickTiles.info(modelData)

                        glyph: info.glyph
                        text: info.text
                        onClicked: {
                            editor.add(modelData);
                            if (ExQuickTiles.unpinned.length === 0)
                                root.adding = false;
                        }
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                visible: pager.count > 1 && !root.editing
                spacing: ExLooks.spacing.xs

                Repeater {
                    model: pager.count

                    AbstractButton {
                        id: dot

                        ExPrimaryOnly {
                            z: 1
                        }

                        required property int index
                        readonly property bool current: dot.index === pager.currentIndex

                        implicitWidth: 18
                        implicitHeight: 18
                        hoverEnabled: true
                        onClicked: pager.currentIndex = dot.index

                        contentItem: Item {
                            Rectangle {
                                anchors.centerIn: parent
                                width: dot.current ? 16 : 6
                                height: 6
                                radius: 3
                                color: dot.current ? ExLooks.colors.accent : ExLooks.colors.textDim
                                opacity: dot.current || dot.hovered ? 1 : 0.5

                                Behavior on width {
                                    NumberAnimation { duration: ExLooks.motion.fast }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.s

                ExButton {
                    kind: "flat"
                    onClicked: {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }

                    ExStatusGlyph {
                        anchors.centerIn: parent
                        name: ExStatusGlyphs.volumeGlyph
                        color: ExLooks.colors.accent
                        size: 18
                    }
                }
                ExSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: Audio.sink?.audio?.volume ?? 0
                    onMoved: Audio.setDeviceVolume(Audio.sink, value)
                }
                // The device and each application, as the arrow at the end
                // of the Windows 11 volume opens them.
                ExButton {
                    kind: "flat"
                    glyph: "chevron_right"
                    onClicked: root.openPage("sound")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.brightness !== null && root.brightness !== undefined
                spacing: ExLooks.spacing.s

                Item {
                    implicitWidth: ExLooks.sizes.control
                    implicitHeight: ExLooks.sizes.control

                    ExGlyph {
                        anchors.centerIn: parent
                        text: "brightness_6"
                        size: 18
                    }
                }
                ExSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: root.brightness?.brightness ?? 0
                    onMoved: root.brightness?.setBrightness(value)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.s
                spacing: ExLooks.spacing.s

                ExStatusGlyph {
                    visible: Battery.available
                    name: ExStatusGlyphs.batteryGlyph
                    color: Battery.isLowAndNotCharging ? ExLooks.colors.destructive : ExLooks.colors.text
                    size: 18
                }
                ExText {
                    Layout.fillWidth: true
                    text: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : ""
                    role: "label"
                }
                ExButton {
                    visible: !root.editing
                    kind: "control"
                    glyph: "edit"
                    onClicked: root.startEditing()
                }
                ExButton {
                    visible: !root.editing
                    kind: "control"
                    glyph: "settings"
                    onClicked: {
                        root.open = false;
                        Surfaces.open("settings", "");
                    }
                }
                ExButton {
                    visible: !root.editing
                    kind: "control"
                    glyph: "power_settings_new"
                    onClicked: {
                        root.open = false;
                        ExStates.sessionOpen = true;
                    }
                }
                ExButton {
                    visible: root.editing
                    enabled: ExQuickTiles.unpinned.length > 0
                    kind: root.adding ? "tonal" : "control"
                    glyph: "add"
                    text: Translation.tr("Add")
                    onClicked: root.adding = !root.adding
                }
                ExButton {
                    visible: root.editing
                    kind: "accent"
                    text: Translation.tr("Done")
                    onClicked: root.stopEditing()
                }
            }
        }
    }
}
