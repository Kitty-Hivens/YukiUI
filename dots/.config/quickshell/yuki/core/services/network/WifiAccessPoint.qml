import QtQuick

QtObject {
    required property var lastIpcObject
    readonly property string ssid: lastIpcObject.ssid
    readonly property string bssid: lastIpcObject.bssid
    readonly property int strength: lastIpcObject.strength
    readonly property int frequency: lastIpcObject.frequency
    readonly property bool active: lastIpcObject.active
    readonly property string security: lastIpcObject.security
    readonly property bool isSecure: security.length > 0

    property bool askingPassword: false

    /// Why the last attempt to join this network failed, as a code for a view to
    /// word as it likes: "secrets" (a password is needed), "wrongPassword",
    /// "notFound", "timeout", "failed". Empty once an attempt succeeds.
    property string errorKind: ""
    /// What nmcli said, for the cases the codes above do not cover.
    property string errorDetail: ""
}
