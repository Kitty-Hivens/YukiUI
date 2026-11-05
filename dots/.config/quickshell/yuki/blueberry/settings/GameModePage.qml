pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services
import qs.blueberry.looks

// When the machine gives itself over to a game, and what that takes. All of it is
// config the shell's GameMode service follows. That service is not used from here:
// this window is a process of its own, and a second copy would hold a second
// governor session and write over the guard's state file.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    readonly property var mode: Config.options.gameMode
    readonly property var guard: Config.options.gameMode.guard

    /** Feral's gamemode is there to be held. */
    property bool gamemodeInstalled: true
    /** The unit that does the guarding: "active", "inactive" or "missing". */
    property string guardUnit: "active"

    function readGuardUnit() {
        guardReader.running = true;
    }

    Component.onCompleted: {
        gamemodeFinder.running = true;
        root.readGuardUnit();
    }

    spacing: ExLooks.settings.groupGap

    Process {
        id: gamemodeFinder
        command: ["which", "gamemoderun"]
        onExited: exitCode => root.gamemodeInstalled = exitCode === 0
    }
    Process {
        id: guardReader
        command: ["systemctl", "--user", "show", "--property=LoadState,ActiveState", "--value", "yuki-game-guard.service"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.guardUnit = lines[0] !== "loaded" ? "missing" : lines[1] === "active" ? "active" : "inactive";
            }
        }
    }
    Process {
        id: guardStarter
        command: ["systemctl", "--user", "start", "yuki-game-guard.service"]
        onExited: root.readGuardUnit()
    }

    SettingsHero {
        Layout.fillWidth: true
        on: root.mode.active
        glyph: "stadia_controller"
        text: root.mode.active ? Translation.tr("Turned on") : Translation.tr("Turned off")
        subtitle: !root.mode.active && root.mode.autoOnFullscreen ? Translation.tr("Comes on by itself for a fullscreen window") : ""
        onSwitched: wanted => Config.options.gameMode.active = wanted
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("When")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "fit_screen"
            text: Translation.tr("While a window is fullscreen")
            description: Translation.tr("A game or a video")

            ExSwitch {
                checked: root.mode.autoOnFullscreen
                onToggled: Config.options.gameMode.autoOnFullscreen = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("What it does")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "blur_off"
            text: Translation.tr("Drop the effects")
            description: Translation.tr("No animations, blur, shadows, rounding or gaps")

            ExSwitch {
                checked: root.mode.visual
                onToggled: Config.options.gameMode.visual = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.gamemodeInstalled
            glyph: "developer_board"
            text: Translation.tr("Hold the processor at full speed")
            description: root.gamemodeInstalled ? Translation.tr("Through Feral GameMode") : Translation.tr("gamemode is not installed")

            ExSwitch {
                checked: root.mode.system && root.gamemodeInstalled
                onToggled: Config.options.gameMode.system = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "motion_photos_paused"
            text: Translation.tr("Pause a video wallpaper")

            ExSwitch {
                checked: root.mode.wallpaper
                onToggled: Config.options.gameMode.wallpaper = checked
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Resource guard")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "shield"
            text: Translation.tr("Keep programs off the game's resources")
            description: Translation.tr("Closes or pauses other programs while the mode is on")

            ExSwitch {
                checked: root.guard.enable
                onToggled: Config.options.gameMode.guard.enable = checked
            }
        }
        // Said out loud rather than left to be found: the switch above does
        // nothing without the unit.
        SettingsCard {
            Layout.fillWidth: true
            visible: root.guard.enable && root.guardUnit !== "active"
            glyph: "error"
            text: root.guardUnit === "missing" ? Translation.tr("The guard is not installed") : Translation.tr("The guard is not running")

            ExButton {
                visible: root.guardUnit === "inactive"
                kind: "accent"
                text: Translation.tr("Start it")
                onClicked: guardStarter.running = true
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.guard.enable
            glyph: "memory"
            text: Translation.tr("Close on low memory")
            description: Translation.tr("The largest program that is not the game")

            ExSwitch {
                checked: root.guard.killOnMemory
                onToggled: Config.options.gameMode.guard.killOnMemory = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.guard.enable
            glyph: "pause_circle"
            text: Translation.tr("Pause on a busy processor")
            description: Translation.tr("The greediest one, until the game is over")

            ExSwitch {
                checked: root.guard.freezeOnCpu
                onToggled: Config.options.gameMode.guard.freezeOnCpu = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.guard.enable
            glyph: "low_priority"
            text: Translation.tr("Put the game last for the kernel's killer")

            ExSwitch {
                checked: root.guard.raiseOomScores
                onToggled: Config.options.gameMode.guard.raiseOomScores = checked
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.guard.enable
            glyph: "verified_user"
            text: Translation.tr("Never touch")
            description: Translation.tr("Program names, separated by commas")

            ExTextField {
                id: keepField
                width: 280
                text: root.guard.keep.join(", ")

                Connections {
                    target: keepField.input
                    function onEditingFinished() {
                        const names = keepField.text.split(",").map(name => name.trim()).filter(name => name.length > 0);
                        if (names.join(",") !== [...root.guard.keep].join(","))
                            Config.options.gameMode.guard.keep = names;
                    }
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.guard.enable
            glyph: "edit_note"
            text: Translation.tr("Only write down what it would do")
            description: Translation.tr("Nothing is closed or paused")

            ExSwitch {
                checked: root.guard.dryRun
                onToggled: Config.options.gameMode.guard.dryRun = checked
            }
        }
    }
}
