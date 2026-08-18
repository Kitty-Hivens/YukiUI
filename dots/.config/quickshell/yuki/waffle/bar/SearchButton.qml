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

    iconName: checked ? "system-search-checked" : "system-search"
    separateLightDark: true

    checked: WStates.searchPanelOpen
    onClicked: {
        WStates.searchPanelOpen = !WStates.searchPanelOpen;
    }

    BarToolTip {
        id: tooltip
        text: Translation.tr("Search")
        extraVisibleCondition: root.shouldShowTooltip
    }
}
