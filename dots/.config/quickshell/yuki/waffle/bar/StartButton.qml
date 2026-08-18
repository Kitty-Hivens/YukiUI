import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.waffle.looks
import qs.waffle

// TODO: Replace the icon with QMLized svg (with /usr/lib/qt6/bin/svgtoqml) for proper micro-animation
AppButton {
    id: root

    leftInset: Config.options.waffles.bar.leftAlignApps ? 12 : 0
    iconName: down ? "start-here-pressed" : "start-here"

    checked: WStates.searchOpen
    onClicked: {
        WStates.searchOpen = !WStates.searchOpen;
    }

    BarToolTip {
        id: tooltip
        text: Translation.tr("Start")
        extraVisibleCondition: root.shouldShowTooltip
    }

    altAction: () => {
        contextMenu.active = true;
    }

    BarMenu {
        id: contextMenu

        model: [
            {
                text: Translation.tr("Terminal"),
                action: () => {
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.terminal]);
                }
            },
            {
                text: Translation.tr("Task Manager"),
                action: () => {
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.taskManager]);
                }
            },
            {
                text: Translation.tr("File Explorer"),
                action: () => {
                    Qt.openUrlExternally(Directories.home);
                }
            },
            {
                text: Translation.tr("Search"),
                action: () => {
                    WStates.searchPanelOpen = true;
                }
            },
        ]
    }
}
