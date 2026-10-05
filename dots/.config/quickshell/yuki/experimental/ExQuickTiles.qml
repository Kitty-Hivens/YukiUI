pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower

import qs.core
import qs.core.models.quickToggles
import qs.core.services
import qs.experimental.looks

/**
 * The tiles quick settings can hold: what each shows, what a click on it does,
 * and which are pinned, in what order. Shared by the docks of every screen, so
 * a tile with a process behind it runs it once.
 *
 * A tile is this environment's own, or one the other environments share, or a
 * plugin's, by its id. Those that need a surface this environment does not
 * have, the on-screen keyboard and music recognition, are not offered.
 */
Singleton {
    id: root

    // Shared with the other environments, made once here.
    readonly property QuickToggleModel gameModeModel: GameModeToggle {}
    readonly property QuickToggleModel easyEffectsModel: EasyEffectsToggle {}
    readonly property QuickToggleModel micModel: MicToggle {}
    readonly property QuickToggleModel antiFlashbangModel: AntiFlashbangToggle {}

    /** This environment's tiles, and the shared ones it shows, in the order they are offered. */
    readonly property var ownKeys: ["wifi", "bluetooth", "nightLight", "doNotDisturb", "powerMode", "keepAwake", "gameMode", "easyEffects", "mic", "darkMode", "antiFlashbang", "colorPicker"]

    function available(key: string): bool {
        if (key === "bluetooth")
            return BluetoothStatus.available;
        if (key === "easyEffects")
            return EasyEffects.available;
        return root.ownKeys.includes(key) || Plugins.quickToggleIds.includes(key);
    }

    /** Every tile that can be pinned here. */
    readonly property var catalogue: [...root.ownKeys.filter(key => root.available(key)), ...Plugins.quickToggleIds]

    readonly property var saved: Config.options.experimental.quickSettings.tiles
    /** The tiles shown, in their order. */
    readonly property var pinned: root.saved.filter(key => root.catalogue.includes(key))
    /** The tiles that could be added. */
    readonly property var unpinned: root.catalogue.filter(key => !root.saved.includes(key))

    /**
     * Puts the shown tiles in a new order. Those kept but not available now,
     * a plugin switched off say, stay in the list after them.
     */
    function setPinned(keys) {
        Config.options.experimental.quickSettings.tiles = [...keys, ...root.saved.filter(key => !root.catalogue.includes(key) && !keys.includes(key))];
    }
    function pin(key: string) {
        if (!root.saved.includes(key))
            root.setPinned([...root.pinned, key]);
    }
    function unpin(key: string) {
        root.setPinned(root.pinned.filter(other => other !== key));
    }

    readonly property string powerProfileName: PowerProfiles.profile === PowerProfile.PowerSaver ? Translation.tr("Power saver")
        : PowerProfiles.profile === PowerProfile.Performance ? Translation.tr("Performance")
        : Translation.tr("Balanced")

    function nextPowerProfile() {
        if (PowerProfiles.profile === PowerProfile.PowerSaver)
            PowerProfiles.profile = PowerProfile.Balanced;
        else if (PowerProfiles.profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance;
        else
            PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    function onOff(on: bool): string {
        return on ? Translation.tr("On") : Translation.tr("Off");
    }

    /**
     * What a tile shows, read live from the system: glyph, text, subtitle,
     * whether it is on, whether a page stands behind it, and whether a click
     * closes quick settings first, for a tile that acts on the screen.
     */
    function info(key: string): var {
        if (key === "wifi") {
            // Wi-Fi's own network, not whatever carries the connection: on a
            // cable or a Bluetooth tether the shared name and glyph describe
            // those.
            const network = Network.active?.ssid || (Network.activeConnectionNames["wifi"] ?? "");
            return {
                glyph: !Network.wifiEnabled ? "signal_wifi_off"
                    : Network.connectionType === "wifi" ? Network.materialSymbol
                    : network.length > 0 ? "wifi" : "wifi_find",
                text: Translation.tr("Wi-Fi"),
                subtitle: Network.wifiEnabled ? (network || Translation.tr("Not connected")) : Translation.tr("Off"),
                checked: Network.wifiEnabled,
                hasPage: true
            };
        }
        if (key === "bluetooth")
            return {
                glyph: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth",
                text: Translation.tr("Bluetooth"),
                subtitle: !BluetoothStatus.enabled ? Translation.tr("Off") : (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")),
                checked: BluetoothStatus.enabled,
                hasPage: true
            };
        if (key === "nightLight")
            return { glyph: "nightlight", text: Translation.tr("Night Light"), subtitle: root.onOff(Hyprsunset.temperatureActive), checked: Hyprsunset.temperatureActive };
        if (key === "doNotDisturb")
            return {
                glyph: Notifications.silent ? "notifications_off" : "notifications",
                text: Translation.tr("Do not disturb"),
                subtitle: root.onOff(Notifications.silent),
                checked: Notifications.silent
            };
        if (key === "powerMode")
            return {
                glyph: PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf" : PowerProfiles.profile === PowerProfile.Performance ? "speed" : "balance",
                text: Translation.tr("Power mode"),
                subtitle: root.powerProfileName,
                checked: PowerProfiles.profile !== PowerProfile.Balanced
            };
        if (key === "keepAwake")
            return { glyph: "coffee", text: Translation.tr("Keep awake"), subtitle: root.onOff(Idle.inhibit), checked: Idle.inhibit };
        if (key === "gameMode")
            return { glyph: "sports_esports", text: root.gameModeModel.name, subtitle: root.gameModeModel.statusText, checked: root.gameModeModel.toggled };
        if (key === "easyEffects")
            return { glyph: "graphic_eq", text: root.easyEffectsModel.name, subtitle: root.onOff(root.easyEffectsModel.toggled), checked: root.easyEffectsModel.toggled };
        if (key === "mic")
            return { glyph: root.micModel.icon, text: Translation.tr("Microphone"), subtitle: root.micModel.statusText, checked: root.micModel.toggled };
        if (key === "darkMode")
            return { glyph: ExLooks.dark ? "dark_mode" : "light_mode", text: Translation.tr("Dark mode"), subtitle: root.onOff(ExLooks.dark), checked: ExLooks.dark };
        if (key === "antiFlashbang")
            return { glyph: root.antiFlashbangModel.icon, text: Translation.tr("Anti-flashbang"), subtitle: root.antiFlashbangModel.toggled ? root.antiFlashbangModel.name : Translation.tr("Off"), checked: root.antiFlashbangModel.toggled };
        if (key === "colorPicker")
            return { glyph: "colorize", text: Translation.tr("Color picker"), subtitle: "", checked: false, closes: true };
        const contributed = Plugins.quickToggle(key);
        if (contributed)
            return {
                glyph: contributed.familyIcons?.experimental ?? contributed.icon,
                text: contributed.name,
                subtitle: contributed.hasStatusText ? (contributed.statusText || root.onOff(contributed.toggled)) : "",
                checked: contributed.toggled
            };
        return { glyph: "help", text: key, subtitle: "", checked: false };
    }

    function run(key: string) {
        if (key === "wifi")
            Network.toggleWifi();
        else if (key === "bluetooth" && Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
        else if (key === "nightLight")
            Hyprsunset.toggleTemperature(!Hyprsunset.temperatureActive);
        else if (key === "doNotDisturb")
            Notifications.silent = !Notifications.silent;
        else if (key === "powerMode")
            root.nextPowerProfile();
        else if (key === "keepAwake")
            Idle.toggleInhibit();
        else if (key === "gameMode")
            root.gameModeModel.mainAction();
        else if (key === "easyEffects")
            root.easyEffectsModel.mainAction();
        else if (key === "mic")
            root.micModel.mainAction();
        else if (key === "darkMode")
            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", ExLooks.dark ? "light" : "dark", "--noswitch"]);
        else if (key === "antiFlashbang")
            root.antiFlashbangModel.mainAction();
        else if (key === "colorPicker")
            pickLater.restart();
        else
            Plugins.quickToggle(key)?.mainAction();
    }

    // Once quick settings has gone from the screen, so the colour picked is
    // not its own.
    Timer {
        id: pickLater
        interval: 300
        onTriggered: Quickshell.execDetached(["hyprpicker", "-a"])
    }
}
