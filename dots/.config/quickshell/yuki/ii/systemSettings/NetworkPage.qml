pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.core.services
import qs.core
import qs.core.functions
import qs.ii.systemSettings
import qs.common.widgets
import qs.common

/**
 * Everything nmtui was kept around for: what carries the machine online right
 * now, the networks in range, the saved ways online that are not wifi, and the
 * daemon underneath when it stops answering.
 *
 * All of it comes from [Network], the same service the sidebar list uses -- this
 * is a second view of one radio, not a second source of truth about it.
 */
Item {
    id: root

    readonly property list<var> otherConnections: Network.otherConnections

    readonly property string channelName: {
        switch (Network.connectionType) {
        case "ethernet":
            return Translation.tr("Wired");
        case "wifi":
            return Translation.tr("Wi-Fi");
        case "cellular":
            return Translation.tr("Mobile broadband");
        case "bluetooth":
            return Translation.tr("Bluetooth tethering");
        }
        return "";
    }

    // NetworkManager's own verdict, worded. "limited" is the one worth saying out
    // loud: the link is up and the internet behind it is not.
    readonly property string reachText: {
        switch (Network.connectivity) {
        case "full":
            return Translation.tr("Internet is reachable");
        case "limited":
            return Translation.tr("Connected, but the internet is not reachable");
        case "portal":
            return Translation.tr("A sign-in page is waiting");
        case "none":
            return Translation.tr("No internet");
        }
        return "";
    }





    // The system dialog rather than a browser of our own: picking a file that
    // could be anywhere on disk is what it is for, and the shell already reaches
    // for it when a wallpaper is chosen from outside the wallpaper folder.
    FileDialog {
        id: vpnPicker
        title: Translation.tr("Choose a VPN configuration")
        nameFilters: [
            `${Translation.tr("VPN configuration")} (*.conf *.ovpn)`,
            `${Translation.tr("All files")} (*)`
        ]
        onAccepted: Network.importVpnConfig(FileUtils.trimFileProtocol(vpnPicker.selectedFile.toString()))
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            // Positioned rather than anchored: inside a flickable the content item
            // is what scrolls, so filling it would pin the page in place.
            y: 16
            // Left edge shared with the page header above it rather than centred:
            // centred, the column drifted away from the heading it belongs to and
            // left a hole down the left of a wide window.
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true
                icon: Network.materialSymbol
                title: Network.connected
                    ? (Network.networkName.length > 0 ? Network.networkName : root.channelName)
                    : Translation.tr("Not connected")
                subtitle: Network.connected ? root.channelName : Translation.tr("Nothing is carrying this machine online")

                FactRow {
                    label: Translation.tr("Reach")
                    value: root.reachText
                }
                FactRow {
                    label: Translation.tr("Wi-Fi device")
                    value: Network.wifiDevice
                }
                FactRow {
                    // Only when the tunnel has no profile of its own below: a unit
                    // outside NetworkManager can raise a tun device that is real but
                    // unlisted, and that is worth saying somewhere.
                    label: Translation.tr("VPN")
                    value: (Network.vpnActive && Network.vpnConnections.length === 0) ? Network.vpnDevice : ""
                }
            }

            PageHeading {
                text: Translation.tr("Wi-Fi")
            }

            SystemCard {
                Layout.fillWidth: true

                ConfigSwitch {
                    id: wifiSwitch
                    text: Translation.tr("Wi-Fi")
                    buttonIcon: "wifi"
                    // Restated through Binding rather than left as a plain
                    // assignment: the control writes its own property when the user
                    // touches it, which drops the binding, and from then on it shows
                    // what was asked for rather than what the radio is doing.
                    Binding {
                        target: wifiSwitch
                        property: "checked"
                        value: Network.wifiEnabled
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    onCheckedChanged: {
                        if (checked !== Network.wifiEnabled)
                            Network.enableWifi(checked);
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: !Network.wifiEnabled ? Translation.tr("The radio is off")
                            : Network.wifiScanning ? Translation.tr("Looking for networks...")
                            : Translation.tr("%1 in range").arg(Network.friendlyWifiNetworks.length)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                    RippleButtonWithIcon {
                        enabled: Network.wifiEnabled && !Network.wifiScanning
                        materialIcon: "refresh"
                        mainText: Translation.tr("Scan")
                        onClicked: Network.rescanWifi()
                    }
                }

                PageNote {
                    visible: Network.wifiEnabled && Network.friendlyWifiNetworks.length === 0
                    text: Network.wifiScanning ? Translation.tr("Looking for networks...") : Translation.tr("Nothing in range")
                }

                Repeater {
                    model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []

                    delegate: ColumnLayout {
                        id: networkEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: networkEntry.index > 0
                        }
                        WifiNetworkRow {
                            Layout.fillWidth: true
                            network: networkEntry.modelData
                        }
                    }
                }
            }

            PageHeading {
                visible: root.otherConnections.length > 0
                text: Translation.tr("Other connections")
            }

            // Bluetooth tethering and modems: saved profiles rather than something
            // in range, which is why they are a list of their own and not part of
            // the wifi one.
            SystemCard {
                Layout.fillWidth: true
                visible: root.otherConnections.length > 0

                Repeater {
                    model: root.otherConnections

                    delegate: ColumnLayout {
                        id: connectionEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: connectionEntry.index > 0
                        }
                        NetworkConnectionRow {
                            Layout.fillWidth: true
                            connection: connectionEntry.modelData
                        }
                    }
                }
            }

            PageHeading {
                text: Translation.tr("VPN")
            }

            // A tunnel rides on whatever is carrying the machine, so it is listed
            // apart from the channels rather than among them: bringing one up does
            // not replace the connection underneath it.
            //
            // Shown even with nothing in it, unlike the other lists here, because
            // this is the one place a tunnel can be brought into existence: the
            // others list what the machine can see, and this lists what somebody
            // has to add.
            SystemCard {
                Layout.fillWidth: true

                Repeater {
                    model: Network.vpnConnections

                    delegate: ColumnLayout {
                        id: vpnEntry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0

                        PageDivider {
                            visible: vpnEntry.index > 0
                        }
                        NetworkConnectionRow {
                            Layout.fillWidth: true
                            connection: vpnEntry.modelData
                        }
                    }
                }

                PageNote {
                    visible: Network.vpnConnections.length === 0
                    text: Translation.tr("No tunnels are saved")
                }

                PageDivider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: Network.vpnImportError.length > 0 ? Network.vpnImportError
                            : Network.vpnImported.length > 0 ? Translation.tr("Imported %1").arg(Network.vpnImported)
                            : Translation.tr("From a WireGuard or OpenVPN configuration file")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Network.vpnImportError.length > 0 ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                    RippleButtonWithIcon {
                        enabled: !Network.vpnImporting
                        materialIcon: Network.vpnImporting ? "hourglass" : "upload_file"
                        mainText: Network.vpnImporting ? Translation.tr("Importing...") : Translation.tr("Import")
                        onClicked: vpnPicker.open()
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Underneath")
            }

            // One row rather than a paragraph: which daemon it is and the button
            // are the parts anyone acts on, and why it helps belongs on the button
            // that does it.
            SystemCard {
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    MaterialSymbol {
                        text: "settings_ethernet"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Wi-Fi backend")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Network.wifiBackendUnit
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RippleButtonWithIcon {
                        enabled: !Network.wifiBackendRestarting
                        materialIcon: Network.wifiBackendRestarting ? "hourglass" : "restart_alt"
                        mainText: Network.wifiBackendRestarting ? Translation.tr("Restarting...") : Translation.tr("Restart")
                        onClicked: Network.restartWifiBackend()
                        StyledToolTip {
                            text: `${Translation.tr("The list of networks comes from this daemon. If scanning stops finding anything while the radio is on, restarting it is what fixes it.")}\n${Translation.tr("Asks systemd to restart %1. It will ask for a password.").arg(Network.wifiBackendUnit)}`
                        }
                    }
                }
            }
        }
    }
}
