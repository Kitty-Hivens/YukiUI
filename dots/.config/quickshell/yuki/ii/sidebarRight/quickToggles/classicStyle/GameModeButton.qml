import qs.core
import qs.common.widgets
import qs.core.services
import QtQuick

QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    toggled: GameMode.engaged
    onClicked: {
        GameMode.setManual(!GameMode.engaged)
    }
    StyledToolTip {
        text: Translation.tr("Game mode | Right-click to configure")
    }
}
