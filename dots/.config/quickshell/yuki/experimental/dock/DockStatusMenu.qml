import QtQuick
import Quickshell

import qs.core.services
import qs.experimental.looks

// What a right click on the status block offers, for whichever part of it was
// clicked, as each icon in the Windows corner has its own: the connection its
// settings, the sound muting and its settings, the battery the power settings,
// the clock do not disturb and the settings of notifications and of the time,
// the layout the keyboard settings.
ExPopup {
    id: root

    /** The part clicked: "network", "volume", "battery", "clock" or "layout". */
    property string kind: ""

    readonly property bool muted: Audio.sink?.audio?.muted ?? false

    function settings(page: string): var {
        return () => Surfaces.open("settings", page);
    }

    readonly property var items: {
        switch (root.kind) {
        case "network":
            return [
                { key: "wifi", text: Translation.tr("Wi-Fi settings"), glyph: "wifi", run: root.settings("wifi") },
                { key: "connections", text: Translation.tr("Connections"), glyph: "lan", run: root.settings("connections") }
            ];
        case "volume":
            return [
                {
                    key: "mute",
                    text: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute"),
                    glyph: root.muted ? "volume_up" : "volume_off",
                    run: () => {
                        if (Audio.sink?.audio)
                            Audio.sink.audio.muted = !Audio.sink.audio.muted;
                    }
                },
                { key: "separator", separator: true },
                { key: "sound", text: Translation.tr("Sound settings"), glyph: "settings", run: root.settings("sound") }
            ];
        case "battery":
            return [
                { key: "power", text: Translation.tr("Power settings"), glyph: "bolt", run: root.settings("power") }
            ];
        case "clock":
            return [
                {
                    key: "silent",
                    text: Notifications.silent ? Translation.tr("Turn off do not disturb") : Translation.tr("Turn on do not disturb"),
                    glyph: Notifications.silent ? "notifications" : "notifications_off",
                    run: () => Notifications.silent = !Notifications.silent
                },
                { key: "separator", separator: true },
                { key: "notifications", text: Translation.tr("Notification settings"), glyph: "settings", run: root.settings("notifications") },
                { key: "time", text: Translation.tr("Date and time settings"), glyph: "schedule", run: root.settings("language") }
            ];
        case "layout":
            return [
                { key: "keyboard", text: Translation.tr("Keyboard settings"), glyph: "keyboard", run: root.settings("keyboard") }
            ];
        }
        return [];
    }

    /** Opens the menu of one part, from the item it stands for, or closes it when it is already open there. */
    function openFor(kind: string, item: Item) {
        if (root.open && root.opener === item && root.kind === kind) {
            root.open = false;
            return;
        }
        // Elsewhere on the block while it is open, it comes out again there.
        root.open = false;
        root.kind = kind;
        root.toggle(item);
    }

    padding: ExLooks.sizes.menuPadding
    surfaceRadius: ExLooks.radius.menu

    onDismissRequested: root.open = false

    Column {
        width: ExLooks.sizes.menuWidth

        Repeater {
            model: ScriptModel {
                values: root.items
                objectProp: "key"
            }

            Loader {
                id: slot

                required property var modelData

                width: parent.width
                sourceComponent: slot.modelData.separator ? separator : item

                Component {
                    id: separator
                    ExMenuSeparator {}
                }

                Component {
                    id: item
                    ExMenuItem {
                        text: slot.modelData.text
                        glyph: slot.modelData.glyph
                        onClicked: {
                            root.open = false;
                            slot.modelData.run();
                        }
                    }
                }
            }
        }
    }
}
