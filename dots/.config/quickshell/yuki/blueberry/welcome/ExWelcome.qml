pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs.core.services
import qs.blueberry.looks
import qs.blueberry.settings

// The welcome's content, laid out as the settings window is: the steps down
// the left on the window's tone, each marked once it has been seen, and the
// step on show on a pane beside them, with the way on at its foot. Every
// choice takes effect as it is made, so there is nothing to confirm at the
// end, and a step can be skipped or come back to.
Item {
    id: root

    /** A step's key to open on, or empty for the first. */
    property string startStep: ""

    signal finished

    readonly property var metrics: ExLooks.settings
    readonly property real railWidth: 248

    readonly property var steps: [
        { key: "hello", name: Translation.tr("Welcome"), glyph: "waving_hand", url: "WelcomeHello.qml" },
        { key: "look", name: Translation.tr("Look"), glyph: "palette", url: "WelcomeLook.qml" },
        { key: "dock", name: Translation.tr("Dock"), glyph: "dock_to_bottom", url: "WelcomeDock.qml" },
        { key: "keys", name: Translation.tr("Keys"), glyph: "keyboard", url: "WelcomeKeys.qml" },
        { key: "updates", name: Translation.tr("Updates"), glyph: "system_update_alt", url: "WelcomeUpdates.qml" },
        { key: "ready", name: Translation.tr("All set"), glyph: "check", url: "WelcomeReady.qml" }
    ]
    property int step: -1
    /** The furthest step reached, so the ones before it read as seen. */
    property int reached: 0
    readonly property bool atLast: root.step === root.steps.length - 1
    /** 1 going on, -1 going back: which side the step comes in from. */
    property int direction: 1

    function go(index: int) {
        if (index < 0 || index >= root.steps.length || index === root.step)
            return;
        root.direction = index > root.step ? 1 : -1;
        root.step = index;
        root.reached = Math.max(root.reached, index);
        content.setSource(Qt.resolvedUrl(root.steps[index].url), { welcome: root });
        scroller.contentY = 0;
        arrivalAnimation.stop();
        root.arrival = 0;
        arrivalAnimation.start();
    }
    function next() {
        if (root.atLast)
            root.finished();
        else
            root.go(root.step + 1);
    }
    function back() {
        root.go(root.step - 1);
    }

    Component.onCompleted: {
        const start = root.steps.findIndex(step => step.key === root.startStep);
        root.go(Math.max(0, start));
        // Opened on a later step, as it is to show that step alone, the ones
        // before it are not passed over unseen.
        root.reached = root.step;
        // The first step comes up with the window, not into it.
        arrivalAnimation.stop();
        root.arrival = 1;
    }

    /** From where the step comes in (0) to in place (1). */
    property real arrival: 1
    NumberAnimation {
        id: arrivalAnimation
        target: root
        property: "arrival"
        to: 1
        duration: ExLooks.motion.normal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: ExLooks.motion.decelerate
    }

    Shortcut {
        sequences: ["Alt+Left"]
        onActivated: root.back()
    }
    Shortcut {
        sequences: ["Alt+Right"]
        onActivated: root.next()
    }
    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: root.finished()
    }

    // What this is, and the steps.
    Item {
        id: rail

        width: root.railWidth
        height: parent.height

        RowLayout {
            id: appTitle

            x: root.metrics.railAxis - root.metrics.railChip / 2
            y: root.metrics.contentTop
            width: parent.width - x - root.metrics.railPadding
            spacing: ExLooks.spacing.m

            // Yuki is snow.
            SettingsChip {
                glyph: "ac_unit"
                size: root.metrics.railChip
            }
            ExText {
                Layout.fillWidth: true
                text: "YukiUI"
                font.pixelSize: root.metrics.heading
                font.weight: ExLooks.font.weightTitle
            }
        }

        Column {
            x: root.metrics.railPadding
            y: appTitle.y + appTitle.height + ExLooks.spacing.xl
            width: parent.width - 2 * x
            spacing: 2

            Repeater {
                model: root.steps

                AbstractButton {
                    id: stepItem

                    ExPrimaryOnly {
                        z: 1
                    }

                    required property var modelData
                    required property int index
                    readonly property bool here: stepItem.index === root.step
                    readonly property bool seen: stepItem.index < root.step || (stepItem.index <= root.reached && !stepItem.here)

                    width: parent.width
                    implicitHeight: root.metrics.railItem
                    hoverEnabled: true
                    onClicked: root.go(stepItem.index)

                    ExFocusRing {
                        anchors.margins: 0
                        cornerRadius: root.metrics.controlRadius - 2
                    }

                    background: Rectangle {
                        radius: root.metrics.controlRadius
                        color: stepItem.here ? ExLooks.colors.tonal : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: ExLooks.motion.fast }
                        }

                        ExStateLayer {
                            ink: stepItem.here ? ExLooks.colors.tonalInk : ExLooks.colors.text
                            hovered: stepItem.hovered
                            pressed: stepItem.down
                        }
                    }
                    contentItem: RowLayout {
                        spacing: ExLooks.spacing.m

                        // The step's glyph, turned to a check once it has been seen.
                        SettingsChip {
                            Layout.leftMargin: root.metrics.railAxis - root.metrics.railPadding - root.metrics.railChip / 2
                            glyph: stepItem.seen ? "check" : stepItem.modelData.glyph
                            size: root.metrics.railChip
                            inverted: stepItem.here || stepItem.seen
                        }
                        ExText {
                            Layout.fillWidth: true
                            text: stepItem.modelData.name
                            font.pixelSize: root.metrics.body
                            font.weight: stepItem.here ? ExLooks.font.weightTitle : ExLooks.font.weightBody
                            color: stepItem.here ? ExLooks.colors.tonalInk : stepItem.seen || stepItem.index <= root.reached ? ExLooks.colors.text : ExLooks.colors.textDim
                        }
                    }
                }
            }
        }

        ExText {
            x: root.metrics.railAxis - root.metrics.railChip / 2
            width: parent.width - x - root.metrics.railPadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.metrics.contentTop
            text: Translation.tr("Super+Shift+Alt+/ opens this again")
            font.pixelSize: root.metrics.small
            wrapMode: Text.Wrap
            dim: true
        }
    }

    // The step on show, and the way on at its foot.
    Rectangle {
        id: pane

        x: rail.width
        y: ExLooks.spacing.s
        width: parent.width - x - ExLooks.spacing.s
        height: parent.height - 2 * ExLooks.spacing.s
        radius: root.metrics.paneRadius
        color: root.metrics.pane

        readonly property real column: Math.min(820, pane.width - 2 * root.metrics.contentMargin)
        readonly property real columnX: Math.round((pane.width - pane.column) / 2)

        Flickable {
            id: scroller

            width: parent.width
            height: parent.height - footer.height
            clip: true
            contentHeight: content.y + (content.item?.implicitHeight ?? 0) + root.metrics.groupGap
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Loader {
                id: content

                x: pane.columnX
                // In line with the rail's title across the window.
                y: root.metrics.contentTop + ExLooks.spacing.m
                width: pane.column
                opacity: root.arrival
                transform: Translate {
                    x: (1 - root.arrival) * 40 * root.direction
                }
            }
        }

        // Up past the top of the page, out of the way of the step's title.
        ExToolButton {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ExLooks.spacing.m
            glyph: "close"
            onClicked: root.finished()
        }

        Item {
            id: footer

            anchors.bottom: parent.bottom
            width: parent.width
            height: 68

            // Shown once the step runs under the foot.
            Rectangle {
                width: parent.width
                height: 1
                color: root.metrics.rule
                opacity: scroller.contentY + scroller.height < scroller.contentHeight - 1 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: ExLooks.motion.fast }
                }
            }

            RowLayout {
                x: pane.columnX
                width: pane.column
                anchors.verticalCenter: parent.verticalCenter
                spacing: ExLooks.spacing.s

                ExButton {
                    visible: root.step > 0
                    kind: "control"
                    glyph: "arrow_back"
                    text: Translation.tr("Back")
                    onClicked: root.back()
                }
                Item {
                    Layout.fillWidth: true
                }
                // Where along the way, as dots: the one on show drawn long.
                Row {
                    spacing: 6

                    Repeater {
                        model: root.steps.length

                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: index === root.step ? 20 : 6
                            height: 6
                            radius: 3
                            color: index === root.step ? ExLooks.colors.accent : ExLooks.colors.textDim
                            opacity: index === root.step ? 1 : 0.4

                            Behavior on width {
                                NumberAnimation { duration: ExLooks.motion.normal; easing.type: Easing.BezierSpline; easing.bezierCurve: ExLooks.motion.standard }
                            }
                        }
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                ExButton {
                    kind: "accent"
                    text: root.atLast ? Translation.tr("Finish") : Translation.tr("Next")
                    glyph: root.atLast ? "check" : ""
                    onClicked: root.next()
                }
            }
        }
    }
}
