pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core.services
import qs.core
import qs.core.functions
import qs.ii.systemSettings
import qs.common.widgets
import qs.common

/**
 * What language the shell speaks and how it writes the time.
 *
 * The clock formats are the shell's own; the timezone and the clock the machine
 * keeps belong to the system and are reported rather than set. Setting them
 * needs the whole zone list and an authorisation prompt, which is a page of its
 * own rather than a control tucked in here.
 */
Item {
    id: root

    property string timezone: ""
    property bool ntp: false
    property bool ntpSynced: false

    Component.onCompleted: timeFacts.running = true

    Process {
        id: timeFacts
        command: ["timedatectl", "show", "--property=Timezone", "--property=NTP", "--property=NTPSynchronized"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                text.trim().split("\n").forEach(line => {
                    const parts = line.split("=");
                    if (parts.length < 2)
                        return;
                    if (parts[0] === "Timezone")
                        root.timezone = parts[1];
                    else if (parts[0] === "NTP")
                        root.ntp = parts[1] === "yes";
                    else if (parts[0] === "NTPSynchronized")
                        root.ntpSynced = parts[1] === "yes";
                });
            }
        }
    }

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true
                icon: "language"
                title: Translation.tr("Interface language")
                subtitle: Translation.tr("Auto follows the system locale")

                StyledComboBox {
                    id: languageSelector
                    Layout.fillWidth: true
                    buttonIcon: "language"
                    textRole: "displayName"

                    model: [
                        {
                            displayName: Translation.tr("Auto (System)"),
                            value: "auto"
                        },
                        ...Translation.allAvailableLanguages.map(language => ({
                            displayName: language,
                            value: language
                        }))
                    ]

                    currentIndex: {
                        const index = languageSelector.model.findIndex(item => item.value === Config.options.language.ui);
                        return index !== -1 ? index : 0;
                    }

                    onActivated: index => {
                        Config.options.language.ui = languageSelector.model[index].value;
                    }
                }

                PageNote {
                    text: Translation.tr("A language with no file of its own falls back to English, one line at a time")
                }
            }

            PageHeading {
                text: Translation.tr("Clock")
            }

            SystemCard {
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.time.format
                    onSelected: newValue => {
                        // The lock screen reads its own config rather than this one,
                        // so the twelve-hour switch has to be made there as well or
                        // the two clocks disagree.
                        if (newValue === "hh:mm") {
                            Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                        } else {
                            Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                        }
                        Config.options.time.format = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("24h"),
                            value: "hh:mm"
                        },
                        {
                            displayName: Translation.tr("12h am/pm"),
                            value: "h:mm ap"
                        },
                        {
                            displayName: Translation.tr("12h AM/PM"),
                            value: "h:mm AP"
                        }
                    ]
                }

                ConfigSwitch {
                    id: secondsSwitch
                    text: Translation.tr("Second precision")
                    buttonIcon: "pace"
                    Binding {
                        target: secondsSwitch
                        property: "checked"
                        value: Config.options.time.secondPrecision
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== Config.options.time.secondPrecision)
                            Config.options.time.secondPrecision = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Enable if you want clocks to show seconds accurately")
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Dates")
            }

            SystemCard {
                Layout.fillWidth: true
                subtitle: Translation.tr("Written the way Qt writes dates: dd day, MM month, yyyy year, ddd weekday")

                ContentSubsection {
                    title: Translation.tr("With the weekday")
                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.time.dateFormat
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.time.dateFormat = text
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Short")
                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.time.shortDateFormat
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.time.shortDateFormat = text
                    }
                }
                ContentSubsection {
                    title: Translation.tr("With the year")
                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.time.dateWithYearFormat
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.time.dateWithYearFormat = text
                    }
                }
                ContentSubsection {
                    // Which day the week starts on and how months are named comes
                    // from here, not from the formats above.
                    title: Translation.tr("Calendar locale")
                    MaterialTextArea {
                        Layout.fillWidth: true
                        text: Config.options.calendar.locale
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: Config.options.calendar.locale = text
                    }
                }
            }

            PageHeading {
                text: Translation.tr("System clock")
            }

            SystemCard {
                Layout.fillWidth: true

                FactRow {
                    label: Translation.tr("Timezone")
                    value: root.timezone
                }
                FactRow {
                    label: Translation.tr("Network time")
                    value: !root.ntp ? Translation.tr("Off")
                        : root.ntpSynced ? Translation.tr("On, in step")
                        : Translation.tr("On, not in step yet")
                }

                PageNote {
                    text: Translation.tr("Reported, not set: changing these asks the system for permission and needs the whole zone list, which is a page of its own")
                }
            }

            PageHeading {
                text: Translation.tr("Generate translation with Gemini")
            }

            SystemCard {
                Layout.fillWidth: true
                subtitle: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextArea {
                        id: localeInput
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                        text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                    }
                    RippleButtonWithIcon {
                        Layout.fillHeight: true
                        nerdIcon: ""
                        enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                        mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                        onClicked: {
                            translationProc.locale = localeInput.text.trim();
                            translationProc.running = false;
                            translationProc.running = true;
                        }
                    }
                }
            }
        }
    }
}
