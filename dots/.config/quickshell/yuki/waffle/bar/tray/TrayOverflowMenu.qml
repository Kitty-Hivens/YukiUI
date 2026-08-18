pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar
import qs.modules.waffle.bar.tray

BarPopup {
    id: root

    closeOnFocusLost: false
    onFocusCleared: {
        const hasMenuOpen = contentItem.children.some(c => (c.menuOpen));
        if (!hasMenuOpen)
            root.close();
        else
            root.grabFocus();
    }

    contentItem: Item {
        id: contentItem
        anchors.centerIn: parent
        // 4 around the grid: measured, the flyout is 48 across one 40 cell and 88
        // across two.
        readonly property int gridPadding: 4
        implicitWidth: contentGrid.implicitWidth + contentItem.gridPadding * 2
        implicitHeight: contentGrid.implicitHeight + contentItem.gridPadding * 2
        GridLayout {
            id: contentGrid
            anchors.centerIn: parent
            rows: Math.max(1, Math.floor(Math.sqrt(TrayService.unpinnedItems.length)))
            columns: Math.max(1, Math.ceil(TrayService.unpinnedItems.length / rows))
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: ScriptModel {
                    values: TrayService.unpinnedItems
                    onValuesChanged: {
                        root.updateAnchor();
                        if (values.length === 0) {
                            root.close();
                        }
                    }
                }
                delegate: TrayButton {
                    id: trayButton
                    required property var modelData
                    item: modelData

                    topInset: 0
                    bottomInset: 0
                    implicitWidth: 40
                    implicitHeight: 40

                    colBackground: ColorUtils.transparentize(Looks.colors.bg2)
                    colBackgroundHover: Looks.colors.bg2Hover
                    colBackgroundActive: Looks.colors.bg2Active

                    onMenuOpenChanged: {
                        // The overflow menu should only be closed when the user clicks outside
                        // However the focus grab refuses to reactivate, so we can't have that
                        // But most of the time the user dismisses the menu by clicking outside anyway,
                        // so this is acceptable.
                        if (!menuOpen) {
                            root.close();
                        }
                    }

                    readonly property bool carrying: TrayDragState.item === trayButton.item
                    opacity: trayButton.carrying ? 0.35 : 1
                    Behavior on opacity {
                        animation: Looks.transition.opacity.createObject(this)
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent

                        property point pressedAt
                        property bool moved: false

                        /// The layer that draws a carried icon stands beside the bar, so
                        /// it speaks the bar window's coordinates and this one does not.
                        /// The flyout hangs off the chevron, though, and the chevron can
                        /// be located in both spaces -- the difference between the two is
                        /// the shift between the windows.
                        function inBarSpace(x, y) {
                            const here = dragArea.mapToItem(null, x, y);
                            const anchorHere = trayButton.QsWindow.mapFromItem(root.anchorItem, 0, 0);
                            const anchorThere = root.anchorItem.mapToItem(null, 0, 0);
                            return Qt.point(here.x - anchorHere.x + anchorThere.x,
                                here.y - anchorHere.y + anchorThere.y);
                        }

                        onPressed: event => {
                            dragArea.pressedAt = Qt.point(event.x, event.y);
                            dragArea.moved = false;
                        }
                        onPositionChanged: event => {
                            const far = Math.abs(event.x - dragArea.pressedAt.x) > 3
                                || Math.abs(event.y - dragArea.pressedAt.y) > 3;
                            if (!dragArea.moved && !far)
                                return;
                            const point = dragArea.inBarSpace(event.x, event.y);
                            if (!dragArea.moved) {
                                dragArea.moved = true;
                                TrayDragState.begin(trayButton.item, point.x, point.y, 8, 8);
                            } else {
                                TrayDragState.moveTo(point.x, point.y);
                            }
                            const local = dragArea.mapToItem(contentItem, event.x, event.y);
                            const left = local.x < 0 || local.y < 0
                                || local.x > contentItem.width || local.y > contentItem.height;
                            TrayDragState.dropAction = left ? "pin" : "";
                        }
                        onReleased: event => {
                            const local = dragArea.mapToItem(contentItem, event.x, event.y);
                            const left = local.x < 0 || local.y < 0
                                || local.x > contentItem.width || local.y > contentItem.height;
                            if (!dragArea.moved) {
                                trayButton.click();
                            } else if (left) {
                                // Hidden first: the item leaves the model on the next
                                // line, and upstream found the shell would crash otherwise.
                                trayButton.visible = false;
                                TrayService.togglePin(trayButton.item.id);
                            }
                            dragArea.moved = false;
                            TrayDragState.clear();
                        }
                        onCanceled: {
                            dragArea.moved = false;
                            TrayDragState.clear();
                        }
                    }
                }
            }
        }
    }
}
