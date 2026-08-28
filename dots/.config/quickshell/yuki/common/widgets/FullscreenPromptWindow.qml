pragma ComponentBehavior: Bound
import qs.core.services
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * A question the session has to answer before it goes on with anything else.
 *
 * One window per screen, over everything, taking focus rather than asking for
 * it -- a prompt that cannot be typed into cannot be answered, and the request
 * behind it expires on its own while nobody can reach it.
 */
Scope {
    id: root

    /** Whether there is anything to answer right now. */
    required property bool active
    /** The screen drawn inside each window. */
    required property Component contentComponent
    /**
     * What the layer is called, and what each window files its focus under.
     * Rules elsewhere match on the first, so it is identity rather than writing.
     */
    required property string name

    Loader {
        active: root.active
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
                WlrLayershell.namespace: `quickshell:${root.name}`
                // Taken, not asked for on demand. A fullscreen window does not
                // give focus up to a layer that only asks when clicked, and
                // while it holds focus it holds the pointer locked to itself,
                // so the click that would hand focus over never arrives.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.layer: WlrLayer.Overlay
                exclusionMode: ExclusionMode.Ignore

                // One prompt per screen, each taking focus, so each gives it
                // back under a name of its own.
                readonly property string focusOwner: `${root.name}:${panelWindow.modelData.name}`
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
