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

    /** Arranging the tiles: which are shown, and in what order. */
    property bool editing: false
    /** From using the switches (0) to arranging them (1). */
    property real editShift: root.editing ? 1 : 0
    Behavior on editShift {
        enabled: root.visible
        NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
    }

    function startEditing() {
        editor.settled = false;
        editor.order = ExQuickTiles.pinned.slice();
        editor.keys = [...ExQuickTiles.pinned, ...ExQuickTiles.unpinned];
        root.editing = true;
        editorSettle.restart();
    }
    // The tiles take their places without travelling until the editor is in:
    // laid out while it was still coming in, they flew in from where its
    // first, narrower layout had put them.
    Timer {
        id: editorSettle
        interval: ExLooks.motion.normal + 40
        onTriggered: editor.settled = true
    }
    function stopEditing() {
        root.editing = false;
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
        height: root.page === "sound" ? soundPage.implicitHeight : column.implicitHeight
        clip: root.shift > 0 && root.shift < 1
        // In step with the slide, so the switches leave a panel still their
        // size rather than one already the sound page's. Only then: what
        // grows on the switches, the tile editor say, grows smoothly itself,
        // and followed a second time the panel lagged behind it and what was
        // at its foot showed below its edge.
        Behavior on height {
            enabled: root.visible && root.drawnPage === "sound"
            NumberAnimation {
                duration: ExLooks.motion.normal
                easing.type: Easing.BezierSpline
                easing.bezierCurve: ExLooks.motion.standard
            }
        }

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
            id: soundPage

            width: parent.width
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

            // Using the switches or arranging them, one going into the other:
            // the height moves between theirs as one fades into the other.
            // Swapped in one frame, the panel jumped from the one height to the
            // other, both ways.
            Item {
                id: tilesArea

                Layout.fillWidth: true
                Layout.preferredHeight: usingView.implicitHeight + (editView.implicitHeight - usingView.implicitHeight) * root.editShift
                clip: root.editShift > 0 && root.editShift < 1

                ColumnLayout {
                    id: usingView

                    width: parent.width
                    spacing: ExLooks.spacing.s
                    // Gone in the first half, the editor coming in the second:
                    // through each other the two made a muddle of tiles.
                    opacity: Math.max(0, 1 - 2 * root.editShift)
                    // Kept to the end, transparent: its height is half of what the
                    // area's height moves between.
                    visible: root.editShift < 1
                    transform: Translate {
                        y: -root.editShift * 16
                    }

                    // What is playing, over the switches, as on Windows 11. Out of the
                    // way while the tiles are arranged.
                    DockMediaCard {
                        Layout.fillWidth: true
                        Layout.bottomMargin: ExLooks.spacing.xs
                        active: root.open
                        visible: shown
                    }

                    // Three rows of switches at most, and pages beyond that, turned by
                    // dragging, by scrolling or with the dots under them.
                    ListView {
                        id: pager

                        readonly property int perPage: 6
                        readonly property real tileRows: 3

                        Layout.fillWidth: true
                        Layout.preferredHeight: pager.tileRows * ExLooks.sizes.tileHeight + (pager.tileRows - 1) * ExLooks.spacing.s
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

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        visible: pager.count > 1
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
                }

                ColumnLayout {
                    id: editView

                    width: parent.width
                    spacing: ExLooks.spacing.s
                    opacity: Math.max(0, 2 * root.editShift - 1)
                    visible: root.editShift > 0
                    transform: Translate {
                        y: (1 - root.editShift) * 16
                    }

                    ExText {
                        Layout.fillWidth: true
                        text: Translation.tr("Drag to reorder")
                        role: "caption"
                        dim: true
                    }

                    // The tiles laid out for arranging: those shown, in their order
                    // and dragged into another, and under them the rest, each moved
                    // across by its own button or dragged across. One set of tiles placed by hand
                    // rather than two layouts, so a tile moved from one part to the
                    // other travels there rather than vanishing from one and turning
                    // up in the other, and a dragged tile moves as it goes. Drawn
                    // plain whatever their state, since arranging is about where a
                    // tile goes and not about whether it is on: coloured by state,
                    // the editor looked like quick settings with badges on it.
                    Item {
                        id: editor

                        /** Every tile, made once as editing starts. */
                        property var keys: []
                        /** The tiles shown, in their order, as the drag goes. */
                        property var order: []
                        readonly property var spare: editor.keys.filter(key => !editor.order.includes(key))
                        property string dragged: ""
                        /** In place: from here on a tile moved travels to its new place. */
                        property bool settled: false

                        readonly property real gap: ExLooks.spacing.s
                        readonly property real cellWidth: (width - gap) / 2
                        readonly property real cellHeight: ExLooks.sizes.tileHeight
                        readonly property int rows: Math.max(1, Math.ceil(editor.order.length / 2))
                        readonly property real shownHeight: editor.rows * (editor.cellHeight + editor.gap) - editor.gap
                        /** Where the rest start, under a caption naming them. */
                        readonly property real spareTop: editor.shownHeight + ExLooks.spacing.l + spareCaption.implicitHeight + ExLooks.spacing.s
                        readonly property int spareRows: Math.ceil(editor.spare.length / 2)

                        function slotX(index: int): real {
                            return (index % 2) * (editor.cellWidth + editor.gap);
                        }
                        function slotY(index: int): real {
                            return Math.floor(index / 2) * (editor.cellHeight + editor.gap);
                        }
                        /** Where a tile goes: among those shown, or among the rest. */
                        function home(key: string): point {
                            const at = editor.order.indexOf(key);
                            if (at >= 0)
                                return Qt.point(editor.slotX(at), editor.slotY(at));
                            const rest = editor.spare.indexOf(key);
                            return Qt.point(editor.slotX(rest), editor.spareTop + editor.slotY(rest));
                        }
                        /** The place among those shown under a point. */
                        function slotAt(x: real, y: real): int {
                            const column = x < editor.cellWidth + editor.gap / 2 ? 0 : 1;
                            const row = Math.max(0, Math.min(editor.rows - 1, Math.floor((y + editor.gap / 2) / (editor.cellHeight + editor.gap))));
                            return Math.min(editor.order.length - 1, row * 2 + column);
                        }
                        /** The place a tile brought in from the rest takes under a point, one past the end included. */
                        function joinAt(x: real, y: real): int {
                            const column = x < editor.cellWidth + editor.gap / 2 ? 0 : 1;
                            const row = Math.max(0, Math.floor((y + editor.gap / 2) / (editor.cellHeight + editor.gap)));
                            return Math.min(editor.order.length, row * 2 + column);
                        }
                        function moveTo(key: string, index: int) {
                            const next = editor.order.filter(other => other !== key);
                            next.splice(index, 0, key);
                            editor.order = next;
                        }
                        function remove(key: string) {
                            editor.order = editor.order.filter(other => other !== key);
                            ExQuickTiles.unpin(key);
                        }
                        function add(key: string) {
                            editor.order = [...editor.order, key];
                            ExQuickTiles.pin(key);
                        }

                        // As tall as the two parts can ever take, for as long as the
                        // tiles are arranged. The panel stands on the dock and grows
                        // upwards, so a row opened or closed by a tile moved across
                        // moved every tile under the pointer, the one being dragged
                        // towards among them.
                        readonly property int mostRows: Math.floor(editor.keys.length / 2) + 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: editor.mostRows * (editor.cellHeight + editor.gap) - editor.gap
                            + ExLooks.spacing.l + spareCaption.implicitHeight + ExLooks.spacing.s

                        ExText {
                            id: spareCaption

                            y: editor.shownHeight + ExLooks.spacing.l
                            width: parent.width
                            opacity: editor.spare.length > 0 ? 1 : 0
                            text: Translation.tr("More tiles")
                            role: "caption"
                            dim: true

                            Behavior on y {
                                enabled: editor.settled
                                NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: ExLooks.motion.fast }
                            }
                        }

                        Repeater {
                            model: editor.keys

                            Item {
                                id: slot

                                required property string modelData
                                readonly property bool shown: editor.order.includes(slot.modelData)
                                readonly property bool lifted: editor.dragged === slot.modelData
                                readonly property var info: ExQuickTiles.info(slot.modelData)
                                readonly property point home: editor.home(slot.modelData)
                                property point held: Qt.point(0, 0)
                                property point pointer: Qt.point(0, 0)

                                width: editor.cellWidth
                                height: editor.cellHeight
                                x: slot.lifted ? slot.pointer.x - slot.held.x : slot.home.x
                                y: slot.lifted ? slot.pointer.y - slot.held.y : slot.home.y
                                z: slot.lifted ? 2 : 1
                                scale: slot.lifted ? 1.04 : 1

                                Behavior on x {
                                    enabled: !slot.lifted && editor.settled
                                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                                }
                                Behavior on y {
                                    enabled: !slot.lifted && editor.settled
                                    NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: ExLooks.motion.fast }
                                }

                                // A shown tile on a plate, one of the rest only outlined.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: ExLooks.radius.tile
                                    color: slot.shown ? ExLooks.colors.control : "transparent"
                                    border.width: slot.shown ? 0 : 1
                                    border.color: ExLooks.colors.border

                                    Behavior on color {
                                        ColorAnimation { duration: ExLooks.motion.normal }
                                    }

                                    ExStateLayer {
                                        ink: ExLooks.colors.text
                                        hovered: grab.hovered
                                        pressed: slot.lifted
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: ExLooks.spacing.m + 2
                                    anchors.rightMargin: ExLooks.spacing.s
                                    spacing: ExLooks.spacing.m

                                    ExGlyph {
                                        text: slot.info.glyph
                                        color: ExLooks.colors.text
                                    }
                                    ExText {
                                        Layout.fillWidth: true
                                        text: slot.info.text
                                        role: "label"
                                        elide: Text.ElideRight
                                    }
                                    // Takes the tile out of quick settings, or puts it in.
                                    AbstractButton {
                                        id: toggle

                                        ExPrimaryOnly {
                                            z: 1
                                        }

                                        implicitWidth: 28
                                        implicitHeight: 28
                                        hoverEnabled: true
                                        onClicked: {
                                            if (slot.shown)
                                                editor.remove(slot.modelData);
                                            else
                                                editor.add(slot.modelData);
                                        }

                                        background: Rectangle {
                                            radius: 14
                                            color: slot.shown ? ExLooks.colors.surface : ExLooks.colors.accent

                                            ExStateLayer {
                                                radius: 14
                                                ink: slot.shown ? ExLooks.colors.text : ExLooks.colors.accentInk
                                                hovered: toggle.hovered
                                                pressed: toggle.down
                                            }
                                        }
                                        contentItem: Item {
                                            ExGlyph {
                                                anchors.centerIn: parent
                                                text: slot.shown ? "remove" : "add"
                                                size: 18
                                                color: slot.shown ? ExLooks.colors.text : ExLooks.colors.accentInk
                                            }
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: grab
                                    cursorShape: slot.lifted ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                }

                                // Dragged within those shown it is put in order, and
                                // dragged between the two parts it is put in or taken
                                // out where it is dropped. The line it crosses lies a
                                // little lower going out than coming in: a tile that
                                // opens or closes a row of those shown moves that
                                // line, and on one line it went in and out again
                                // under a still pointer.
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
                                        const middle = slot.pointer.y - slot.held.y + editor.cellHeight / 2;
                                        if (slot.shown && middle > editor.shownHeight + ExLooks.spacing.l) {
                                            editor.order = editor.order.filter(other => other !== slot.modelData);
                                            return;
                                        }
                                        if (!slot.shown) {
                                            if (middle < editor.shownHeight + ExLooks.spacing.l / 2) {
                                                const next = editor.order.slice();
                                                next.splice(editor.joinAt(slot.pointer.x, slot.pointer.y), 0, slot.modelData);
                                                editor.order = next;
                                            }
                                            return;
                                        }
                                        const target = editor.slotAt(slot.pointer.x, slot.pointer.y);
                                        if (target !== editor.order.indexOf(slot.modelData))
                                            editor.moveTo(slot.modelData, target);
                                    }
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
                // The buttons of using quick settings and the one of
                // arranging it, fading into each other in one place.
                Item {
                    implicitWidth: Math.max(usingButtons.implicitWidth, done.implicitWidth)
                    implicitHeight: Math.max(usingButtons.implicitHeight, done.implicitHeight)

                    Row {
                        id: usingButtons

                        anchors.right: parent.right
                        spacing: ExLooks.spacing.s
                        opacity: Math.max(0, 1 - 2 * root.editShift)
                        visible: root.editShift < 0.5

                        ExButton {
                            kind: "control"
                            glyph: "edit"
                            onClicked: root.startEditing()
                        }
                        ExButton {
                            kind: "control"
                            glyph: "settings"
                            onClicked: {
                                root.open = false;
                                Surfaces.open("settings", "");
                            }
                        }
                        ExButton {
                            kind: "control"
                            glyph: "power_settings_new"
                            onClicked: {
                                root.open = false;
                                ExStates.sessionOpen = true;
                            }
                        }
                    }
                    ExButton {
                        id: done

                        anchors.right: parent.right
                        opacity: Math.max(0, 2 * root.editShift - 1)
                        visible: root.editShift > 0.5
                        kind: "accent"
                        text: Translation.tr("Done")
                        onClicked: root.stopEditing()
                    }
                }
            }
        }
    }
}
