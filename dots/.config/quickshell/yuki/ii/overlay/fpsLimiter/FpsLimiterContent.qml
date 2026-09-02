import qs.core.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.core
import qs.common.widgets
import qs.ii.overlay

OverlayBackground {
    id: root

    enum State { Normal, Success, Error }

    property real padding: 16
    property var currentState: FpsLimiterContent.State.Normal
    implicitWidth: content.implicitWidth + (padding * 2)
    implicitHeight: content.implicitHeight + (padding * 2)

    Timer {
        id: iconResetTimer
        interval: 1000
        onTriggered: {
            root.currentState = FpsLimiterContent.State.Normal;
        }
    }

    function applyLimit() {
        var fpsValue = parseInt(fpsField.text);
        if (isNaN(fpsValue) || fpsValue < 0) {
            root.currentState = FpsLimiterContent.State.Error;
            iconResetTimer.restart();
            fpsField.text = "";
            return;
        }

        // MangoHud's config directory does not exist until MangoHud itself has
        // written something there, and it is wherever XDG says rather than a
        // literal ~/.config -- appending a line to a file in a directory that is
        // not there is how this wrote nothing at all and said it had worked.
        fpsSetter.command = ["bash", "-c",
            'cfg="${XDG_CONFIG_HOME:-$HOME/.config}/MangoHud/MangoHud.conf"; ' +
            'mkdir -p "$(dirname "$cfg")" && touch "$cfg" || exit 1; ' +
            'if grep -q "^fps_limit=" "$cfg"; ' +
            `then sed -i "s/^fps_limit=.*/fps_limit=${fpsValue}/" "$cfg"; ` +
            `else printf "fps_limit=%s\\n" "${fpsValue}" >> "$cfg"; fi`];
        fpsSetter.running = true;

        // Clear the field after applying
        fpsField.text = "";
    }

    Process {
        id: fpsSetter
        /**
         * Waited on rather than detached, and no longer signalled afterwards.
         *
         * The tick used to be drawn the moment the command was handed over, so it
         * said the limit had been written whether or not anything had been. The
         * command that followed the write was `pkill -SIGUSR2 mangohud`, which
         * could never reach the HUD: it lives inside the game's own process
         * through LD_PRELOAD, `mangohud` on PATH is a shell wrapper, and the
         * library installs no handler for that signal -- so the one process the
         * pattern could ever have matched would have been killed by it. The limit
         * is read when a game starts, and that is when it now takes effect.
         */
        onExited: (exitCode, exitStatus) => {
            root.currentState = exitCode === 0 ? FpsLimiterContent.State.Success : FpsLimiterContent.State.Error;
            iconResetTimer.restart();
        }
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 4

        ToolbarTextField {
            id: fpsField
            Layout.fillWidth: true
            Layout.preferredWidth: 200
            placeholderText: root.currentState === FpsLimiterContent.State.Error ? Translation.tr("Enter a valid number") : Translation.tr("Set FPS limit")
            inputMethodHints: Qt.ImhDigitsOnly
            focus: true

            onAccepted: {
                root.applyLimit();
            }
        }

        IconToolbarButton {
            id: applyButton
            text: switch (root.currentState) {
                case FpsLimiterContent.State.Error: return "close";
                case FpsLimiterContent.State.Success: return "check";
                case FpsLimiterContent.State.Normal:
                default: return "save";
            }
            enabled: root.currentState === FpsLimiterContent.State.Normal && fpsField.text.length > 0
            onClicked: {
                root.applyLimit();
            }
        }
    }
}
