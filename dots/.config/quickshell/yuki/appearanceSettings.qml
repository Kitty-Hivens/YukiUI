//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common

ApplicationWindow {
    id: root
    property real contentPadding: 8
    // Which desktop these settings belong to.
    //
    // Bound rather than told, the way a panel decides whether to be on screen at
    // all: the bar reads the fullscreen state and unmaps itself, and this reads
    // the family and closes itself. Nothing owns this window. It is a shell process
    // of its own, and a process cannot be held by the object tree that
    // asked for it, because a reload destroys that tree without the desktop
    // having changed at all.
    //
    // Only on a change: a window someone started by hand while another desktop
    // is up was asked for on purpose, and refusing to open is not this rule's
    // business. Leaving through close() rather than quitting, so whatever the
    // window still owes (a display layout waiting to be confirmed) is settled by
    // onClosing on the way out.
    readonly property bool mine: Config.options?.panelFamily === "ii"
    onMineChanged: if (!root.mine) root.close()
    readonly property var pages: [
        { name: Translation.tr("Quick"), icon: "instant_mix", component: "ii/settings/QuickConfig.qml" },
        { name: Translation.tr("General"), icon: "browse", component: "ii/settings/GeneralConfig.qml" },
        { name: Translation.tr("Bar"), icon: "toast", iconRotation: 180, component: "ii/settings/BarConfig.qml" },
        { name: Translation.tr("Background"), icon: "texture", component: "ii/settings/BackgroundConfig.qml" },
        { name: Translation.tr("Interface"), icon: "bottom_app_bar", component: "ii/settings/InterfaceConfig.qml" },
        { name: Translation.tr("Services"), icon: "settings", component: "ii/settings/ServicesConfig.qml" },
        { name: Translation.tr("Advanced"), icon: "construction", component: "ii/settings/AdvancedConfig.qml" },
        { name: Translation.tr("System"), icon: "info", component: "ii/settings/About.qml" }
    ]
    property int currentPage: 0

    visible: true
    onClosing: Qt.quit()
    // Hyprland floats this window by matching the exact title (rules.lua) -- keep it
    // hardcoded, never bind to a translated string.
    title: "YukiUI Appearance"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleRow.implicitHeight, windowControlsRow.implicitHeight)
            RowLayout {
                id: titleRow
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                spacing: 8
                MaterialSymbol {
                    text: "format_paint"
                    iconSize: Appearance.font.pixelSize.title
                    color: Appearance.colors.colOnLayer0
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    id: titleText
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Appearance")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 150 : fab.baseSize
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                NavigationRail { // Window content with navigation rail and content pane
                    id: navRail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 900
                    
                    NavigationRailExpandButton {
                        focus: root.visible
                    }

                    FloatingActionButton {
                        id: fab
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`file://${Directories.shellConfigPath}`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = Directories.shellConfigPath;
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: {
                                fab.justCopied = false;
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 15
                        spacing: 0
                        Repeater {
                            model: root.pages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                Layout.fillWidth: true
                                toggled: root.currentPage === index
                                onPressed: root.currentPage = index
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation || 0
                                buttonText: modelData.name
                            }
                        }
                    }

                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pages[0].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
