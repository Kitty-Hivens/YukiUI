pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.core.services

/**
 * What the window can show, in the order it offers it.
 *
 * The navigation, the window header and the home page all describe the same
 * set of pages. Written once here, they cannot drift apart, and a page added
 * below appears in all three.
 */
Singleton {
    id: root

    readonly property string homeComponent: "ii/systemSettings/HomePage.qml"
    readonly property string displaysComponent: "ii/systemSettings/DisplaysPage.qml"
    readonly property string soundComponent: "ii/systemSettings/SoundPage.qml"
    readonly property string networkComponent: "ii/systemSettings/NetworkPage.qml"
    readonly property string pluginsComponent: "ii/systemSettings/PluginsPage.qml"
    readonly property string bluetoothComponent: "ii/systemSettings/BluetoothPage.qml"
    readonly property string powerComponent: "ii/systemSettings/PowerPage.qml"
    readonly property string inputComponent: "ii/systemSettings/InputPage.qml"
    readonly property string localeComponent: "ii/systemSettings/LocalePage.qml"
    readonly property string defaultAppsComponent: "ii/systemSettings/DefaultAppsPage.qml"

    /**
     * A line of live state for one page, read only when something asks.
     *
     * A function rather than a property per page, because this catalogue is read
     * in the shell process as well: the launcher searches it. Written as
     * bindings, merely naming the catalogue there instantiated every service they
     * touch, the display service among them, which polls the compositor twice a
     * second for as long as it exists. A binding that calls this still follows
     * whatever the call read, so nothing is lost by the move.
     */
    function statusFor(key) {
        if (key === "displays") {
            const active = Displays.outputs.filter(output => !output.disabled);
            if (active.length === 1)
                return `${active[0].name} \u00b7 ${active[0].width}x${active[0].height}`;
            if (active.length > 1)
                return Translation.tr("%1 connected").arg(active.length);
            return "";
        }
        // What carries the machine online, named the way the bar names it. Not the
        // signal strength as well: that moves on its own every few seconds.
        if (key === "network") {
            if (!Network.connected)
                return Translation.tr("Not connected");
            return Network.networkName.length > 0 ? Network.networkName : Network.connectionType;
        }
        // The device sound currently goes to. Deliberately not the volume as
        // well: that changes on every scroll of the wheel.
        if (key === "sound")
            return Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : "";
        // The charge, or nothing at all on a machine that runs from the wall.
        if (key === "power") {
            if (!Battery.available)
                return "";
            const percent = Math.round(Battery.percentage * 100);
            return Battery.isCharging ? Translation.tr("%1%, charging").arg(percent) : Translation.tr("%1%").arg(percent);
        }
        // What the adapter is doing, in as few words as the row has room for. Not
        // the device names: with three connected they do not fit, and the count is
        // what the row is being scanned for anyway.
        if (key === "bluetooth") {
            if (!BluetoothStatus.available)
                return "";
            if (!BluetoothStatus.enabled)
                return Translation.tr("Off");
            const connected = BluetoothStatus.activeDeviceCount;
            if (connected === 1)
                return BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("%1 connected").arg(1);
            return connected > 0 ? Translation.tr("%1 connected").arg(connected) : Translation.tr("On");
        }
        // Read from the service the bar indicator already keeps running rather
        // than from the one the page uses, so this does not start a second reader
        // of the same two files for a line of text.
        if (key === "input")
            return HyprlandXkb.layoutCodes.join(", ");
        if (key === "plugins") {
            const total = Plugins.entries.length;
            if (total === 0)
                return "";
            return Translation.tr("%1 of %2 on").arg(Plugins.entries.filter(entry => !Plugins.isDisabled(entry.id)).length).arg(total);
        }
        return "";
    }

    /**
     * Words a page is worth finding by that are not in its name.
     *
     * One translated line per page rather than a list of terms, so a language
     * gets eight strings to translate instead of eighty, and so the headings
     * inside a page are not a second list to keep in step with this one. Never
     * shown; only matched against.
     */
    readonly property var staticGroups: [
        {
            id: "home",
            // Unnamed: the way in needs no heading above it.
            name: "",
            pages: [
                {
                    // The name is translated and the component is a path, so neither
                    // can be what a caller asks for. This is what goes in the window's
                    // environment and what the launcher's results carry.
                    key: "home",
                    name: Translation.tr("Home"),
                    icon: "home",
                    description: Translation.tr("Overview of this system"),
                    keywords: Translation.tr("About this system, overview, hostname, distro, kernel, uptime, processor, memory, RAM, swap, storage, disk"),
                    component: root.homeComponent
                }
            ]
        },
        {
            id: "hardware",
            name: Translation.tr("Hardware"),
            pages: [
                {
                    key: "displays",
                    name: Translation.tr("Displays"),
                    icon: "monitor",
                    description: Translation.tr("Arrangement, modes, colour"),
                    keywords: Translation.tr("Monitor, screen, resolution, refresh rate, scale, rotation, position, brightness, arrangement"),
                    component: root.displaysComponent
                },
                {
                    key: "sound",
                    name: Translation.tr("Sound"),
                    icon: "volume_up",
                    description: Translation.tr("Devices, applications and profiles"),
                    keywords: Translation.tr("Audio, volume, output, input, microphone, speakers, headphones, PipeWire, card, profile, playing, recording, system sounds"),
                    component: root.soundComponent
                },
                {
                    key: "input",
                    name: Translation.tr("Keyboard and input"),
                    icon: "keyboard",
                    description: Translation.tr("Layouts, key repeat and the touchpad"),
                    keywords: Translation.tr("Keyboard, layout, xkb, language switch, Caps Lock, key repeat, touchpad, scrolling, mouse"),
                    component: root.inputComponent
                },
                {
                    key: "bluetooth",
                    name: Translation.tr("Bluetooth"),
                    icon: "bluetooth",
                    description: Translation.tr("Devices, pairing and what is connected"),
                    keywords: Translation.tr("Bluetooth, pairing, headset, adapter, nearby devices"),
                    component: root.bluetoothComponent
                },
                {
                    key: "power",
                    name: Translation.tr("Power"),
                    icon: "battery_full",
                    description: Translation.tr("Battery, profile and what happens when left alone"),
                    keywords: Translation.tr("Battery, charge, profile, performance, power saver, idle, hypridle, lock screen, screen off, DPMS, suspend, sleep"),
                    component: root.powerComponent
                },
                {
                    key: "network",
                    name: Translation.tr("Network"),
                    icon: "wifi",
                    description: Translation.tr("Wi-Fi, tethering and saved connections"),
                    keywords: Translation.tr("Wi-Fi, ethernet, internet, connection, VPN, tethering, hotspot, NetworkManager, scan"),
                    component: root.networkComponent
                }
            ]
        },
        {
            // Both of these are the shell's own: what it speaks and how it writes
            // a date, and what has been added to it. Kept apart, each was a
            // heading over a single row, and three headings over seven entries is
            // a hierarchy standing in for a list.
            id: "shell",
            name: Translation.tr("Shell"),
            pages: [
                {
                    key: "locale",
                    name: Translation.tr("Language and time"),
                    icon: "translate",
                    description: Translation.tr("What the shell speaks and how it writes the date"),
                    keywords: Translation.tr("Language, locale, translation, clock, time, date format, timezone, network time, calendar"),
                    component: root.localeComponent
                },
                {
                    // Not a hardware page and not one of the shell's own, but a
                    // group for a single entry would be a heading standing in for
                    // a list. It sits with the other desktop-wide settings.
                    key: "defaults",
                    name: Translation.tr("Default applications"),
                    icon: "apps",
                    description: Translation.tr("What opens pictures, video, documents and links"),
                    keywords: Translation.tr("Default, open with, association, MIME type, handler, browser, mail, file manager, image viewer, player, editor, archive"),
                    component: root.defaultAppsComponent
                },
                {
                    key: "plugins",
                    name: Translation.tr("Extensions"),
                    icon: "extension",
                    description: Translation.tr("What is installed, what runs, and what each one is set to"),
                    keywords: Translation.tr("Plugins, extensions, add-ons, manifest, registry"),
                    component: root.pluginsComponent
                }
            ]
        }
    ]

    /**
     * Where a page goes when the plugin that brought it does not say, or names a
     * group this window does not have. The shell group is where what has been
     * added to the shell already lives.
     */
    readonly property string fallbackGroup: "shell"

    /**
     * The pages above, plus the ones installed plugins declare.
     *
     * Contributed entries carry no status line. The built-in ones read a service
     * for theirs, which is a live binding and cannot come out of an inert
     * manifest; a page that wants one will need somewhere to put a binding, and
     * that is a second contribution point rather than a field in a JSON file.
     */
    readonly property var groups: {
        const contributed = Plugins.pageEntries;
        if (contributed.length === 0)
            return root.staticGroups;
        const known = root.staticGroups.map(group => group.id);
        return root.staticGroups.map(group => {
            const extra = contributed.filter(page => {
                const wanted = known.indexOf(page.group) !== -1 ? page.group : root.fallbackGroup;
                return wanted === group.id;
            }).map(page => ({
                key: page.key,
                // Translated through the same catalogue as everything else: a
                // plugin ships English in its manifest, and a language that has
                // the string renders it, while one that does not falls back to
                // what the manifest said.
                name: Translation.tr(page.name),
                icon: page.icon,
                description: page.description.length > 0 ? Translation.tr(page.description) : "",
                keywords: page.keywords.length > 0 ? Translation.tr(page.keywords) : "",
                component: page.component
            }));
            if (extra.length === 0)
                return group;
            return { id: group.id, name: group.name, pages: group.pages.concat(extra) };
        });
    }

    /**
     * How wide a page's content is, and where its left edge sits.
     *
     * One rule, read by the window for its heading and by every page for its
     * column, so the two cannot drift apart -- which is exactly what happened
     * when the column was centred and the heading above it was not.
     */
    function contentWidth(paneWidth) {
        return Math.min(paneWidth - 40, 1180);
    }

    function contentInset(paneWidth) {
        return Math.max(20, Math.round((paneWidth - root.contentWidth(paneWidth)) / 2));
    }

    /**
     * The page a caller asked for by name, so a button elsewhere in the shell
     * can open the window where it means rather than at the front door.
     */
    function componentFor(key) {
        const wanted = (key ?? "").toLowerCase();
        for (const page of root.pages)
            if (page.key === wanted)
                return page.component;
        return root.homeComponent;
    }

    readonly property var pages: {
        const all = [];
        for (const group of root.groups)
            for (const page of group.pages)
                all.push(page);
        return all;
    }
}
