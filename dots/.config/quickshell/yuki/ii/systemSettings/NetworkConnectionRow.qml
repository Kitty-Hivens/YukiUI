pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.common.widgets
import qs.common

/**
 * A way online that is not wifi -- bluetooth tethering, a modem -- as one row.
 *
 * These are saved profiles rather than things in range, so the row is about
 * bringing one up or taking it down, and there is nothing to expand.
 */
RowLayout {
    id: root
    required property var connection

    readonly property bool isActive: root.connection?.active ?? false
    readonly property bool busy: Network.busyConnectionUuid.length > 0
        && Network.busyConnectionUuid === (root.connection?.uuid ?? "")

    spacing: 12

    MaterialSymbol {
        text: root.connection?.channel === "cellular" ? "signal_cellular_alt"
            : root.connection?.channel === "vpn" ? "vpn_key"
            : "bluetooth"
        iconSize: Appearance.font.pixelSize.hugeass
        color: root.isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: root.connection?.name ?? Translation.tr("Unknown")
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: root.isActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        }
        StyledText {
            Layout.fillWidth: true
            text: {
                if (root.busy)
                    return root.isActive ? Translation.tr("Disconnecting...") : Translation.tr("Connecting...");
                return root.isActive ? Translation.tr("Connected") : Translation.tr("Saved");
            }
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtext
        }
    }

    RippleButtonWithIcon {
        // Any connection coming up or going down holds every row, not only the one
        // that is busy: they are alternatives to each other, and two nmcli runs at
        // once decide between them what the machine ends up on.
        enabled: !Network.connectionBusy
        materialIcon: root.busy ? "hourglass" : root.isActive ? "link_off" : "link"
        mainText: root.isActive ? Translation.tr("Disconnect") : Translation.tr("Connect")
        onClicked: {
            if (root.isActive)
                Network.deactivateConnection(root.connection.uuid);
            else
                Network.activateConnection(root.connection.uuid);
        }
    }
}
