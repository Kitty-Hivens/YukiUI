import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import qs
import qs.core.services
import qs.core
import qs.waffle.looks
import qs.waffle

AppButton {
    id: root

    iconName: (down && !checked) ? "task-view-pressed" : "task-view"
    pressedScale: checked ? 5/6 : 1
    separateLightDark: true

    checked: WStates.overviewOpen
    onClicked: {
        WStates.overviewOpen = !WStates.overviewOpen;
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip
        text: Translation.tr("Task View") // Should be a preview of workspaces, but we'll have this for now...
    }
}
