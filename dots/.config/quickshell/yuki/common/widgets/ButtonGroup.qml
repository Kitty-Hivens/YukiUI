import qs.core
import qs.common.widgets
import qs.common
import QtQuick
import QtQuick.Layouts

/**
 * A container that supports GroupButton children for bounciness.
 * See https://m3.material.io/components/button-groups/overview
 */
Rectangle {
    id: root
    default property alias groupData: rowLayout.data
    property alias uniformCellSizes: rowLayout.uniformCellSizes
    property real spacing: 5
    property real padding: 0
    property alias clickIndex: rowLayout.clickIndex
    property alias childrenCount: rowLayout.childrenCount

    /**
     * The children that are actually drawn as buttons.
     *
     * Hidden ones were already left out of the width and were still paid a gap
     * each, so a group with a toggle that hides itself carried a strip of
     * nothing. A Repeater put among the children is not a button at all and has
     * no radius to take a corner from, so it is left out by the same pass.
     */
    readonly property var shownChildren: {
        const shown = [];
        // Read through the row rather than from it: this is evaluated while the
        // group is still being built, and reaching into something that is not
        // there yet leaves the whole expression undefined -- which then lands on
        // a number property as "Unable to assign [undefined] to double".
        const children = rowLayout?.children ?? [];
        for (let i = 0; i < children.length; ++i) {
            const child = children[i];
            if (!child.visible || child.radius === undefined) continue;
            shown.push(child);
        }
        return shown;
    }

    property real contentWidth: {
        const shown = root.shownChildren ?? [];
        let total = 0;
        for (let i = 0; i < shown.length; ++i) {
            const child = shown[i];
            total += child.baseWidth ?? child.implicitWidth ?? child.width ?? 0;
        }
        return total + (rowLayout?.spacing ?? root.spacing) * Math.max(0, shown.length - 1);
    }

    readonly property real fallbackRadius: Appearance?.rounding?.small ?? 8

    topLeftRadius: root.shownChildren.length > 0 ? (root.shownChildren[0].radius + padding) : root.fallbackRadius
    bottomLeftRadius: topLeftRadius
    topRightRadius: root.shownChildren.length > 0 ? (root.shownChildren[root.shownChildren.length - 1].radius + padding) : root.fallbackRadius
    bottomRightRadius: topRightRadius

    color: "transparent"
    width: root.contentWidth + padding * 2
    implicitHeight: rowLayout.implicitHeight + padding * 2
    implicitWidth: root.contentWidth + padding * 2
    
    children: [RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
        property int clickIndex: -1
        property int childrenCount: children.length
    }]
}
