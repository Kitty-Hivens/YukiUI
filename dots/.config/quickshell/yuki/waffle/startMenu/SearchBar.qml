pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.waffle.looks

FooterRectangle {
    id: root

    property real horizontalPadding: 32
    property real verticalPadding: 16
    property bool searching: text.length > 0
    property alias searchInput: searchInput
    property alias text: searchInput.text
    /// A pixel short of twice the padding, which is why the field ends up with 16
    /// above it and 15 below. The band and the separator under it come to 64 between
    /// them -- the same 64 as the account bar and its own separator at the other end
    /// of the menu -- and that separator is drawn by the page below, not here.
    implicitHeight: outline.implicitHeight + verticalPadding * 2 - 1

    signal accepted()

    Component.onCompleted: forceFocus()
    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    focus: true
    color: searching ? Looks.colors.bgPanelBody : Looks.colors.bgPanelFooter

    Behavior on horizontalPadding {
        enabled: Config.options.waffles.tweaks.smootherSearchBar
        animation: Looks.transition.move.createObject(this)
    }
    Behavior on verticalPadding {
        enabled: Config.options.waffles.tweaks.smootherSearchBar
        animation: Looks.transition.move.createObject(this)
    }

    Rectangle {
        id: outline
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        implicitHeight: 32
        color: "transparent"
        radius: height / 2
        border.width: 1
        border.color: Looks.colors.bg2Border
    }

    Rectangle {
        id: searchInputBg
        anchors.fill: outline
        anchors.margins: 1
        radius: height / 2
        color: Looks.colors.inputBg

        RowLayout {
            anchors.fill: parent
            spacing: 11

            WAppIcon {
                Layout.leftMargin: 14
                iconName: "system-search-checked"
                separateLightDark: true
                implicitSize: 18
            }

            WTextInput {
                id: searchInput
                focus: true
                Layout.fillWidth: true

                WText {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    color: Looks.colors.accentUnfocused
                    // The reference says "apps, settings, and documents". Settings are
                    // searched now; documents are not, and claiming them would be a
                    // promise the results cannot keep.
                    text: Translation.tr("Search for apps and settings")
                    visible: searchInput.text.length === 0
                    font.pixelSize: Looks.font.pixelSize.large
                }

                onAccepted: {
                    root.accepted();
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        acceptedButtons: Qt.NoButton
    }
}
