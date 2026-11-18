pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.core
import qs.core.services
import qs.blueberry.looks

// A pen tablet. The tablet itself and the pen are OpenTabletDriver's, read and
// set through PenTablet; the screen the pen works on and the hand that holds
// it are the compositor's, through HyprInput. What else the driver can do, the
// buttons' bindings and its filters, is a click away in its own window.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    /** Held back by the window until the driver has been asked. */
    readonly property bool ready: PenTablet.ready

    Component.onCompleted: {
        PenTablet.refresh();
        HyprInput.refresh();
    }

    readonly property var tablet: PenTablet.tablet

    // -- Screens -------------------------------------------------------------

    /** A monitor's size as the layout has it, turned and scaled. */
    function logicalSize(monitor) {
        const turned = (monitor.transform ?? 0) % 2 === 1;
        const scale = monitor.scale > 0 ? monitor.scale : 1;
        return {
            width: (turned ? monitor.height : monitor.width) / scale,
            height: (turned ? monitor.width : monitor.height) / scale
        };
    }

    readonly property var monitors: HyprlandData.monitors.filter(monitor => !monitor.disabled)

    /**
     * The whole desktop, which the driver maps the pen onto before the
     * compositor puts it on a screen: its own area is always all of it, and
     * which screen the pen works on is the compositor's choice.
     */
    readonly property var desktop: {
        if (root.monitors.length === 0)
            return null;
        let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
        for (const monitor of root.monitors) {
            const size = root.logicalSize(monitor);
            left = Math.min(left, monitor.x);
            top = Math.min(top, monitor.y);
            right = Math.max(right, monitor.x + size.width);
            bottom = Math.max(bottom, monitor.y + size.height);
        }
        return { width: right - left, height: bottom - top };
    }
    readonly property var wholeDesktop: root.desktop ? { Width: root.desktop.width, Height: root.desktop.height, X: root.desktop.width / 2, Y: root.desktop.height / 2, Rotation: 0 } : null

    /** The pen reaching only part of the desktop: the driver's area left from another screen. */
    readonly property bool displayAreaStale: {
        const area = PenTablet.displayArea;
        const whole = root.wholeDesktop;
        if (!area || !whole)
            return false;
        return ["Width", "Height", "X", "Y"].some(key => Math.abs(area[key] - whole[key]) > 1);
    }

    /** The screen the pen draws on, whose shape a fitted area takes. */
    readonly property var targetSize: {
        const named = root.monitors.find(monitor => monitor.name === HyprInput.tabletOutput);
        if (named)
            return root.logicalSize(named);
        if (HyprInput.tabletOutput === "current") {
            const focused = root.monitors.find(monitor => monitor.focused);
            if (focused)
                return root.logicalSize(focused);
        }
        return root.desktop;
    }

    readonly property var screenChoices: [
        { value: "", text: Translation.tr("All screens") },
        { value: "current", text: Translation.tr("The screen in use") }
    ].concat(root.monitors.map(monitor => ({ value: monitor.name, text: monitor.description ? `${monitor.name} (${monitor.description})` : monitor.name })))

    // -- The area of the tablet ----------------------------------------------

    function fullArea() {
        return { Width: root.tablet.width, Height: root.tablet.height, X: root.tablet.width / 2, Y: root.tablet.height / 2, Rotation: 0 };
    }

    /** As much of the tablet as has the screen's shape, in its middle, so a circle drawn stays one. */
    function fittedArea() {
        const size = root.targetSize;
        if (!size || size.height <= 0)
            return root.fullArea();
        const shape = size.width / size.height;
        const wide = root.tablet.width / root.tablet.height > shape;
        const width = wide ? root.tablet.height * shape : root.tablet.width;
        const height = wide ? root.tablet.height : root.tablet.width / shape;
        return { Width: width, Height: height, X: root.tablet.width / 2, Y: root.tablet.height / 2, Rotation: 0 };
    }

    function sameArea(a, b): bool {
        return a !== null && b !== null && ["Width", "Height", "X", "Y"].every(key => Math.abs(a[key] - b[key]) < 0.5);
    }

    readonly property string areaMode: !root.tablet || !PenTablet.tabletArea ? "full"
        : root.sameArea(PenTablet.tabletArea, root.fullArea()) ? "full"
        : root.sameArea(PenTablet.tabletArea, root.fittedArea()) ? "screen"
        : "custom"
    /** Chosen here and kept while the numbers are still the whole tablet or the fitted shape. */
    property bool customChosen: false

    readonly property var areaModes: [
        { value: "full", text: Translation.tr("All of it") },
        { value: "screen", text: Translation.tr("The screen's shape") },
        { value: "custom", text: Translation.tr("Custom area") }
    ]

    /** Hands an area to the driver, with the desktop as its screen area so the two agree. */
    function setArea(area) {
        const changes = { tabletArea: area };
        if (root.wholeDesktop)
            changes.displayArea = root.wholeDesktop;
        PenTablet.apply(changes);
    }

    function patchArea(changes) {
        const area = Object.assign({}, PenTablet.tabletArea ?? root.fullArea(), changes);
        // Kept on the tablet: an area hanging off its edge is pen strokes
        // that go nowhere.
        area.Width = Math.min(area.Width, root.tablet.width);
        area.Height = Math.min(area.Height, root.tablet.height);
        area.X = Math.max(area.Width / 2, Math.min(root.tablet.width - area.Width / 2, area.X));
        area.Y = Math.max(area.Height / 2, Math.min(root.tablet.height - area.Height / 2, area.Y));
        root.setArea(area);
    }

    readonly property var outputModes: [
        { value: PenTablet.artistMode, text: Translation.tr("Drawing"), description: Translation.tr("Pressure and tilt reach the program") },
        { value: PenTablet.absoluteMode, text: Translation.tr("Pointer on the spot"), description: Translation.tr("A point on the tablet is a point on the screen, no pressure") },
        { value: PenTablet.relativeMode, text: Translation.tr("Pointer that moves"), description: Translation.tr("The pen moves the pointer as a mouse does") }
    ]

    function indexOfValue(list, value): int {
        return Math.max(0, list.findIndex(entry => entry.value === value));
    }

    function millimetres(value): string {
        return Translation.tr("%1 mm").arg(Math.round(value * 10) / 10);
    }

    spacing: ExLooks.settings.groupGap

    SettingsHero {
        Layout.fillWidth: true
        switchable: false
        on: root.tablet !== null
        glyph: "stylus"
        text: !PenTablet.installed ? Translation.tr("OpenTabletDriver is not installed")
            : !PenTablet.running ? Translation.tr("The tablet driver is not running")
            : root.tablet ? root.tablet.name
            : Translation.tr("No tablet connected")
        subtitle: !PenTablet.installed ? Translation.tr("Pen tablets are driven by it here")
            : !PenTablet.running ? ""
            : root.tablet ? Translation.tr("%1 × %2 mm, %3 pressure levels, %4 pen buttons, %5 keys")
                .arg(Math.round(root.tablet.width)).arg(Math.round(root.tablet.height))
                .arg(root.tablet.maxPressure + 1).arg(root.tablet.penButtons).arg(root.tablet.auxButtons)
            : Translation.tr("Plug it in and it shows here")

        ExButton {
            visible: PenTablet.installed && !PenTablet.running
            kind: "accent"
            text: Translation.tr("Start the driver")
            onClicked: PenTablet.startDriver()
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: PenTablet.lastError.length > 0
        glyph: "error"
        text: Translation.tr("The change did not go through")
        description: PenTablet.lastError
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: root.tablet !== null && root.displayAreaStale
        glyph: "warning"
        text: Translation.tr("The pen reaches only part of the screen")
        description: Translation.tr("The driver still maps it onto %1 × %2, left from another screen")
            .arg(Math.round(PenTablet.displayArea?.Width ?? 0)).arg(Math.round(PenTablet.displayArea?.Height ?? 0))

        ExButton {
            kind: "accent"
            text: Translation.tr("Use the whole screen")
            onClicked: PenTablet.apply({ displayArea: root.wholeDesktop })
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: root.tablet !== null
        title: Translation.tr("Screen")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "desktop_windows"
            text: Translation.tr("The pen works on")

            SettingsDropdown {
                model: root.screenChoices.map(choice => choice.text)
                currentIndex: root.indexOfValue(root.screenChoices, HyprInput.tabletOutput)
                onActivated: index => {
                    HyprInput.set(["input", "tablet"], "output", root.screenChoices[index].value);
                    // The fitted shape follows the screen it is fitted to.
                    if (root.areaMode === "screen")
                        fitAgain.restart();
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "back_hand"
            text: Translation.tr("Left-handed")
            description: Translation.tr("The tablet is turned round")

            ExSwitch {
                checked: HyprInput.tabletLeftHanded
                onToggled: HyprInput.set(["input", "tablet"], "left_handed", checked)
            }
        }
    }

    // Once the compositor has the new screen, so the shape is the new one's.
    Timer {
        id: fitAgain
        interval: 400
        onTriggered: root.setArea(root.fittedArea())
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: root.tablet !== null && PenTablet.outputMode !== PenTablet.relativeMode
        title: Translation.tr("Area of the tablet")

        TabletAreaPreview {
            Layout.fillWidth: true
            tabletWidth: root.tablet?.width ?? 1
            tabletHeight: root.tablet?.height ?? 1
            area: PenTablet.tabletArea
        }
        // The numbers under it are the area whatever was chosen, and changing
        // one makes it a custom area.
        SettingsExpander {
            id: areaExpander

            Layout.fillWidth: true
            glyph: "crop_free"
            text: Translation.tr("The pen reads on")
            description: root.areaMode === "screen" ? Translation.tr("Shaped like the screen, so a circle stays round") : ""

            control: SettingsDropdown {
                model: root.areaModes.map(mode => mode.text)
                currentIndex: root.indexOfValue(root.areaModes, root.customChosen ? "custom" : root.areaMode)
                onActivated: index => {
                    const mode = root.areaModes[index].value;
                    root.customChosen = mode === "custom";
                    if (mode === "full")
                        root.setArea(root.fullArea());
                    else if (mode === "screen")
                        root.setArea(root.fittedArea());
                    else
                        areaExpander.expanded = true;
                }
            }

            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("Width")

                SettingsNumber {
                    from: 10
                    to: root.tablet?.width ?? 100
                    stepSize: 1
                    unit: Translation.tr("mm")
                    value: Math.round(PenTablet.tabletArea?.Width ?? 0)
                    onEdited: value => root.patchArea({ Width: value })
                }
            }
            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("Height")

                SettingsNumber {
                    from: 10
                    to: root.tablet?.height ?? 100
                    stepSize: 1
                    unit: Translation.tr("mm")
                    value: Math.round(PenTablet.tabletArea?.Height ?? 0)
                    onEdited: value => root.patchArea({ Height: value })
                }
            }
            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("From the left edge")
                description: Translation.tr("To the middle of the area")

                SettingsNumber {
                    from: 0
                    to: root.tablet?.width ?? 100
                    stepSize: 1
                    unit: Translation.tr("mm")
                    value: Math.round(PenTablet.tabletArea?.X ?? 0)
                    onEdited: value => root.patchArea({ X: value })
                }
            }
            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("From the top edge")
                description: Translation.tr("To the middle of the area")

                SettingsNumber {
                    from: 0
                    to: root.tablet?.height ?? 100
                    stepSize: 1
                    unit: Translation.tr("mm")
                    value: Math.round(PenTablet.tabletArea?.Y ?? 0)
                    onEdited: value => root.patchArea({ Y: value })
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: root.tablet !== null
        title: Translation.tr("Pen")

        SettingsCard {
            Layout.fillWidth: true
            glyph: "draw"
            text: Translation.tr("The pen acts as")
            description: root.outputModes[root.indexOfValue(root.outputModes, PenTablet.outputMode)].description

            SettingsDropdown {
                model: root.outputModes.map(mode => mode.text)
                currentIndex: root.indexOfValue(root.outputModes, PenTablet.outputMode)
                onActivated: index => PenTablet.apply({ outputMode: root.outputModes[index].value })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "touch_app"
            text: Translation.tr("Pressure for a touch")
            description: Translation.tr("%1% of full pressure before the tip counts as down").arg(Math.round(tipSlider.value))

            ExSlider {
                id: tipSlider
                implicitWidth: 240
                from: 0
                to: 100
                stepSize: 1
                value: PenTablet.tipThreshold
                // Sent as the knob is let go: each change is a round trip
                // through the driver, which a drag would queue up.
                onPressedChanged: {
                    if (!pressed)
                        PenTablet.apply({ tipThreshold: Math.round(value) });
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: PenTablet.installed
        title: Translation.tr("Related")

        SettingsCard {
            Layout.fillWidth: true
            leads: true
            glyph: "open_in_new"
            text: Translation.tr("OpenTabletDriver")
            description: Translation.tr("Buttons, keys and filters")
            onClicked: PenTablet.openDriverWindow()
        }
    }
}
