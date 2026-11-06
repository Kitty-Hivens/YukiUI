pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import qs.core.services

/**
 * The status glyphs: the connection, the sound and the battery, in every state
 * they have, by their names in Material Symbols, which draws the rest of this
 * desktop. A state the font has no glyph of its own for is a glyph with a mark in
 * its corner: Wi-Fi of so many bars with no internet, a cable with none, a
 * Bluetooth device.
 */
Singleton {
    id: root

    readonly property var wifiBars: ["signal_wifi_0_bar", "network_wifi_1_bar", "network_wifi_2_bar", "network_wifi_3_bar", "signal_wifi_4_bar"]

    // Every glyph each status can show, for a place that keeps it as wide as
    // the widest of them. The battery's by whether it is charging: the bolt
    // makes it nearly twice as wide, and kept that wide for good it left an
    // empty stretch beside the battery whenever it was not charging.
    readonly property var chargingGlyphs: ["battery_charging_20", "battery_charging_30", "battery_charging_50", "battery_charging_60", "battery_charging_80", "battery_charging_90", "battery_charging_full"]
    readonly property var batteryBars: ["battery_0_bar", "battery_1_bar", "battery_2_bar", "battery_3_bar", "battery_4_bar", "battery_5_bar", "battery_6_bar", "battery_full"]
    readonly property var dischargingGlyphs: [...root.batteryBars, "battery_alert"]
    readonly property var networkGlyphs: [...root.wifiBars, "signal_wifi_off", "lan", "public_off", "mobile_share", "signal_cellular_4_bar", "signal_cellular_connected_no_internet_4_bar"]

    // -- Sound ------------------------------------------------------------------

    /** Where sound comes out: the hardware behind whatever processor is in the way. */
    readonly property var output: Audio.defaultSinkEndpoint ?? Audio.sink
    // What a device is, its form among it, comes with its properties, and
    // those only with a device that is tracked.
    PwObjectTracker {
        objects: [root.output]
    }

    /**
     * What sound comes out of: "headphones", "bluetoothHeadphones",
     * "bluetoothSpeaker", "display", or "speakers" for anything that does not
     * say. A device says so by its form, which a headset, Bluetooth or wired,
     * reports, and a screen by its name. A USB dongle reports no form, and is
     * shown by how loud it is.
     */
    readonly property string outputKind: {
        const node = root.output;
        const name = node?.name ?? "";
        const properties = node?.properties ?? {};
        const form = properties["device.form-factor"] ?? "";
        const icon = properties["device.icon-name"] ?? "";
        const worn = /^(head|hands)/.test(form) || /head(set|phone)/.test(icon);
        if (name.startsWith("bluez_"))
            return worn ? "bluetoothHeadphones" : "bluetoothSpeaker";
        if (worn)
            return "headphones";
        if (/hdmi|displayport/i.test(`${name} ${node?.description ?? ""}`))
            return "display";
        return "speakers";
    }

    /**
     * The glyphs the sound can show on the output playing now, for a place
     * as wide as the widest of them. Counted across every output, the screen's
     * speaker set the width, and a plain speaker stood in a wide empty stretch.
     */
    readonly property var volumeVariants: {
        switch (root.outputKind) {
        case "headphones":
        case "bluetoothHeadphones":
            return ["headphones", "headset_off"];
        case "bluetoothSpeaker":
            return ["speaker", "volume_off"];
        case "display":
            return ["tv", "tv_off"];
        }
        return ["volume_off", "volume_mute", "volume_down", "volume_up"];
    }

    readonly property bool muted: Audio.sink?.audio?.muted ?? false
    readonly property real volume: Audio.sink?.audio?.volume ?? 0

    /**
     * The sound, as Windows shows it: headphones, a Bluetooth speaker or a
     * screen by what they are, and anything else by how loud it plays. The
     * font's speaker has no waves, one or two, so no waves is silence, and
     * the waves split the rest in halves: a speaker with no waves at a low
     * volume read as no sound at all.
     */
    readonly property string volumeGlyph: {
        const muted = root.muted;
        switch (root.outputKind) {
        case "headphones":
        case "bluetoothHeadphones":
            return muted ? "headset_off" : "headphones";
        case "bluetoothSpeaker":
            return muted ? "volume_off" : "speaker";
        case "display":
            return muted ? "tv_off" : "tv";
        }
        if (muted)
            return "volume_off";
        if (root.volume < 0.005)
            return "volume_mute";
        if (root.volume <= 0.5)
            return "volume_down";
        return "volume_up";
    }

    /** The mark on the sound: the font has no Bluetooth headphones or speaker of their own. */
    readonly property string volumeBadge: root.outputKind === "bluetoothHeadphones" || root.outputKind === "bluetoothSpeaker" ? "bluetooth" : ""

    /** The loudness not reached, stood faintly behind the speaker. */
    readonly property string volumeGhost: root.volumeGlyph === "volume_mute" || root.volumeGlyph === "volume_down" ? "volume_up" : ""

    // -- Connection -------------------------------------------------------------

    /**
     * Connected, but not to the internet, as NetworkManager judges it. Its
     * check goes through a tunnel when one is up and calls a working
     * connection limited, so with a tunnel only no connectivity at all counts.
     */
    readonly property bool noInternet: Network.connected
        && (Network.connectivity === "none" || Network.connectivity === "portal"
            || (Network.connectivity === "limited" && !Network.vpnActive))

    /** What is being connected to while nothing carries the connection: "wifi", "bluetooth", or empty. */
    readonly property string connecting: {
        if (Network.connected)
            return "";
        const busy = Network.otherConnections.find(connection => connection.uuid === Network.busyConnectionUuid);
        if (Network.connectionBusy && busy?.channel === "bluetooth")
            return "bluetooth";
        if (Network.wifiConnecting || Network.wifiStatus === "connecting")
            return "wifi";
        return "";
    }

    // The arcs filling one after another while Wi-Fi connects, as on Windows.
    property int frame: 0
    Timer {
        running: root.connecting === "wifi"
        interval: 350
        repeat: true
        onTriggered: root.frame = (root.frame + 1) % 4
        onRunningChanged: root.frame = 0
    }

    /** Bars of signal, 0 to 4, from a strength in per cent. */
    function bars(strength: real): int {
        if (strength > 80)
            return 4;
        if (strength > 55)
            return 3;
        if (strength > 30)
            return 2;
        if (strength > 5)
            return 1;
        return 0;
    }

    readonly property string networkGlyph: {
        const type = Network.connectionType;
        if (type === "ethernet")
            return "lan";
        if (type === "wifi")
            return root.wifiBars[root.bars(Network.active?.strength ?? Network.networkStrength)];
        // NetworkManager does not say how strong a modem's signal is.
        if (type === "cellular")
            return root.noInternet ? "signal_cellular_connected_no_internet_4_bar" : "signal_cellular_4_bar";
        if (type === "bluetooth" || root.connecting === "bluetooth")
            return "mobile_share";
        if (root.connecting === "wifi")
            return root.wifiBars[root.frame + 1];
        if (!Network.wifiEnabled)
            return "signal_wifi_off";
        return "public_off";
    }

    /**
     * The mark in the corner of the connection: no internet, where the glyph has
     * no way to say it, and otherwise a tunnel, while one carries the traffic.
     */
    readonly property string networkBadge: {
        if (!Network.connected)
            return "";
        if (root.noInternet && Network.connectionType !== "cellular")
            return "priority_high";
        return Network.vpnActive ? "shield_lock" : "";
    }

    // -- Battery ----------------------------------------------------------------

    /** The battery by as many steps as the font has, charging or not, and running low. Empty without one. */
    readonly property string batteryGlyph: {
        if (!Battery.available)
            return "";
        const level = Math.max(0, Math.min(1, Battery.percentage));
        if (Battery.isCharging)
            return root.chargingGlyphs[[0.25, 0.4, 0.55, 0.7, 0.85, 0.95, 2].findIndex(step => level < step)];
        if (Battery.isLow)
            return "battery_alert";
        return root.batteryBars[Math.round(level * 7)];
    }
}
