pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property Component contentComponent
    
    Loader {
        active: PolkitService.active
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: PanelWindow {
                id: panelWindow
                required property var modelData
                screen: modelData
                
                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                color: "transparent"
                WlrLayershell.namespace: "quickshell:polkit"
                // Taken, not asked for on demand. A fullscreen window does not
                // give focus up to a layer that only asks when clicked, and
                // while it holds focus it holds the pointer locked to itself,
                // so the click that would hand focus over never arrives. This
                // is a password prompt: unable to take focus it cannot be
                // answered at all, and the request expires on its own.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.layer: WlrLayer.Overlay
                exclusionMode: ExclusionMode.Ignore

                // One prompt per screen, each taking focus, so each gives it
                // back under a name of its own.
                readonly property string focusOwner: `polkit:${panelWindow.modelData.name}`
                Component.onCompleted: FocusReturn.remember(panelWindow.focusOwner)
                Component.onDestruction: FocusReturn.restore(panelWindow.focusOwner)

                Loader {
                    anchors.fill: parent
                    sourceComponent: root.contentComponent
                }
            }
        }
    }
}
