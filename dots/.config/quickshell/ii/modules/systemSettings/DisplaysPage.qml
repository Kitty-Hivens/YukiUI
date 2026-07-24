pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "arrange.js" as Arrange

Item {
    id: root
    readonly property bool wide: width > 1100
    property var draft: []
    property string selectedName: ""
    // Distinguishes edits made here from the compositor changing underneath us:
    // a monitor being unplugged is not an unapplied change the user has to
    // resolve, and the draft should simply follow reality.
    property bool userEdited: false

    readonly property var selected: root.draft.find(entry => entry.name === root.selectedName) ?? null
    readonly property var selectedOutput: Displays.outputs.find(output => output.name === root.selectedName) ?? null
    // The panel's backlight, which is what brightness means to anyone not
    // thinking about colour encodings. Driven over DDC for an external display
    // and through the kernel for the built-in one.
    readonly property var backlight: Brightness.monitors.find(monitor => monitor.screen?.name === root.selectedName) ?? null

    readonly property bool dirty: root.userEdited
        && root.planSignature(root.draft) !== root.planSignature(Displays.currentPlan())

    /**
     * What actually distinguishes one layout from another.
     *
     * Normalised, so sliding the whole arrangement across the canvas without
     * changing how the displays sit relative to each other is not a change. A
     * switched-off display contributes no position at all: it is parked
     * somewhere arbitrary, and turning one on and back off would otherwise leave
     * the page insisting there was something to apply.
     */
    function planSignature(plan) {
        return JSON.stringify(Arrange.normalize(plan)
            .map(entry => [
                entry.name, entry.enabled === true,
                entry.enabled ? entry.x : 0, entry.enabled ? entry.y : 0,
                entry.width, entry.height, Math.round(entry.refreshRate),
                entry.scale, entry.transform, entry.bitdepth, entry.cm,
                entry.vrrOverride ? entry.vrr : null,
                entry.sdrMaxLuminance, entry.sdrSaturation
            ])
            .sort((a, b) => a[0] < b[0] ? -1 : 1));
    }

    function resetDraft() {
        root.draft = Displays.currentPlan();
        root.userEdited = false;
        if (root.draft.length > 0 && !root.draft.some(entry => entry.name === root.selectedName))
            root.selectedName = root.primaryName();
    }

    // Dragging a display out of the parked row turns it on where it was dropped,
    // then lets the arrangement rules push it clear of whatever is already there.
    function enableAt(name, x, y) {
        const settled = Arrange.resolveOverlap(
            root.draft.map(entry => entry.name === name
                ? Object.assign({}, entry, { enabled: true, x: x, y: y })
                : entry),
            name, x, y);
        root.draft = root.draft.map(entry => entry.name === name
            ? Object.assign({}, entry, { enabled: true, x: settled.x, y: settled.y })
            : entry);
        root.userEdited = true;
        root.selectedName = name;
    }

    // Refused rather than silently ignored when it would leave nothing on: the
    // display being dragged away is the one the user is looking at.
    function disableOutput(name) {
        if (root.draft.filter(entry => entry.enabled).length <= 1)
            return;
        root.patch(name, { enabled: false });
        root.selectedName = name;
    }

    // The display at the origin is the primary one in every sense that matters
    // here, and picking it beats picking whichever the compositor listed first.
    function primaryName() {
        const active = root.draft.filter(entry => entry.enabled);
        const pool = active.length > 0 ? active : root.draft;
        const origin = pool.find(entry => entry.x === 0 && entry.y === 0);
        if (origin)
            return origin.name;
        return pool.reduce((best, entry) =>
            Math.abs(entry.x) + Math.abs(entry.y) < Math.abs(best.x) + Math.abs(best.y) ? entry : best,
            pool[0]).name;
    }

    function round2(value) {
        return Math.round(value * 100) / 100;
    }

    function tuneSdr(changes) {
        if (!root.selected)
            return;
        root.patch(root.selected.name, changes);
        const entry = root.draft.find(item => item.name === root.selectedName);
        Displays.previewSdr(entry.name, entry.sdrMaxLuminance, entry.sdrSaturation);
    }

    function patch(name, changes) {
        root.draft = root.draft.map(entry => entry.name === name ? Object.assign({}, entry, changes) : entry);
        root.userEdited = true;
    }

    // Outputs can report no mode list at all (virtual and headless ones do).
    // Falling back to what is currently set keeps the control meaningful
    // instead of rendering an empty dropdown.
    function resolutionsFor(output) {
        const seen = [];
        (output?.availableModes ?? []).forEach(mode => {
            const parsed = /^(\d+)x(\d+)@/.exec(mode);
            if (!parsed)
                return;
            const label = `${parsed[1]}x${parsed[2]}`;
            if (seen.indexOf(label) === -1)
                seen.push(label);
        });
        if (seen.length === 0 && root.selected)
            seen.push(`${root.selected.width}x${root.selected.height}`);
        return seen;
    }

    function refreshRatesFor(output, resolution) {
        const rates = [];
        (output?.availableModes ?? []).forEach(mode => {
            const parsed = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(mode);
            if (!parsed || `${parsed[1]}x${parsed[2]}` !== resolution)
                return;
            const rate = Math.round(parseFloat(parsed[3]));
            if (rates.indexOf(rate) === -1)
                rates.push(rate);
        });
        if (rates.length === 0 && root.selected)
            rates.push(Math.round(root.selected.refreshRate));
        return rates.sort((a, b) => b - a);
    }

    Component.onCompleted: {
        root.resetDraft();
        MonitorDdc.reload();
        // Separate process from the shell, so read the current gamma rather than
        // trusting this instance's default.
        Hyprsunset.fetchState();
    }

    Connections {
        target: Displays
        function onOutputsChanged() {
            // A display appearing, vanishing or losing its mode is hardware
            // changing underneath, not an edit to keep. Holding on to the draft
            // there leaves the page describing a machine that no longer exists,
            // which is exactly when the user needs it to be right.
            const live = Displays.currentPlan();
            const sameSet = live.length === root.draft.length
                && live.every(entry => root.draft.some(item => item.name === entry.name
                    && item.usable === entry.usable));
            if (!sameSet || !root.userEdited || root.draft.length === 0)
                root.resetDraft();
        }
        // Once the change is saved or deliberately left unsaved, the draft stops
        // being an edit in progress. Without this the banner stays up, because
        // the compositor can report a value back slightly differently from what
        // was asked for and the draft never compares equal again.
        function onPersisted() {
            root.resetDraft();
        }
    }

    // Side by side the two panes each manage their own height, but stacked they
    // need more room than a small window has, and the inspector was simply cut
    // off. The page scrolls in that case, and the canvas takes a fixed share
    // rather than competing for what is left.
    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        interactive: !root.wide
        contentHeight: root.wide ? height : pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

    ColumnLayout {
        id: pageColumn
        // Positioned rather than anchored: inside a flickable the content item
        // is what scrolls, so filling it would pin the page in place.
        x: 20
        y: 12
        width: pageFlick.width - 40
        height: root.wide ? pageFlick.height - 32 : implicitHeight
        spacing: 12

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.wide ? 2 : 1
            columnSpacing: 12
            rowSpacing: 12

            DisplayCanvas {
                id: canvas
                Layout.fillWidth: true
                Layout.fillHeight: root.wide
                Layout.preferredHeight: root.wide ? -1 : 320
                Layout.minimumHeight: 280
                plan: root.draft
                selectedName: root.selectedName
                onOutputPicked: name => root.selectedName = name
                onOutputMoved: (name, x, y) => root.patch(name, { x: x, y: y })
                onOutputEnableRequested: (name, x, y) => root.enableAt(name, x, y)
                onOutputDisableRequested: name => root.disableOutput(name)
            }

            SystemCard {
                Layout.preferredWidth: root.wide ? 380 : parent.width
                Layout.fillWidth: !root.wide
                Layout.fillHeight: root.wide
                Layout.alignment: Qt.AlignTop
                icon: "display_settings"
                title: root.selected?.name ?? Translation.tr("No display selected")
                subtitle: root.selectedOutput?.description ?? ""

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.wide
                    Layout.preferredHeight: root.wide ? -1 : inspector.implicitHeight
                    implicitHeight: inspector.implicitHeight
                    contentHeight: inspector.implicitHeight
                    clip: true
                    ScrollBar.vertical: StyledScrollBar {}

                    ColumnLayout {
                        id: inspector
                        width: parent.width
                        spacing: 10
                        enabled: root.selected !== null

                        ConfigSwitch {
                            id: enabledSwitch
                            text: Translation.tr("Enabled")
                            buttonIcon: "power_settings_new"
                            // Restated through Binding rather than left as a plain
                            // assignment: a control writes its own property when
                            // the user touches it, which drops the binding, and
                            // from then on it shows the display it was last used
                            // on instead of the one selected.
                            Binding {
                                target: enabledSwitch
                                property: "checked"
                                value: root.selected?.enabled ?? false
                                restoreMode: Binding.RestoreBindingOrValue
                            }
                            enabled: root.selected !== null
                                && !(root.selected.enabled && root.draft.filter(entry => entry.enabled).length <= 1)
                            onCheckedChanged: {
                                if (root.selected && checked !== root.selected.enabled)
                                    root.patch(root.selected.name, { enabled: checked });
                            }
                            StyledToolTip {
                                text: Translation.tr("The last enabled display cannot be turned off")
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Mode")

                            StyledComboBox {
                                id: resolutionBox
                                Layout.fillWidth: true
                                buttonIcon: "aspect_ratio"
                                model: root.resolutionsFor(root.selectedOutput)
                                // Selecting an entry writes currentIndex, and
                                // swapping the model resets it to zero, so
                                // without this the box shows the first mode of
                                // whatever display is selected rather than its
                                // actual one.
                                Binding {
                                    target: resolutionBox
                                    property: "currentIndex"
                                    value: resolutionBox.model.indexOf(`${root.selected?.width}x${root.selected?.height}`)
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                onActivated: index => {
                                    const parsed = /^(\d+)x(\d+)$/.exec(model[index]);
                                    if (!parsed || !root.selected)
                                        return;
                                    const rates = root.refreshRatesFor(root.selectedOutput, model[index]);
                                    root.patch(root.selected.name, {
                                        width: parseInt(parsed[1]),
                                        height: parseInt(parsed[2]),
                                        refreshRate: rates.length > 0 ? rates[0] : root.selected.refreshRate
                                    });
                                }
                            }

                            StyledComboBox {
                                id: refreshBox
                                Layout.fillWidth: true
                                buttonIcon: "refresh"
                                model: root.refreshRatesFor(root.selectedOutput, `${root.selected?.width}x${root.selected?.height}`).map(rate => `${rate} Hz`)
                                Binding {
                                    target: refreshBox
                                    property: "currentIndex"
                                    value: refreshBox.model.indexOf(`${Math.round(root.selected?.refreshRate ?? 0)} Hz`)
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                onActivated: index => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { refreshRate: parseInt(model[index]) });
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Scale")
                            ConfigSelectionArray {
                                currentValue: root.selected?.scale ?? 1
                                options: [
                                    { displayName: "100%", value: 1 },
                                    { displayName: "125%", value: 1.25 },
                                    { displayName: "150%", value: 1.5 },
                                    { displayName: "175%", value: 1.75 },
                                    { displayName: "200%", value: 2 }
                                ]
                                onSelected: newValue => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { scale: newValue });
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Rotation")
                            ConfigSelectionArray {
                                currentValue: root.selected?.transform ?? 0
                                options: [
                                    { displayName: "0", value: 0 },
                                    { displayName: "90", value: 1 },
                                    { displayName: "180", value: 2 },
                                    { displayName: "270", value: 3 }
                                ]
                                onSelected: newValue => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { transform: newValue });
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Position")
                            ConfigRow {
                                uniform: true
                                ConfigSpinBox {
                                    id: posX
                                    text: "X"
                                    from: -20000
                                    to: 20000
                                    stepSize: 10
                                    Binding {
                                        target: posX
                                        property: "value"
                                        value: root.selected?.x ?? 0
                                        restoreMode: Binding.RestoreBindingOrValue
                                    }
                                    onValueChanged: {
                                        if (root.selected && value !== root.selected.x)
                                            root.patch(root.selected.name, { x: value });
                                    }
                                }
                                ConfigSpinBox {
                                    id: posY
                                    text: "Y"
                                    from: -20000
                                    to: 20000
                                    stepSize: 10
                                    Binding {
                                        target: posY
                                        property: "value"
                                        value: root.selected?.y ?? 0
                                        restoreMode: Binding.RestoreBindingOrValue
                                    }
                                    onValueChanged: {
                                        if (root.selected && value !== root.selected.y)
                                            root.patch(root.selected.name, { y: value });
                                    }
                                }
                            }
                        }

                        ContentSubsection {
                            title: "VRR"
                            tooltip: Translation.tr("Variable refresh rate. Fullscreen limits it to a fullscreen window, which avoids flicker some idle apps cause.")
                            ConfigSelectionArray {
                                currentValue: root.selected?.vrr ?? 0
                                options: [
                                    { displayName: Translation.tr("Off"), value: 0 },
                                    { displayName: Translation.tr("On"), value: 1 },
                                    { displayName: Translation.tr("Fullscreen"), value: 2 }
                                ]
                                onSelected: newValue => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { vrr: newValue });
                                }
                            }
                        }

                        ConfigSwitch {
                            text: Translation.tr("Allow tearing")
                            buttonIcon: "align_horizontal_left"
                            checked: Displays.tearing
                            onCheckedChanged: {
                                if (checked !== Displays.tearing)
                                    Displays.setTearing(checked);
                            }
                            StyledToolTip {
                                text: Translation.tr("Session-wide, not per display. Lets a game present without waiting for the refresh, trading a possible tear for lower latency.")
                            }
                        }

                        ContentSubsection {
                            visible: root.backlight !== null
                            title: Translation.tr("Backlight")

                            ConfigSlider {
                                id: backlightSlider
                                text: Translation.tr("Brightness")
                                buttonIcon: "brightness_6"
                                from: 0.05
                                to: 1.0
                                valueAnimationDuration: 250
                                Binding {
                                    target: backlightSlider
                                    property: "value"
                                    value: root.backlight?.brightness ?? 1.0
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                tooltipContent: `${Math.round((root.backlight?.brightness ?? 1) * 100)}%`
                                onMoved: root.backlight?.setBrightness(value)
                            }

                            // Gamma is the compositor's, not the panel's, and it
                            // applies to the whole session rather than one output.
                            // It used to sit in the night-light widget, which is
                            // not where anyone looks for a display setting.
                            ConfigSlider {
                                id: gammaSlider
                                text: Translation.tr("Gamma")
                                buttonIcon: "gradient"
                                from: Hyprsunset.gammaLowerLimit / 100
                                to: 1.0
                                valueAnimationDuration: 250
                                Binding {
                                    target: gammaSlider
                                    property: "value"
                                    value: Hyprsunset.gamma / 100
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                tooltipContent: `${Math.round(Hyprsunset.gamma)}%`
                                onMoved: Hyprsunset.setGamma(Math.round(value * 100))
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Colour")
                            tooltip: Translation.tr("Saved settings live in ~/.config/hypr/monitors.lua, which Hyprland reads on startup.")

                            ConfigSelectionArray {
                                currentValue: root.selected?.bitdepth ?? 8
                                options: [
                                    { displayName: Translation.tr("8 bit"), value: 8 },
                                    { displayName: Translation.tr("10 bit"), value: 10 }
                                ]
                                onSelected: newValue => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { bitdepth: newValue });
                                }
                            }
                            ConfigSelectionArray {
                                currentValue: root.selected?.cm ?? "srgb"
                                // Filtered by what the panel advertises. A display
                                // that reports neither PQ nor BT.2020 cannot be
                                // sent either, and offering the choice only
                                // produces a signal it has to guess at.
                                options: {
                                    const list = [{ displayName: "sRGB", value: "srgb" }];
                                    if (Displays.capabilities[root.selectedName]?.wideGamut)
                                        list.push({ displayName: Translation.tr("Wide"), value: "wide" });
                                    if (Displays.hdrCapable(root.selectedName)) {
                                        list.push({ displayName: "HDR", value: "hdr" });
                                        list.push({ displayName: Translation.tr("From EDID"), value: "hdredid" });
                                    }
                                    return list;
                                }
                                onSelected: newValue => {
                                    if (root.selected)
                                        root.patch(root.selected.name, { cm: newValue });
                                }
                            }

                            // Only meaningful once the output carries an absolute
                            // encoding: PQ fixes what a code value is worth in
                            // nits, so how bright and how saturated ordinary sRGB
                            // content looks becomes a decision nothing else can
                            // make for the display.
                            ContentSubsection {
                                visible: (root.selected?.cm ?? "srgb") !== "srgb"
                                title: Translation.tr("Mapping of ordinary content")
                                tooltip: Translation.tr("How bright and how saturated ordinary content looks while the display is in HDR.")

                                // Driven from onMoved, not onValueChanged: the
                                // latter also fires when the binding writes the
                                // value back, so the control fought its own
                                // source and settled on a number the user never
                                // chose. Previewed live, since judging these by
                                // eye is the only way to set them.
                                ConfigSlider {
                                    id: sdrLuminanceSlider
                                    valueAnimationDuration: 250
                                    text: Translation.tr("White level")
                                    buttonIcon: "exposure"
                                    // In nits, because HDR encodes absolute
                                    // luminance and this decides what an ordinary
                                    // white is worth. Bounded by the figure the
                                    // panel itself asks content to be graded for:
                                    // asking for more than it can emit only
                                    // clips.
                                    from: 50
                                    to: Math.max(200, Displays.peakLuminance(root.selectedName))
                                    stepSize: 5
                                    // Restated so the control still follows the
                                    // model after it has been dragged: dragging
                                    // writes the property and drops the binding,
                                    // which is why discarding a preview left the
                                    // handle sitting where it had been left.
                                    Binding {
                                        target: sdrLuminanceSlider
                                        property: "value"
                                        value: root.selected?.sdrMaxLuminance ?? 80
                                        restoreMode: Binding.RestoreBindingOrValue
                                    }
                                    usePercentTooltip: false
                                    tooltipContent: `${Math.round(root.selected?.sdrMaxLuminance ?? 80)} nit`
                                    onMoved: root.tuneSdr({ sdrMaxLuminance: Math.round(value) })
                                }
                                ConfigSlider {
                                    id: sdrSaturationSlider
                                    valueAnimationDuration: 250
                                    text: Translation.tr("Saturation")
                                    buttonIcon: "palette"
                                    from: 0.5
                                    to: 2.0
                                    Binding {
                                        target: sdrSaturationSlider
                                        property: "value"
                                        value: root.selected?.sdrSaturation ?? 1.0
                                        restoreMode: Binding.RestoreBindingOrValue
                                    }
                                    usePercentTooltip: false
                                    tooltipContent: `${(root.selected?.sdrSaturation ?? 1.0).toFixed(2)}x`
                                    onMoved: root.tuneSdr({ sdrSaturation: root.round2(value) })
                                }
                            }
                        }

                        // The monitor's own controls, read from it rather than
                        // fixed: what a panel exposes over DDC is what shows, and
                        // only settings the compositor cannot reach appear here,
                        // so nothing has two owners.
                        ContentSubsection {
                            visible: MonitorDdc.hasControls(root.selectedName)
                            title: Translation.tr("Monitor")
                            tooltip: Translation.tr("Read from the monitor itself. These are its hardware controls, applied over DDC and confirmed by reading them back.")

                            // Driven straight off the feature list. The read-back
                            // that follows a write does not rebuild the control
                            // under the pointer, because writes are coalesced in
                            // MonitorDdc and the read is deferred until the drag
                            // settles, so there is no churn mid-drag to lose.
                            Repeater {
                                model: MonitorDdc.featuresFor(root.selectedName)

                                delegate: Loader {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    sourceComponent: modelData.kind === "C" ? continuousControl : listControl

                                    // Value read from the separate live map, not
                                    // from the model row, so a read-back updates
                                    // the number without rebuilding the control and
                                    // taking its focus.
                                    readonly property int ddcCurrent: MonitorDdc.currentOf(root.selectedName, modelData.vcp)

                                    Component {
                                        id: continuousControl
                                        ConfigSlider {
                                            id: ddcSlider
                                            text: Translation.tr(modelData?.name ?? "")
                                            buttonIcon: modelData?.icon ?? ""
                                            from: 0
                                            to: MonitorDdc.maxOf(root.selectedName, modelData?.vcp ?? "")
                                            stepSize: 1
                                            usePercentTooltip: false
                                            // Follows the live value when idle, the
                                            // drag drives it directly, and the
                                            // binding is restored once the read-back
                                            // lands so a rejected change corrects.
                                            Binding {
                                                target: ddcSlider
                                                property: "value"
                                                value: ddcCurrent >= 0 ? ddcCurrent : 0
                                                restoreMode: Binding.RestoreBindingOrValue
                                            }
                                            tooltipContent: `${Math.round(ddcSlider.value)}`
                                            onMoved: MonitorDdc.setValue(root.selectedName, modelData.vcp, Math.round(value))
                                        }
                                    }

                                    Component {
                                        id: listControl
                                        ContentSubsection {
                                            title: Translation.tr(modelData.name)
                                            StyledComboBox {
                                                Layout.fillWidth: true
                                                buttonIcon: modelData.icon
                                                model: modelData.values.map(v => v.label)
                                                currentIndex: modelData.values.findIndex(v => parseInt(v.code, 16) === ddcCurrent)
                                                onActivated: index => {
                                                    const code = parseInt(modelData.values[index].code, 16);
                                                    MonitorDdc.setValue(root.selectedName, modelData.vcp, code);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Read straight from the panel's EDID, so it fills in for
                        // whatever is connected -- including a screen that offers
                        // no DDC controls at all. Facts, not settings.
                        ContentSubsection {
                            visible: MonitorDdc.infoFor(root.selectedName).length > 0
                            title: Translation.tr("About this display")

                            readonly property var infoLabels: ({
                                "model": Translation.tr("Model"),
                                "vendor": Translation.tr("Made by"),
                                "made": Translation.tr("Made"),
                                "size": Translation.tr("Size"),
                                "depth": Translation.tr("Colour depth"),
                                "panel": Translation.tr("Panel"),
                                "gamut": Translation.tr("Gamut"),
                                "hdr": Translation.tr("HDR")
                            })

                            Repeater {
                                model: MonitorDdc.infoFor(root.selectedName)
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledText {
                                        text: infoLabels[modelData.key] ?? modelData.key
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                    Item { Layout.fillWidth: true }
                                    StyledText {
                                        Layout.maximumWidth: parent.width * 0.62
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideRight
                                        text: modelData.value
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true; implicitHeight: 0 }
    }
    }

    // Floated over the content rather than placed in the column: appearing and
    // disappearing must not resize the canvas underneath, which would shift the
    // very displays the user is aiming at.
    Rectangle {
        id: banner

        // Validated even when nothing was edited: the compositor can already be
        // in a state this page would refuse to produce, and saying so beats
        // letting Apply fail later.
        readonly property string problem: root.draft.length > 0 ? Displays.validate(root.draft) : ""
        readonly property bool bad: banner.problem.length > 0 || Displays.lastError.length > 0
        readonly property bool actionable: root.dirty || banner.problem.length > 0
        readonly property string message: Displays.lastError.length > 0 ? Displays.lastError
            : banner.problem.length > 0 ? banner.problem
            : Translation.tr("Unapplied changes")

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 20
        }
        implicitHeight: actionRow.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: banner.bad ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
        opacity: (banner.actionable || Displays.lastError.length > 0) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: actionRow
            anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 10
                topMargin: 10
                bottomMargin: 10
            }
            spacing: 10

            MaterialSymbol {
                text: banner.bad ? "error" : "edit"
                iconSize: Appearance.font.pixelSize.huge
                color: banner.bad ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: banner.message
                font.pixelSize: Appearance.font.pixelSize.normal
                color: banner.bad ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
            }

            // Nothing left to act on, the banner is only carrying a message.
            DialogButton {
                visible: !banner.actionable && Displays.lastError.length > 0
                buttonText: Translation.tr("Got it")
                onClicked: Displays.lastError = ""
            }
            DialogButton {
                visible: banner.actionable
                buttonText: Translation.tr("Discard")
                onClicked: {
                    Displays.lastError = "";
                    Displays.discardSdrPreview();
                    root.resetDraft();
                }
            }
            RippleButtonWithIcon {
                visible: banner.actionable
                materialIcon: Displays.busy ? "hourglass" : "check"
                mainText: Displays.busy ? Translation.tr("Applying") : Translation.tr("Apply")
                enabled: root.dirty && !banner.bad && !Displays.busy
                onClicked: Displays.apply(root.draft)
            }
        }
    }


    Rectangle {
        anchors.fill: parent
        visible: Displays.awaitingConfirmation
        color: Appearance.colors.colScrim

        // Takes focus while it is up so the key lands here rather than on the
        // window, where it closes everything: walking away from a layout nobody
        // has confirmed yet has to mean refusing it, not keeping it.
        focus: Displays.awaitingConfirmation
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Displays.revert();
                event.accepted = true;
            }
        }
        onVisibleChanged: if (visible) forceActiveFocus()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        Rectangle {
            anchors.centerIn: parent
            implicitWidth: 420
            implicitHeight: confirmColumn.implicitHeight + 48
            radius: Appearance.rounding.large
            // The themed surface colour is solved against the shell's
            // transparency. A dialog asking whether the screen still works has
            // to be readable over whatever it is covering.
            color: Appearance.m3colors.m3surfaceContainerHigh

            ColumnLayout {
                id: confirmColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 24
                }
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Keep these display settings?")
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Reverting in %1 s").arg(Displays.secondsLeft)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                }
                StyledProgressBar {
                    Layout.fillWidth: true
                    value: Displays.secondsLeft / Math.max(1, Displays.revertSeconds)
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    Item { Layout.fillWidth: true }
                    DialogButton {
                        buttonText: Translation.tr("Revert now")
                        onClicked: Displays.revert()
                    }
                    RippleButtonWithIcon {
                        materialIcon: "check"
                        mainText: Translation.tr("Keep")
                        onClicked: Displays.confirm()
                    }
                }
            }
        }
    }
}
