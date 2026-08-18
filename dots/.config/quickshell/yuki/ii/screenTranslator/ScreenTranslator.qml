pragma ComponentBehavior: Bound
import qs
import qs.ii
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        IiStates.screenTranslatorOpen = false
    }

    readonly property var currentScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    
    Loader {
        id: translatorLoader
        property var lockedScreen
        active: false
        Connections {
            target: IiStates
            function onScreenTranslatorOpenChanged() {
                if (!IiStates.screenTranslatorOpen) {
                    translatorLoader.active = false;
                } else {
                    translatorLoader.lockedScreen = root.currentScreen
                    translatorLoader.active = true
                }
            }
        }

        sourceComponent: ScreenTranslatorPanel {
            screen: translatorLoader.lockedScreen
            onDismiss: root.dismiss()
        }
    }

    function translate() {
        IiStates.screenTranslatorOpen = true
    }

    IpcHandler {
        target: "screenTranslator"

        function translate() {
            root.translate()
        }
    }

    GlobalShortcut {
        name: "screenTranslate"
        description: "Translates screen content"
        onPressed: root.translate()
    }
}
