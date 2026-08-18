import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

/**
 * A toggle this family did not write, drawn in this family's style.
 *
 * The glyph is a Material symbol unless the plugin named a picture of its own
 * for this style, which is what a service with a logo tends to want -- there is
 * no symbol for a particular company, and the nearest one says something else.
 */
QuickToggleButton {
    id: root

    required property QuickToggleModel toggleModel

    readonly property string customIcon: toggleModel?.familyIcons?.iiClassic ?? ""
    readonly property color colContent: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

    visible: toggleModel?.available ?? false
    toggled: toggleModel?.toggled ?? false
    buttonIcon: toggleModel?.icon ?? "extension"

    contentItem: Item {
        implicitWidth: 22
        implicitHeight: 22

        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.customIcon.length === 0
            iconSize: 22
            fill: root.toggled ? 1 : 0
            color: root.colContent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.buttonIcon

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        CustomIcon {
            anchors.centerIn: parent
            visible: root.customIcon.length > 0
            source: root.customIcon
            width: 16
            height: 16
            colorize: true
            color: root.colContent

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    onClicked: root.toggleModel?.mainAction?.()

    StyledToolTip {
        text: root.toggleModel?.tooltipText ?? ""
    }
}
