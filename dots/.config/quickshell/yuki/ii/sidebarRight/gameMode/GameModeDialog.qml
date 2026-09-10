import qs.core
import qs.common.widgets
import qs.core.services
import qs.common
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root
    backgroundHeight: 500

    WindowDialogTitle {
        text: Translation.tr("Game mode")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    Column {
        Layout.topMargin: -16
        Layout.fillWidth: true
        Layout.fillHeight: true

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "stadia_controller"
            text: Translation.tr("Enable now")
            checked: GameMode.engaged
            onCheckedChanged: GameMode.setManual(checked)
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "blur_on"
            text: Translation.tr("Visual performance")
            checked: Config.options.gameMode.visual
            onCheckedChanged: Config.options.gameMode.visual = checked
            StyledToolTip { text: Translation.tr("No animations, blur, shadows, rounding or gaps") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "developer_board"
            text: Translation.tr("System GameMode")
            checked: Config.options.gameMode.system
            onCheckedChanged: Config.options.gameMode.system = checked
            StyledToolTip { text: Translation.tr("Hold a Feral GameMode session (CPU performance governor)") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "motion_photos_paused"
            text: Translation.tr("Pause wallpaper")
            checked: Config.options.gameMode.wallpaper
            onCheckedChanged: Config.options.gameMode.wallpaper = checked
            StyledToolTip { text: Translation.tr("Freeze the video wallpaper on its last frame") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "fit_screen"
            text: Translation.tr("Auto on fullscreen")
            checked: Config.options.gameMode.autoOnFullscreen
            onCheckedChanged: Config.options.gameMode.autoOnFullscreen = checked
            StyledToolTip { text: Translation.tr("Engage automatically while a window is fullscreen") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "shield"
            text: Translation.tr("Resource guard")
            checked: Config.options.gameMode.guard.enable
            onCheckedChanged: Config.options.gameMode.guard.enable = checked
            StyledToolTip { text: Translation.tr("Close or pause whatever takes memory and cores away from the game") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            enabled: Config.options.gameMode.guard.enable
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "memory"
            text: Translation.tr("Close on low memory")
            checked: Config.options.gameMode.guard.killOnMemory
            onCheckedChanged: Config.options.gameMode.guard.killOnMemory = checked
            StyledToolTip { text: Translation.tr("Ask the largest program that is not the game to close, then kill it") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            enabled: Config.options.gameMode.guard.enable
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "pause_circle"
            text: Translation.tr("Pause on CPU contention")
            checked: Config.options.gameMode.guard.freezeOnCpu
            onCheckedChanged: Config.options.gameMode.guard.freezeOnCpu = checked
            StyledToolTip { text: Translation.tr("Stop the greediest program while the game waits for a core, and start it again afterwards") }
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
