import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import qs.core.services
import qs.core
import qs.waffle.looks

BarButton {
    id: root

    required property string iconName
    property bool multiple: false
    property bool separateLightDark: false
    property alias tryCustomIcon: iconWidget.tryCustomIcon
    leftInset: 2
    rightInset: 2
    // Stated, not derived. Deriving the width from the height made the cell follow
    // the icon: dropping the icon from 26 to its measured 24 pulled the button from
    // 42 to 40, where Windows is 44 regardless of what it holds. The task row is a
    // list view, which does not stretch its delegates, so the height has to be said
    // as well or it comes back from the content too.
    implicitWidth: Looks.sizes.barButtonWidth
    implicitHeight: Looks.sizes.barHeight

    property real pressedScale: 5/6

    onDownChanged: {
        scaleAnim.duration = root.down ? 150 : 200
        scaleAnim.easing.bezierCurve = root.down ? Looks.transition.easing.bezierCurve.decelerate : Looks.transition.easing.bezierCurve.accelerate
        contentItem.scale = root.down ? root.pressedScale : 1 // If/When we do dragging, the scale is 1.25
    }

    background: Item {
        id: background
        BackgroundAcrylicRectangle {
            id: mainBgRect
            anchors.fill: parent
            layer.enabled: root.multiple
            layer.effect: OpacityMask {
                invert: true
                maskSource: Item {
                    width: mainBgRect.width
                    height: mainBgRect.height
                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 3
                        radius: mainBgRect.radius
                    }
                }
            }
        }
        Loader {
            anchors.fill: parent
            anchors.rightMargin: 5
            active: root.multiple
            sourceComponent: BackgroundAcrylicRectangle {}
        }
    }

    contentItem: Item {
        id: contentItem
        anchors.centerIn: parent

        implicitHeight: iconWidget.implicitHeight
        implicitWidth: iconWidget.implicitWidth

        Behavior on scale {
            NumberAnimation {
                id: scaleAnim
                easing.type: Easing.BezierSpline
            }
        }

        WAppIcon {
            id: iconWidget
            anchors.centerIn: parent
            iconName: root.iconName
            separateLightDark: root.separateLightDark
        }
    }

    component BackgroundAcrylicRectangle: AcrylicRectangle {
        shiny: ((root.hovered && !root.down) || root.checked)
        color: root.color
        border.width: 1
        border.color: root.colBackgroundBorder

        Behavior on border.color {
            animation: Looks.transition.color.createObject(this)
        }
    }
}
