pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

import qs.core.services

/**
 * The status glyphs: the connection, the sound and the battery, in every
 * state they have.
 *
 * Drawn from Material Design Icons, which the Nerd Font the interface already
 * depends on carries. Material Symbols, which draws the rest of this desktop,
 * has a speaker with two loudnesses and nothing for a wired or tethered
 * connection without internet. Named here by their icon names, which the font
 * does not know: it has no ligatures, only code points.
 */
Singleton {
    id: root

    readonly property string family: "JetBrainsMono Nerd Font Propo"

    readonly property var codes: ({
        "volume_off": 0xF0581,
        "volume_low": 0xF057F,
        "volume_medium": 0xF0580,
        "volume_high": 0xF057E,
        "headphones": 0xF02CB,
        "headphones_bluetooth": 0xF0970,
        "headphones_off": 0xF07CE,
        "speaker_bluetooth": 0xF09A2,
        "speaker_off": 0xF04C4,
        "monitor_speaker": 0xF0F5F,
        "monitor_speaker_off": 0xF0F60,
        "wifi_strength_outline": 0xF092F,
        "wifi_strength_1": 0xF091F,
        "wifi_strength_2": 0xF0922,
        "wifi_strength_3": 0xF0925,
        "wifi_strength_4": 0xF0928,
        "wifi_strength_alert_outline": 0xF092B,
        "wifi_strength_1_alert": 0xF0920,
        "wifi_strength_2_alert": 0xF0923,
        "wifi_strength_3_alert": 0xF0926,
        "wifi_strength_4_alert": 0xF0929,
        "wifi_strength_off_outline": 0xF092E,
        "ethernet": 0xF0200,
        "lan_disconnect": 0xF0319,
        "web_off": 0xF0A8E,
        "cellphone_wireless": 0xF0815,
        "network_strength_4": 0xF08FA,
        "network_strength_4_alert": 0xF08FB,
        "shield_lock": 0xF099D,
        "alert_circle": 0xF0028,
        "battery_outline": 0xF008E,
        "battery_10": 0xF007A,
        "battery_20": 0xF007B,
        "battery_30": 0xF007C,
        "battery_40": 0xF007D,
        "battery_50": 0xF007E,
        "battery_60": 0xF007F,
        "battery_70": 0xF0080,
        "battery_80": 0xF0081,
        "battery_90": 0xF0082,
        "battery": 0xF0079,
        "battery_charging_outline": 0xF089F,
        "battery_charging_10": 0xF089C,
        "battery_charging_20": 0xF0086,
        "battery_charging_30": 0xF0087,
        "battery_charging_40": 0xF0088,
        "battery_charging_50": 0xF089D,
        "battery_charging_60": 0xF0089,
        "battery_charging_70": 0xF089E,
        "battery_charging_80": 0xF008A,
        "battery_charging_90": 0xF008B,
        "battery_charging_100": 0xF0085,
        "battery_alert_variant_outline": 0xF10CD
    })

    /** The character that draws a glyph, or nothing for a name not listed. */
    function text(name: string): string {
        const code = root.codes[name];
        return code ? String.fromCodePoint(code) : "";
    }

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
            return muted ? "headphones_off" : "headphones";
        case "bluetoothHeadphones":
            return muted ? "headphones_off" : "headphones_bluetooth";
        case "bluetoothSpeaker":
            return muted ? "speaker_off" : "speaker_bluetooth";
        case "display":
            return muted ? "monitor_speaker_off" : "monitor_speaker";
        }
        if (muted)
            return "volume_off";
        if (root.volume < 0.005)
            return "volume_low";
        if (root.volume <= 0.5)
            return "volume_medium";
        return "volume_high";
    }

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
            return root.noInternet ? "lan_disconnect" : "ethernet";
        if (type === "wifi") {
            const bars = root.bars(Network.active?.strength ?? Network.networkStrength);
            if (root.noInternet)
                return bars === 0 ? "wifi_strength_alert_outline" : `wifi_strength_${bars}_alert`;
            return bars === 0 ? "wifi_strength_outline" : `wifi_strength_${bars}`;
        }
        // NetworkManager does not say how strong a modem's signal is.
        if (type === "cellular")
            return root.noInternet ? "network_strength_4_alert" : "network_strength_4";
        if (type === "bluetooth")
            return "cellphone_wireless";
        if (root.connecting === "bluetooth")
            return "cellphone_wireless";
        if (root.connecting === "wifi")
            return `wifi_strength_${root.frame + 1}`;
        if (!Network.wifiEnabled)
            return "wifi_strength_off_outline";
        return "web_off";
    }

    /**
     * The mark in the corner of the connection: no internet, for a tethered
     * phone, whose glyph has no way to say it, and otherwise a tunnel, while
     * one carries the traffic.
     */
    readonly property string networkBadge: {
        if (!Network.connected)
            return "";
        if (root.noInternet && Network.connectionType === "bluetooth")
            return "alert_circle";
        return Network.vpnActive ? "shield_lock" : "";
    }

    // -- Battery ----------------------------------------------------------------

    /** The battery in tenths, charging or not, and running low. Empty without one. */
    readonly property string batteryGlyph: {
        if (!Battery.available)
            return "";
        const tenths = Math.max(0, Math.min(10, Math.round(Battery.percentage * 10)));
        if (Battery.isCharging)
            return tenths === 0 ? "battery_charging_outline" : `battery_charging_${tenths * 10}`;
        if (Battery.isLow)
            return "battery_alert_variant_outline";
        if (tenths === 10)
            return "battery";
        return tenths === 0 ? "battery_outline" : `battery_${tenths * 10}`;
    }
}
