import qs.core.services
import qs.core
import qs.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.ii.sidebarRight.quickToggles.classicStyle
import qs.common

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        color: Appearance.colors.colLayer1

        NetworkToggle {
            altAction: () => {
                root.openWifiDialog();
            }
        }
        BluetoothToggle {
            altAction: () => {
                root.openBluetoothDialog();
            }
        }
        NightLight {}
        GameModeButton {
            altAction: () => {
                root.openGameModeDialog();
            }
        }
        IdleInhibitor {}
        EasyEffectsToggle {}

        // Whatever the installed plugins offer, after what the family brings
        // itself. Nothing here names any of them.
        Repeater {
            model: Plugins.quickToggleIds
            delegate: ContributedToggle {
                required property string modelData
                toggleModel: Plugins.quickToggle(modelData)
            }
        }
    }
}
