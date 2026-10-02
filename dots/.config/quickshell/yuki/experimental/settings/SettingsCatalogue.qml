import QtQuick

import qs.core.services

/**
 * What the settings hold, the way Windows 11 lays it out: categories in the
 * navigation, and in each one the pages it leads to.
 *
 * A category with pages opens on a list of them. A page with a component opens
 * that page. Keywords are what search matches besides the names.
 */
QtObject {
    id: root

    readonly property var categories: [
        {
            key: "home",
            name: Translation.tr("Home"),
            glyph: "home",
            component: "HomePage.qml",
            pages: []
        },
        {
            key: "system",
            name: Translation.tr("System"),
            glyph: "computer",
            pages: [
                { key: "display", name: Translation.tr("Display"), glyph: "desktop_windows", description: Translation.tr("Screens, resolution, scale"), keywords: "monitor screen resolution scale refresh brightness night light hdr vrr rotation", component: "DisplayPage.qml" },
                { key: "sound", name: Translation.tr("Sound"), glyph: "volume_up", description: Translation.tr("Output, input, volume"), keywords: "audio volume speaker microphone mixer", component: "SoundPage.qml" },
                { key: "notifications", name: Translation.tr("Notifications"), glyph: "notifications", description: Translation.tr("Do not disturb, what is kept"), keywords: "alerts do not disturb", component: "NotificationsPage.qml" },
                { key: "power", name: Translation.tr("Power"), glyph: "bolt", description: Translation.tr("Power mode, battery, keeping awake"), keywords: "battery sleep power profile idle lock suspend", component: "PowerPage.qml" },
                { key: "multitasking", name: Translation.tr("Multitasking"), glyph: "select_window", description: Translation.tr("Snap, switching between windows"), keywords: "alt tab switch windows snap maximize", component: "MultitaskingPage.qml" }
            ]
        },
        {
            key: "devices",
            name: Translation.tr("Bluetooth and devices"),
            glyph: "bluetooth",
            pages: [
                { key: "bluetooth", name: Translation.tr("Bluetooth"), glyph: "bluetooth", description: Translation.tr("Pair and connect devices"), keywords: "pair headphones", component: "BluetoothPage.qml" },
                { key: "keyboard", name: Translation.tr("Keyboard"), glyph: "keyboard", description: Translation.tr("Layouts and typing"), keywords: "layout language input caps repeat", component: "KeyboardPage.qml" },
                { key: "mouse", name: Translation.tr("Mouse and touchpad"), glyph: "mouse", description: Translation.tr("Pointer speed, scrolling"), keywords: "pointer touchpad scroll speed", component: "MousePage.qml" }
            ]
        },
        {
            key: "network",
            name: Translation.tr("Network and internet"),
            glyph: "wifi",
            pages: [
                { key: "wifi", name: Translation.tr("Wi-Fi"), glyph: "wifi", description: Translation.tr("Networks nearby, saved networks"), keywords: "wireless network internet password", component: "WifiPage.qml" },
                { key: "connections", name: Translation.tr("Connections"), glyph: "lan", description: Translation.tr("Wired, VPN, tethering"), keywords: "ethernet vpn tether wireguard openvpn", component: "ConnectionsPage.qml" }
            ]
        },
        {
            key: "personalization",
            name: Translation.tr("Personalization"),
            glyph: "palette",
            pages: [
                { key: "background", name: Translation.tr("Background"), glyph: "wallpaper", description: Translation.tr("The picture behind the windows"), keywords: "wallpaper image picture", component: "BackgroundPage.qml" },
                { key: "colors", name: Translation.tr("Colors"), glyph: "contrast", description: Translation.tr("Light or dark"), keywords: "dark light theme mode accent", component: "ColorsPage.qml" },
                { key: "dock", name: Translation.tr("Dock"), glyph: "dock_to_bottom", description: Translation.tr("Edge, style, alignment"), keywords: "taskbar panel edge", component: "DockPage.qml" },
                { key: "desktop", name: Translation.tr("Desktop"), glyph: "desktop_mac", description: Translation.tr("Icons on the desktop"), keywords: "icons sort size", component: "DesktopPage.qml" }
            ]
        },
        {
            key: "apps",
            name: Translation.tr("Apps"),
            glyph: "apps",
            pages: [
                { key: "defaults", name: Translation.tr("Default applications"), glyph: "star", description: Translation.tr("What opens links and files"), keywords: "browser mime open with file types", component: "DefaultAppsPage.qml" },
                { key: "extensions", name: Translation.tr("Extensions"), glyph: "extension", description: Translation.tr("Plugins of the shell"), keywords: "plugins", component: "ExtensionsPage.qml" }
            ]
        },
        {
            key: "time",
            name: Translation.tr("Time and language"),
            glyph: "schedule",
            pages: [
                { key: "language", name: Translation.tr("Language and time"), glyph: "translate", description: Translation.tr("Language of the shell, time format"), keywords: "locale clock date timezone ntp format", component: "LanguagePage.qml" }
            ]
        }
    ]

    /** Every page, each with the category it belongs to. */
    readonly property var pages: {
        const all = [];
        for (const category of root.categories)
            for (const page of category.pages)
                all.push(Object.assign({ category: category.key }, page));
        return all;
    }

    function category(key: string): var {
        return root.categories.find(category => category.key === key) ?? null;
    }

    function page(key: string): var {
        return root.pages.find(page => page.key === key) ?? null;
    }

    /** Pages whose name, description or keywords hold every word typed. */
    function search(text: string): var {
        const words = text.toLowerCase().split(/\s+/).filter(word => word.length > 0);
        if (words.length === 0)
            return [];
        return root.pages.filter(page => {
            const haystack = `${page.name} ${page.description} ${page.keywords}`.toLowerCase();
            return words.every(word => haystack.includes(word));
        });
    }
}
