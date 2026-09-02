import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common.widgets.widgetCanvas
import qs.common
import qs.ii

Item {
    id: root
    focus: true
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true

    Keys.onPressed: (event) => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            IiStates.overlayOpen = false;
        }
    }

    property real initScale: Config.options.overlay.openingZoomAnimation ? 1.08 : 1.000001
    scale: initScale
    Component.onCompleted: {
        scale = 1
    }
    Behavior on scale {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Appearance.colors.colScrim
        visible: Config.options.overlay.darkenScreen && opacity > 0
        opacity: (IiStates.overlayOpen && root.scale !== initScale) ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    WidgetCanvas {
        anchors.fill: parent
        onClicked: IiStates.overlayOpen = false

        OverlayTaskbar {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 50
            }
        }

        Repeater {
            model: ScriptModel {
                // An identifier the saved state still names but this build no
                // longer has resolves to nothing, and an empty row reaches the
                // model as a value that compares equal to every other empty one.
                values: Persistent.states.overlay.open
                    .map(identifier => OverlayContext.availableWidgets.find(w => w.identifier === identifier))
                    .filter(widget => widget !== undefined)
                objectProp: "identifier"
            }
            delegate: OverlayWidgetDelegateChooser {
                
            }
        }
    }
}
