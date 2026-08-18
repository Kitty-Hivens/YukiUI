import QtQuick
import qs.waffle.widgets

// Four corner marks instead of a drawn border: the card reads as something aimed
// at rather than something framed.
Item {
    id: root

    property color color: BoardLooks.cornerColor
    property int length: BoardLooks.cornerLength
    property int weight: BoardLooks.cornerWeight
    property int inset: 0

    Repeater {
        model: [
            {
                h: Qt.AlignLeft,
                v: Qt.AlignTop
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignTop
            },
            {
                h: Qt.AlignLeft,
                v: Qt.AlignBottom
            },
            {
                h: Qt.AlignRight,
                v: Qt.AlignBottom
            }
        ]
        delegate: Item {
            id: corner
            required property var modelData
            readonly property bool atLeft: modelData.h === Qt.AlignLeft
            readonly property bool atTop: modelData.v === Qt.AlignTop

            x: atLeft ? root.inset : root.width - root.length - root.inset
            y: atTop ? root.inset : root.height - root.length - root.inset
            width: root.length
            height: root.length

            Rectangle { // Horizontal arm
                x: 0
                y: corner.atTop ? 0 : corner.height - root.weight
                width: root.length
                height: root.weight
                color: root.color
            }
            Rectangle { // Vertical arm
                x: corner.atLeft ? 0 : corner.width - root.weight
                y: 0
                width: root.weight
                height: root.length
                color: root.color
            }
        }
    }
}
