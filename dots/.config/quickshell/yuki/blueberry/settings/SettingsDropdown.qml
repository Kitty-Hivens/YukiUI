pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import qs.blueberry.looks

// One choice out of a list, shown as the choice made, the list opening under it
// on a click. What Windows puts in a settings card as a combo box. A long list
// scrolls rather than running past the window, and opens on the choice made.
ExButton {
    id: root

    /** The choices as text, in order. */
    property var model: []
    property int currentIndex: -1
    /** A choice that cannot be made is shown, and not offered. */
    property var disabledIndices: []

    signal activated(int index)

    kind: "control"
    text: root.model[root.currentIndex] ?? ""
    implicitWidth: Math.min(360, Math.max(160, label.implicitWidth + 2 * ExLooks.sizes.buttonPadding + 24))

    /** The list, for what has to read how it stands. */
    readonly property alias list: list

    // The widest choice, as a row of the list draws it: the room for the check,
    // the text, the row's own margins, and the bar of a list long enough to
    // scroll. Measured as the list opens: read from items made for the purpose
    // it came too early, was nothing, and every list stayed as wide as its box.
    TextMetrics {
        id: measure
        font.family: ExLooks.font.family
        font.pixelSize: ExLooks.font.body
        font.weight: ExLooks.font.weightBody
    }
    function widestChoice(): real {
        let widest = 0;
        for (const choice of root.model) {
            measure.text = choice;
            widest = Math.max(widest, Math.ceil(measure.advanceWidth));
        }
        return widest + 2 * (ExLooks.spacing.s + 2) + 18 + ExLooks.spacing.m + 2 * ExLooks.sizes.menuPadding + 8;
    }
    // The button toggles the list. A press on it is not a press outside, or it
    // would close the list only for the release to open it again.
    onClicked: list.visible ? list.close() : list.open()

    contentItem: Item {
        ExText {
            id: label
            anchors.left: parent.left
            anchors.leftMargin: ExLooks.sizes.buttonPadding
            anchors.right: arrow.left
            anchors.rightMargin: ExLooks.spacing.s
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            role: "label"
            color: root.ink
        }
        ExGlyph {
            id: arrow
            anchors.right: parent.right
            anchors.rightMargin: ExLooks.spacing.m
            anchors.verticalCenter: parent.verticalCenter
            text: "expand_more"
            size: 18
            color: root.ink
        }
    }

    Popup {
        id: list

        readonly property real rowHeight: ExLooks.sizes.menuItem

        // As wide as the box, as on Windows, and wider only for a choice that
        // would not fit: a fixed width made a short list stand far out past
        // its box, and cut long choices, a sound card's profiles, short. Grown
        // towards the page, since a box stands at the far end of its row.
        x: root.width - list.width
        y: root.height + 4
        width: root.width
        onAboutToShow: list.width = Math.max(root.width, Math.min(560, root.widestChoice()))
        height: Math.min(360, root.model.length * list.rowHeight + 2 * ExLooks.sizes.menuPadding)
        // Kept inside the window, moved up rather than cut off at its edge.
        margins: ExLooks.spacing.s
        padding: 0
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: null
        onOpened: rows.positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Center)

        contentItem: ExSurface {
            radius: ExLooks.radius.menu
            elevation: 1

            ListView {
                id: rows

                anchors.fill: parent
                anchors.margins: ExLooks.sizes.menuPadding
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.model

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: ExMenuItem {
                    required property string modelData
                    required property int index

                    width: ListView.view.width
                    text: modelData
                    glyph: index === root.currentIndex ? "check" : ""
                    enabled: !root.disabledIndices.includes(index)
                    onClicked: {
                        list.close();
                        if (index !== root.currentIndex)
                            root.activated(index);
                    }
                }
            }
        }
    }
}
