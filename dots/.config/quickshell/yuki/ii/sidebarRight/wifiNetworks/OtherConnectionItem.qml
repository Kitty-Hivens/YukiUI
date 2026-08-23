import qs
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.core.services
import qs.common
import qs.ii
import QtQuick
import QtQuick.Layouts

/**
 * A way online that is not wifi -- bluetooth tethering, a modem -- as one row of
 * the network dialog.
 */
DialogListItem {
    id: root
    required property var connection
    property bool expanded: false

    readonly property bool isActive: root.connection?.active ?? false
    readonly property bool busy: Network.busyConnectionUuid.length > 0
        && Network.busyConnectionUuid === (root.connection?.uuid ?? "")

    active: root.isActive
    pointingHandCursor: !root.expanded
    onClicked: root.expanded = !root.expanded
    altAction: () => root.expanded = !root.expanded

    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnPrimary
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: root.connection?.channel === "cellular" ? "signal_cellular_alt" : "bluetooth"
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.connection?.name ?? Translation.tr("Unknown")
                    textFormat: Text.PlainText
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: {
                        if (root.busy)
                            return root.isActive ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
                        return root.isActive ? Translation.tr("Connected") : Translation.tr("Saved");
                    }
                }
            }

            MaterialSymbol {
                visible: root.isActive
                text: "check"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            Layout.topMargin: 8
            visible: root.expanded

            Item {
                Layout.fillWidth: true
            }

            ActionButton {
                // Any connection being brought up or down holds every row, not just
                // the one that is busy: they are alternatives to each other, and two
                // nmcli runs at once decide between them what the machine ends up on.
                enabled: !Network.connectionBusy
                buttonText: root.isActive ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (root.isActive)
                        Network.deactivateConnection(root.connection.uuid);
                    else
                        Network.activateConnection(root.connection.uuid);
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
