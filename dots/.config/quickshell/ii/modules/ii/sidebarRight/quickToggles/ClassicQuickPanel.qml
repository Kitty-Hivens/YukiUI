import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

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
        GameMode {
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
