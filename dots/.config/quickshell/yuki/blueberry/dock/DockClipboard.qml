pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

import qs.core
import qs.core.functions
import qs.core.services
import qs.blueberry
import qs.blueberry.looks

// The clipboard history on Win+V, out of the middle of the dock: a search, what
// was copied lately down the left, newest first, and the one picked shown whole
// on the right with where and when it was copied. A click or Enter copies it back
// and the history goes. Typing searches straight away, the arrows and the wheel
// move from one entry to the next, Delete on
// an empty search deletes, Escape closes. Everything inside is rounded by the
// panel's corner less the room round it, so the corners run parallel.
ExPopup {
    id: root

    /** The entry the keys are on, in the list as searched. */
    property int current: 0

    /** What the dock hands the keys to while this is open. */
    readonly property Item keyTarget: root.open ? search.input : null

    readonly property var shown: search.text.trim().length > 0 ? ClipboardHistory.fuzzyQuery(search.text) : ClipboardHistory.entries
    readonly property var picked: root.shown[Math.min(root.current, root.shown.length - 1)] ?? null

    onOpenChanged: {
        ExClipboardHistory.open = root.open;
        if (root.open) {
            search.text = "";
            root.current = 0;
            search.input.forceActiveFocus();
        }
    }
    onShownChanged: root.current = Math.max(0, Math.min(root.current, root.shown.length - 1))
    onPickedChanged: ExClipboardHistory.picked = root.picked?.id ?? ""

    /** The corner of what stands inside the panel, the panel's less the room between them. */
    readonly property real innerRadius: ExLooks.radius.panel - ExLooks.spacing.m

    padding: ExLooks.spacing.m
    motion: "panel"
    onDismissRequested: root.open = false

    /** What an entry is, told apart further than the history does: a link and a colour are text too. */
    function kindOf(entry): string {
        if (!entry)
            return "";
        if (entry.kind !== "text")
            return entry.kind;
        const text = (entry.preview ?? "").trim();
        if (/^https?:\/\/\S+$/i.test(text))
            return "link";
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(text) || /^rgba?\([\d\s.,%]+\)$/i.test(text))
            return "color";
        return "text";
    }

    readonly property var kinds: ({
        text: { name: Translation.tr("Text"), glyph: "notes", hue: 230 },
        link: { name: Translation.tr("Link"), glyph: "link", hue: 195 },
        image: { name: Translation.tr("Picture"), glyph: "image", hue: 350 },
        files: { name: Translation.tr("Files"), glyph: "folder", hue: 145 },
        color: { name: Translation.tr("Colour"), glyph: "palette", hue: 30 }
    })

    function hued(hue: real, saturation: real, lightness: real): color {
        return Qt.hsla(hue / 360, saturation, lightness, 1);
    }
    function chipColor(hue: real): color {
        return root.hued(hue, ExLooks.dark ? 0.32 : 0.55, ExLooks.dark ? 0.26 : 0.9);
    }
    function chipInk(hue: real): color {
        return root.hued(hue, 0.5, ExLooks.dark ? 0.75 : 0.36);
    }

    /** One line for the list. */
    function lineOf(entry): string {
        if (!entry)
            return "";
        if (entry.kind === "image")
            return entry.width > 0 ? Translation.tr("Picture %1 × %2").arg(entry.width).arg(entry.height) : Translation.tr("Picture");
        if (entry.kind === "files") {
            const names = (entry.preview ?? "").split("\n").filter(name => name.length > 0);
            return names.length > 1 ? Translation.tr("%1 and %2 more").arg(names[0]).arg(names.length - 1) : (names[0] ?? "");
        }
        return (entry.preview ?? "").replace(/\s+/g, " ").trim();
    }

    /** How long ago, said the short way. */
    function ago(time: real): string {
        const seconds = Math.max(0, Date.now() / 1000 - time);
        if (seconds < 60)
            return Translation.tr("now");
        if (seconds < 3600)
            return Translation.tr("%1 min").arg(Math.floor(seconds / 60));
        if (seconds < 86400)
            return Translation.tr("%1 h").arg(Math.floor(seconds / 3600));
        if (seconds < 2 * 86400)
            return Translation.tr("yesterday");
        return Qt.locale().toString(new Date(time * 1000), Config.options.time.shortDateFormat);
    }

    function sizeOf(entry): string {
        if (!entry)
            return "";
        const bytes = entry.size ?? 0;
        const units = [Translation.tr("B"), Translation.tr("KB"), Translation.tr("MB"), Translation.tr("GB")];
        let value = bytes;
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        const amount = `${Number(value).toLocaleString(Qt.locale(), "f", unit > 0 && value < 10 ? 1 : 0)} ${units[unit]}`;
        if (entry.kind === "image" && entry.width > 0)
            return `${entry.width} × ${entry.height}  ·  ${amount}`;
        if (entry.kind === "text")
            return Translation.tr("%1 characters").arg((entry.preview ?? "").length >= 400 ? "400+" : (entry.preview ?? "").length);
        if (entry.kind === "files") {
            const count = (entry.paths?.length ?? 0) || (entry.preview ?? "").split("\n").filter(name => name.length > 0).length;
            return Translation.tr("%1 items").arg(count);
        }
        return amount;
    }

    function choose(entry) {
        if (entry)
            ExClipboardHistory.choose(entry.id);
    }

    // The whole text of the one picked: the list keeps only the start of it.
    property string fullText: ""
    FileView {
        id: textForm
        path: {
            const entry = root.picked;
            if (!entry || entry.kind !== "text")
                return "";
            const form = (entry.forms ?? []).find(form => form.type.startsWith("text/plain") || form.type === "UTF8_STRING");
            return form?.file ?? "";
        }
        printErrors: false
        onLoaded: root.fullText = textForm.text().slice(0, 20000)
        onPathChanged: root.fullText = ""
    }

    ColumnLayout {
        width: 780
        spacing: ExLooks.spacing.m

        RowLayout {
            Layout.fillWidth: true
            spacing: ExLooks.spacing.s

            ExTextField {
                id: search

                Layout.fillWidth: true
                implicitHeight: 40
                radius: root.innerRadius
                glyph: "search"
                placeholder: Translation.tr("Search the clipboard")

                input.Keys.onPressed: event => {
                    const count = root.shown.length;
                    if (event.key === Qt.Key_Escape) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Down && count > 0) {
                        root.current = Math.min(count - 1, root.current + 1);
                    } else if (event.key === Qt.Key_Up && count > 0) {
                        root.current = Math.max(0, root.current - 1);
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.picked) {
                        root.choose(root.picked);
                    } else if (event.key === Qt.Key_Delete && search.text.length === 0 && root.picked) {
                        ExClipboardHistory.run("delete", root.picked.id);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
            ExButton {
                kind: "flat"
                glyph: "delete_sweep"
                text: Translation.tr("Clear")
                enabled: ClipboardHistory.entries.some(entry => !entry.pinned)
                onClicked: ExClipboardHistory.run("clear")
            }
        }

        // Nothing yet, or nothing found, in the middle of the room the list
        // and the preview take.
        Item {
            visible: root.shown.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 420

            Column {
                anchors.centerIn: parent
                spacing: ExLooks.spacing.s

                ExGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: search.text.length > 0 ? "search_off" : "content_paste"
                    size: 40
                    color: ExLooks.colors.textDim
                }
                ExText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: search.text.length > 0 ? Translation.tr("Nothing found") : Translation.tr("Nothing copied yet")
                    role: "label"
                }
            }
        }

        RowLayout {
            visible: root.shown.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 420
            spacing: ExLooks.spacing.m

            ListView {
                id: list

                Layout.preferredWidth: 320
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                // Not flicked or scrolled by hand: the wheel picks instead, and
                // the list follows the pick.
                interactive: false
                model: root.shown
                currentIndex: root.current
                onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                // The plate of the entry picked glides to the next one. Moved by
                // the arrows and by a click only: following the pointer it ran
                // behind it the whole way down, with the text it passed lit at
                // once and its plate a moment later.
                highlightFollowsCurrentItem: false
                highlight: Rectangle {
                    width: list.width
                    height: list.currentItem?.height ?? 0
                    y: list.currentItem?.y ?? 0
                    radius: root.innerRadius
                    color: ExLooks.colors.tonal

                    Behavior on y {
                        NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                    }
                }

                // A row going makes room by sliding the rest up, rather than
                // leaving a hole for a frame.
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: ExLooks.motion.fast }
                }
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                }

                // The wheel picks the next entry rather than scrolling the list,
                // so the preview can be looked through with the mouse before a
                // click takes one. A touchpad's small steps add up to a notch.
                property real wheelRest: 0
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        list.wheelRest += event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                        while (Math.abs(list.wheelRest) >= 120) {
                            const step = list.wheelRest > 0 ? -1 : 1;
                            root.current = Math.max(0, Math.min(root.shown.length - 1, root.current + step));
                            list.wheelRest -= 120 * -step;
                        }
                        event.accepted = true;
                    }
                }

                delegate: AbstractButton {
                    id: row

                    ExPrimaryOnly {
                        z: 1
                    }

                    required property var modelData
                    required property int index
                    readonly property var kind: root.kinds[root.kindOf(row.modelData)] ?? root.kinds.text
                    readonly property bool here: row.index === root.current

                    width: ListView.view.width
                    height: 52
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.current = row.index;
                        root.choose(row.modelData);
                    }

                    // Under the pointer at once, apart from the plate of the one picked.
                    background: Rectangle {
                        radius: root.innerRadius
                        color: "transparent"

                        ExStateLayer {
                            ink: ExLooks.colors.text
                            hovered: row.hovered
                            pressed: row.down
                        }
                    }
                    contentItem: RowLayout {
                        spacing: ExLooks.spacing.m

                        Rectangle {
                            Layout.leftMargin: ExLooks.spacing.s
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 16
                            color: root.chipColor(row.kind.hue)

                            ExGlyph {
                                anchors.centerIn: parent
                                text: row.kind.glyph
                                size: 18
                                color: root.chipInk(row.kind.hue)
                            }
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: root.lineOf(row.modelData)
                            elide: Text.ElideRight
                            color: row.here ? ExLooks.colors.tonalInk : ExLooks.colors.text

                            Behavior on color {
                                ColorAnimation { duration: ExLooks.motion.normal }
                            }
                        }
                        ExGlyph {
                            visible: row.modelData.pinned === true
                            text: "keep"
                            size: 14
                            fill: 1
                            color: ExLooks.colors.accent
                        }
                        ExText {
                            Layout.rightMargin: ExLooks.spacing.s
                            text: root.ago(row.modelData.time)
                            role: "caption"
                            dim: true
                        }
                    }
                }
            }

            // The one picked, whole.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.innerRadius
                color: ExLooks.colors.surfaceSunken

                ColumnLayout {
                    id: preview

                    readonly property var entry: root.picked
                    readonly property string kind: root.kindOf(preview.entry)

                    anchors.fill: parent
                    anchors.margins: ExLooks.spacing.m
                    spacing: ExLooks.spacing.m
                    opacity: 1

                    // A new entry comes in rather than being swapped.
                    onEntryChanged: arrive.restart()
                    NumberAnimation {
                        id: arrive
                        target: preview
                        property: "opacity"
                        from: 0.4
                        to: 1
                        duration: ExLooks.motion.fast
                    }

                    // What it is, from where, when and how large, in one line
                    // under its kind, and what can be done to it beside them.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ExLooks.spacing.m

                        Rectangle {
                            readonly property var kind: root.kinds[preview.kind] ?? root.kinds.text
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: root.chipColor(kind.hue)

                            ExGlyph {
                                anchors.centerIn: parent
                                text: parent.kind.glyph
                                size: 20
                                color: root.chipInk(parent.kind.hue)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            ExText {
                                Layout.fillWidth: true
                                text: (root.kinds[preview.kind] ?? root.kinds.text).name
                                role: "label"
                                font.weight: ExLooks.font.weightTitle
                            }
                            ExText {
                                Layout.fillWidth: true
                                text: {
                                    const entry = preview.entry;
                                    if (!entry)
                                        return "";
                                    const app = AppSearch.entryFor(entry.app ?? "")?.name ?? (entry.app ?? "");
                                    const when = Qt.locale().toString(new Date(entry.time * 1000), `${Config.options.time.shortDateFormat} ${Config.options.time.format}`);
                                    return [app, when, root.sizeOf(entry)].filter(part => part.length > 0).join("  ·  ");
                                }
                                role: "caption"
                                dim: true
                                elide: Text.ElideRight
                            }
                        }
                        // Together, as a toolbar's buttons stand.
                        Row {
                            spacing: 2

                            ExToolButton {
                                visible: preview.kind === "link"
                                implicitWidth: 32
                                implicitHeight: 32
                                glyph: "open_in_new"
                                onClicked: {
                                    Qt.openUrlExternally((preview.entry?.preview ?? "").trim());
                                    root.open = false;
                                }
                            }
                            ExToolButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                glyph: "keep"
                                toggled: preview.entry?.pinned ?? false
                                onClicked: ExClipboardHistory.run("pin", preview.entry.id, preview.entry.pinned ? "0" : "1")
                            }
                            ExToolButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                glyph: "delete"
                                onClicked: ExClipboardHistory.run("delete", preview.entry.id)
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // As large as fits, and rounded at the picture's own
                        // corners rather than at the room around it.
                        // The picture's own size, as the history wrote it down, or
                        // read off a copy for an entry older than that. Taken off the
                        // picture on show, it changed with the frame it sized.
                        Image {
                            id: measure
                            visible: false
                            source: preview.kind === "image" && !(preview.entry.width > 0) ? FileUtils.fileUrl(preview.entry.image) : ""
                            sourceSize.width: 900
                            asynchronous: true
                        }
                        ClippingRectangle {
                            id: frame

                            readonly property real naturalWidth: preview.entry?.width > 0 ? preview.entry.width : measure.implicitWidth
                            readonly property real naturalHeight: preview.entry?.height > 0 ? preview.entry.height : measure.implicitHeight
                            readonly property real room: Math.min(parent.width, 2000)
                            readonly property real fit: frame.naturalWidth > 0 && frame.naturalHeight > 0
                                ? Math.min(frame.room / frame.naturalWidth, parent.height / frame.naturalHeight, 1) : 0

                            visible: preview.kind === "image"
                            anchors.centerIn: parent
                            width: Math.round(frame.naturalWidth * frame.fit)
                            height: Math.round(frame.naturalHeight * frame.fit)
                            radius: Math.max(4, root.innerRadius - ExLooks.spacing.m / 2)
                            color: "transparent"

                            Image {
                                id: picture
                                anchors.fill: parent
                                source: preview.kind === "image" ? FileUtils.fileUrl(preview.entry.image) : ""
                                sourceSize.width: 900
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }
                        Flickable {
                            visible: preview.kind === "text"
                            anchors.fill: parent
                            clip: true
                            contentHeight: whole.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            ExText {
                                id: whole
                                width: parent.width
                                text: root.fullText.length > 0 ? root.fullText : (preview.entry?.preview ?? "")
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                            }
                        }
                        ColumnLayout {
                            visible: preview.kind === "link"
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: ExLooks.spacing.s

                            ExGlyph {
                                Layout.alignment: Qt.AlignHCenter
                                text: "public"
                                size: 48
                                color: root.chipInk(195)
                            }
                            ExText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: (preview.entry?.preview ?? "").replace(/^https?:\/\//i, "").split("/")[0]
                                role: "title"
                                elide: Text.ElideRight
                            }
                            ExText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: (preview.entry?.preview ?? "").trim()
                                role: "caption"
                                dim: true
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            visible: preview.kind === "color"
                            anchors.fill: parent
                            radius: Math.max(4, root.innerRadius - ExLooks.spacing.m / 2)
                            color: preview.kind === "color" ? (preview.entry?.preview ?? "").trim() : "transparent"

                            ExText {
                                anchors.centerIn: parent
                                text: (preview.entry?.preview ?? "").trim()
                                font.family: "monospace"
                                font.pixelSize: 20
                                // Dark or light by how bright the colour is to the eye, not by its lightness.
                                readonly property color shown: parent.color
                                color: 0.2126 * shown.r + 0.7152 * shown.g + 0.0722 * shown.b > 0.55 ? "#15161a" : "#ffffff"
                            }
                        }
                        ColumnLayout {
                            visible: preview.kind === "files"
                            anchors.fill: parent
                            spacing: ExLooks.spacing.s

                            Repeater {
                                model: preview.kind === "files" ? (preview.entry?.paths?.length > 0 ? preview.entry.paths : (preview.entry?.preview ?? "").split("\n")).slice(0, 8) : []

                                RowLayout {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    spacing: ExLooks.spacing.m

                                    ExGlyph {
                                        text: /\.[^/]+$/.test(modelData) ? "description" : "folder"
                                        size: 22
                                        fill: 1
                                        color: root.chipInk(145)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        ExText {
                                            Layout.fillWidth: true
                                            text: modelData.split("/").pop()
                                            elide: Text.ElideMiddle
                                        }
                                        ExText {
                                            Layout.fillWidth: true
                                            visible: modelData.includes("/")
                                            text: modelData.slice(0, modelData.lastIndexOf("/"))
                                            role: "caption"
                                            dim: true
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    ExButton {
                        Layout.fillWidth: true
                        kind: "accent"
                        glyph: "content_copy"
                        text: Translation.tr("Copy")
                        onClicked: root.choose(preview.entry)
                    }
                }
            }
        }
    }
}
