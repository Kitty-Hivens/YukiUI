pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services
import qs.blueberry.looks

// The language the shell speaks, how it writes the time and the date, and the
// zone and the network time the machine keeps. The last two belong to the
// system: setting them goes through timedated, which asks for a password.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    property string timezone: ""
    property bool ntp: false
    property bool ntpSynced: false
    property var zones: []

    readonly property var languages: ["auto", ...Translation.allAvailableLanguages]
    readonly property var clockFormats: [
        { value: "hh:mm", text: Translation.tr("24h") },
        { value: "h:mm ap", text: Translation.tr("12h am/pm") },
        { value: "h:mm AP", text: Translation.tr("12h AM/PM") }
    ]
    readonly property date now: clock.date

    function languageName(code: string): string {
        if (code === "auto")
            return Translation.tr("Auto (System)");
        const native = Qt.locale(code).nativeLanguageName;
        return native.length > 0 ? `${native.charAt(0).toUpperCase()}${native.slice(1)}  ·  ${code}` : code;
    }

    function example(format: string): string {
        return Translation.tr("Now: %1").arg(Qt.locale().toString(root.now, format));
    }

    Component.onCompleted: {
        facts.running = true;
        zoneList.running = true;
    }

    spacing: ExLooks.spacing.s

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: facts
        command: ["timedatectl", "show", "--property=Timezone", "--property=NTP", "--property=NTPSynchronized"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.trim().split("\n")) {
                    const at = line.indexOf("=");
                    if (at < 0)
                        continue;
                    const key = line.slice(0, at);
                    const value = line.slice(at + 1);
                    if (key === "Timezone")
                        root.timezone = value;
                    else if (key === "NTP")
                        root.ntp = value === "yes";
                    else if (key === "NTPSynchronized")
                        root.ntpSynced = value === "yes";
                }
            }
        }
    }
    Process {
        id: zoneList
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: root.zones = text.trim().split("\n").filter(zone => zone.length > 0)
        }
    }
    // Read again once timedated has answered, whether it did what was asked or
    // the password was refused.
    Process {
        id: change
        onExited: {
            facts.running = false;
            facts.running = true;
        }
    }

    // A date written the way Qt writes one, with what it comes out as now.
    component DateFormatCard: SettingsCard {
        id: dateCard

        property string format
        signal changed(string format)

        Layout.fillWidth: true
        description: root.example(dateCard.format)

        ExTextField {
            id: field
            width: 220
            text: dateCard.format

            Connections {
                target: field.input
                function onEditingFinished() {
                    if (field.text.trim().length > 0 && field.text !== dateCard.format)
                        dateCard.changed(field.text);
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Language")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "language"
            text: Translation.tr("Interface language")
            description: Translation.tr("A language with no file of its own falls back to English, one line at a time")

            SettingsDropdown {
                model: root.languages.map(code => root.languageName(code))
                currentIndex: Math.max(0, root.languages.indexOf(Config.options.language.ui))
                onActivated: index => Config.options.language.ui = root.languages[index]
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Time and date")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "schedule"
            text: Translation.tr("Clock")
            description: root.example(Config.options.time.format)

            SettingsChoice {
                value: Config.options.time.format
                options: root.clockFormats
                onPicked: format => Config.options.time.format = format
            }
        }
        DateFormatCard {
            glyph: "calendar_today"
            text: Translation.tr("Short")
            format: Config.options.time.shortDateFormat
            onChanged: format => Config.options.time.shortDateFormat = format
        }
        DateFormatCard {
            glyph: "event"
            text: Translation.tr("With the weekday")
            format: Config.options.time.dateFormat
            onChanged: format => Config.options.time.dateFormat = format
        }
        DateFormatCard {
            glyph: "calendar_month"
            text: Translation.tr("With the year")
            format: Config.options.time.dateWithYearFormat
            onChanged: format => Config.options.time.dateWithYearFormat = format
        }
        ExText {
            Layout.fillWidth: true
            Layout.leftMargin: ExLooks.spacing.l
            text: Translation.tr("Written the way Qt writes dates: dd day, MM month, yyyy year, ddd weekday")
            role: "caption"
            dim: true
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("System clock")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "public"
            text: Translation.tr("Timezone")

            SettingsDropdown {
                enabled: root.zones.length > 0 && !change.running
                model: root.zones
                currentIndex: root.zones.indexOf(root.timezone)
                onActivated: index => {
                    change.command = ["timedatectl", "set-timezone", root.zones[index]];
                    change.running = true;
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "sync"
            text: Translation.tr("Set the time automatically")
            description: !root.ntp ? Translation.tr("Off")
                : root.ntpSynced ? Translation.tr("On, in step")
                : Translation.tr("On, not in step yet")

            ExSwitch {
                enabled: !change.running
                checked: root.ntp
                // Back on what the system says, which the reading after the
                // change brings: a refused change, the password prompt
                // cancelled say, left the switch where the finger put it.
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.ntp);
                    change.command = ["timedatectl", "set-ntp", wanted ? "true" : "false"];
                    change.running = true;
                }
            }
        }
    }
}
