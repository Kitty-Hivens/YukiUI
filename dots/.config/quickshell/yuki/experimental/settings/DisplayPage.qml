pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services
import qs.experimental.looks
import "../../core/functions/arrange.js" as Arrange

// The displays, laid out as Windows lays out its display settings: the
// arrangement on top, then brightness and colour, scale and layout, and the
// finer points of the chosen display.
//
// A choice from a list takes effect at once and asks to be kept, the way
// Windows does it, and goes back by itself when nobody answers. Dragging the
// arrangement and tuning how ordinary content looks in HDR are judged as a
// whole, so they wait for Apply. All of it goes through Displays, which checks
// a layout with the compositor before sending it and writes it to monitors.lua
// once kept.
//
// Brightness and night light belong to the running shell, which owns the
// panels' backlight and the night light schedule. They are read and set
// through it rather than by a second copy of those services in this window.
ColumnLayout {
    id: root

    property var settings
    property var catalogue
    property var shell

    property var draft: []
    property string selectedName: ""
    /** Edited here and not yet applied, as opposed to the hardware changing. */
    property bool userEdited: false

    readonly property var selected: root.draft.find(entry => entry.name === root.selectedName) ?? null
    readonly property var selectedOutput: Displays.outputs.find(output => output.name === root.selectedName) ?? null
    readonly property bool locked: Displays.busy || Displays.awaitingConfirmation || Displays.state === Displays.stateReverting
    readonly property string problem: root.draft.length > 0 ? Displays.validate(root.draft) : ""
    readonly property bool dirty: root.userEdited && root.signature(root.draft) !== root.signature(Displays.currentPlan())

    // What the shell reports, "none" for a display whose brightness it cannot set.
    property string brightness: "none"
    property bool nightLight: false
    property bool shellAnswered: false

    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]

    /**
     * The scale Hyprland runs a mode at when asked for one: the scale itself
     * when it leaves the screen a whole number of points across and down, and
     * otherwise the nearest that does, looked for as Hyprland looks, in steps
     * of 1/120, above first. Offered as asked, 175% on a 1080p screen was run
     * at another scale without a word, and the layout worked out from the one
     * asked for no longer met its neighbours.
     */
    function cleanScale(width: int, height: int, scale: real): real {
        const fits = candidate => {
            const across = width / candidate;
            const down = height / candidate;
            return across === Math.round(across) && down === Math.round(down);
        };
        if (width <= 0 || height <= 0 || fits(scale))
            return scale;
        const steps = Math.round(scale * 120);
        if (fits(steps / 120))
            return steps / 120;
        for (let i = 1; i < 90; i++) {
            if (fits((steps + i) / 120))
                return (steps + i) / 120;
            if (fits((steps - i) / 120))
                return (steps - i) / 120;
        }
        // Hyprland gives up and uses its own default then. Nothing better to offer.
        return scale;
    }
    readonly property var orientations: [
        { value: 0, text: Translation.tr("Landscape") },
        { value: 1, text: Translation.tr("Portrait") },
        { value: 2, text: Translation.tr("Landscape (flipped)") },
        { value: 3, text: Translation.tr("Portrait (flipped)") }
    ]
    readonly property var vrrModes: [
        { value: 0, text: Translation.tr("Off") },
        { value: 1, text: Translation.tr("On") },
        { value: 2, text: Translation.tr("Fullscreen") },
        { value: 3, text: Translation.tr("Video and games") }
    ]
    readonly property var colourModes: {
        const list = [{ value: "srgb", text: "sRGB" }];
        if (Displays.capabilities[root.selectedName]?.wideGamut)
            list.push({ value: "wide", text: Translation.tr("Wide") });
        if (Displays.hdrCapable(root.selectedName)) {
            list.push({ value: "hdr", text: "HDR" });
            list.push({ value: "hdredid", text: Translation.tr("From EDID") });
        }
        return list;
    }

    /** What tells one layout from another, the whole of it shifted to the origin. */
    function signature(plan): string {
        return JSON.stringify(Arrange.normalize(plan).map(entry => [
            entry.name, entry.enabled === true,
            entry.enabled ? entry.x : 0, entry.enabled ? entry.y : 0,
            entry.width, entry.height, Math.round(entry.refreshRate),
            entry.scale, entry.transform, entry.bitdepth, entry.cm,
            entry.vrrOverride ? entry.vrr : null,
            entry.sdrMaxLuminance, entry.sdrSaturation
        ]).sort((a, b) => a[0] < b[0] ? -1 : 1));
    }

    function resetDraft() {
        root.draft = Displays.currentPlan();
        root.userEdited = false;
        if (root.draft.length > 0 && !root.draft.some(entry => entry.name === root.selectedName))
            root.selectedName = root.primaryName();
    }

    // The display at the origin, or the one nearest it.
    function primaryName(): string {
        const active = root.draft.filter(entry => entry.enabled);
        const pool = active.length > 0 ? active : root.draft;
        return pool.reduce((best, entry) => Math.abs(entry.x) + Math.abs(entry.y) < Math.abs(best.x) + Math.abs(best.y) ? entry : best, pool[0]).name;
    }

    function patch(name: string, changes) {
        root.draft = root.draft.map(entry => entry.name === name ? Object.assign({}, entry, changes) : entry);
        root.userEdited = true;
    }

    /** A choice that takes effect now and asks to be kept. */
    function change(changes) {
        if (!root.selected)
            return;
        const before = root.selected;
        root.patch(before.name, changes);
        root.draft = Arrange.keepTogether(root.draft, before.name, before);
        if (!Displays.apply(root.draft))
            root.resetDraft();
    }

    // Switched on from here there is no drop point to go by, and an output that
    // is off reports no position, so it goes to the right of the others.
    // Switched off, the others close up the gap it leaves.
    function setEnabled(on: bool) {
        if (!root.selected)
            return;
        if (!on) {
            const name = root.selected.name;
            root.patch(name, { enabled: false });
            root.draft = Arrange.closeGap(root.draft, name);
            if (!Displays.apply(root.draft))
                root.resetDraft();
            return;
        }
        const at = Arrange.placeSwitchedOn(root.draft, root.selected.name);
        const placed = root.draft.map(entry => entry.name === root.selected.name ? Object.assign({}, entry, { enabled: true, x: at.x, y: at.y }) : entry);
        const settled = Arrange.resolveOverlap(placed, root.selected.name, at.x, at.y);
        root.change({ enabled: true, x: settled.x, y: settled.y });
    }

    function tuneSdr(changes) {
        if (!root.selected)
            return;
        root.patch(root.selected.name, changes);
        const entry = root.draft.find(item => item.name === root.selectedName);
        Displays.previewSdr(entry.name, entry.sdrMaxLuminance, entry.sdrSaturation);
    }

    // A display with no list of modes, virtual ones, still has the one it runs at.
    function resolutionsFor(output): var {
        const seen = [];
        for (const mode of output?.availableModes ?? []) {
            const parsed = /^(\d+)x(\d+)@/.exec(mode);
            if (parsed && !seen.includes(`${parsed[1]}x${parsed[2]}`))
                seen.push(`${parsed[1]}x${parsed[2]}`);
        }
        if (seen.length === 0 && root.selected)
            seen.push(`${root.selected.width}x${root.selected.height}`);
        return seen;
    }

    function ratesFor(output, resolution: string): var {
        const rates = [];
        for (const mode of output?.availableModes ?? []) {
            const parsed = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(mode);
            if (!parsed || `${parsed[1]}x${parsed[2]}` !== resolution)
                continue;
            const rate = Math.round(parseFloat(parsed[3]));
            if (!rates.includes(rate))
                rates.push(rate);
        }
        if (rates.length === 0 && root.selected)
            rates.push(Math.round(root.selected.refreshRate));
        return rates.sort((a, b) => b - a);
    }

    // Asked again once a read already under way is over, not by starting it
    // over: the answer for the display selected before came back after the
    // selection had moved and was shown for the new one.
    function readShell() {
        if (shellState.running) {
            shellState.again = true;
            return;
        }
        shellState.asked = root.selectedName;
        shellState.command = ["sh", "-c", "qs -p \"$1\" ipc call brightness level \"$2\"; qs -p \"$1\" ipc call nightLight status", "display-page", Quickshell.shellPath("shell.qml"), root.selectedName];
        shellState.running = true;
    }

    Component.onCompleted: {
        root.resetDraft();
        Displays.reload();
        root.readShell();
        if (root.settings)
            root.settings.displaysTouched = true;
    }
    onSelectedNameChanged: root.readShell()

    // Leaving the page takes back how HDR content was being previewed: kept,
    // the screen went on showing values the config did not have, and the page
    // came back with no way to see or discard the difference.
    Component.onDestruction: {
        Displays.discardSdrPreview();
        Displays.polling = false;
    }

    // Only while someone is looking: the service polls the compositor. Not
    // put back when the page goes, which would leave it polling for as long as
    // the window stays open.
    Binding {
        target: Displays
        property: "polling"
        value: root.Window.window?.active ?? true
        restoreMode: Binding.RestoreNone
    }

    Connections {
        target: Displays

        // A display appearing or going away is the machine changing, not an
        // edit to hold on to.
        function onOutputsChanged() {
            const live = Displays.currentPlan();
            const sameSet = live.length === root.draft.length && live.every(entry => root.draft.some(item => item.name === entry.name && item.usable === entry.usable));
            if (!sameSet || !root.userEdited || root.draft.length === 0)
                root.resetDraft();
        }
        function onPersisted() {
            root.resetDraft();
        }
        function onApplyFailed() {
            root.resetDraft();
        }
        // Back to idle after a revert, the compositor is about to report the
        // layout it went back to, and that is what the page should follow.
        function onStateChanged() {
            if (Displays.state === Displays.stateIdle && Displays.pendingPlan === null)
                root.userEdited = false;
        }
    }

    Process {
        id: shellState
        property string asked: ""
        property bool again: false
        onRunningChanged: {
            if (!shellState.running && shellState.again) {
                shellState.again = false;
                root.readShell();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (shellState.asked !== root.selectedName)
                    return;
                // Anything but the two answers means the shell was not there
                // to ask, and then there is nothing to show for either.
                const lines = text.trim().split("\n").map(line => line.trim());
                root.shellAnswered = lines.length === 2 && ["on", "off"].includes(lines[1]);
                root.brightness = root.shellAnswered && /^\d+$/.test(lines[0]) ? lines[0] : "none";
                root.nightLight = root.shellAnswered && lines[1] === "on";
            }
        }
    }
    Timer {
        running: root.Window.window?.active ?? true
        repeat: true
        interval: 3000
        onTriggered: root.readShell()
    }
    Timer {
        id: readSoon
        interval: 400
        onTriggered: root.readShell()
    }

    spacing: ExLooks.spacing.s

    DisplayArrangement {
        Layout.fillWidth: true
        Layout.preferredHeight: 240
        enabled: !root.locked
        plan: root.draft
        selectedName: root.selectedName
        onPicked: name => root.selectedName = name
        onMoved: (name, x, y) => root.patch(name, { x: x, y: y })
    }

    // Arranging and tuning HDR content wait here to be applied as a whole.
    RowLayout {
        Layout.fillWidth: true
        visible: root.dirty || root.problem.length > 0
        spacing: ExLooks.spacing.s

        ExGlyph {
            visible: root.problem.length > 0
            text: "error"
            size: 18
            color: ExLooks.colors.destructive
        }
        ExText {
            Layout.fillWidth: true
            text: root.problem.length > 0 ? root.problem : Translation.tr("Unapplied changes")
            color: root.problem.length > 0 ? ExLooks.colors.destructive : ExLooks.colors.textDim
            wrapMode: Text.Wrap
        }
        ExButton {
            visible: root.dirty
            kind: "control"
            text: Translation.tr("Discard")
            onClicked: {
                Displays.discardSdrPreview();
                root.resetDraft();
            }
        }
        ExButton {
            visible: root.dirty
            kind: "accent"
            enabled: root.problem.length === 0 && !root.locked
            text: Displays.busy ? Translation.tr("Applying") : Translation.tr("Apply")
            onClicked: Displays.apply(root.draft)
        }
    }

    SettingsCard {
        Layout.fillWidth: true
        visible: Displays.lastError.length > 0
        glyph: "error"
        text: Translation.tr("The change did not go through")
        description: Displays.lastError

        ExButton {
            kind: "control"
            text: Translation.tr("Got it")
            onClicked: Displays.lastError = ""
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Brightness and colour")

        SettingsCard {
            Layout.fillWidth: true
            visible: root.brightness !== "none"
            glyph: "brightness_6"
            text: Translation.tr("Brightness")
            description: `${root.brightness}%`

            ExSlider {
                id: brightnessSlider
                implicitWidth: 240
                from: 0
                to: 100
                stepSize: 1
                value: parseInt(root.brightness) || 0
                // Seen on the screen as the knob moves, as on Windows, but sent
                // at most every 150 ms: a panel driven over DDC takes a moment
                // per step and would fall behind a drag. Sent once more as the
                // knob is let go.
                onMoved: {
                    if (!brightnessSend.running)
                        brightnessSend.start();
                }
                onPressedChanged: {
                    if (brightnessSlider.pressed)
                        return;
                    brightnessSend.stop();
                    root.brightness = String(Math.round(brightnessSlider.value));
                    root.shell?.call("brightness", "setLevel", [root.selectedName, Math.round(brightnessSlider.value)]);
                    readSoon.restart();
                }

                Timer {
                    id: brightnessSend
                    interval: 150
                    onTriggered: root.shell?.call("brightness", "setLevel", [root.selectedName, Math.round(brightnessSlider.value)])
                }
            }
        }
        // The switch is the shell's, the schedule and the warmth are the
        // config the shell's night light reads.
        SettingsExpander {
            Layout.fillWidth: true
            glyph: "nightlight"
            text: Translation.tr("Night light")
            description: root.shellAnswered ? Translation.tr("Warmer colours, easier on the eyes at night") : Translation.tr("Set by the running shell, which is not answering")

            control: ExSwitch {
                enabled: root.shellAnswered
                checked: root.nightLight
                onToggled: {
                    root.nightLight = checked;
                    root.shell?.call("nightLight", checked ? "enable" : "disable", []);
                    readSoon.restart();
                }
            }

            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("On a schedule")
                description: Config.options.light.night.automatic ? Translation.tr("From %1 to %2").arg(Config.options.light.night.from).arg(Config.options.light.night.to) : Translation.tr("Only when switched on")

                ExTextField {
                    id: fromField
                    visible: Config.options.light.night.automatic
                    width: 80
                    text: Config.options.light.night.from

                    Connections {
                        target: fromField.input
                        function onEditingFinished() {
                            if (/^\d{1,2}:\d{2}$/.test(fromField.text))
                                Config.options.light.night.from = fromField.text;
                            // Bound again either way: written over, the field
                            // stopped following the config.
                            fromField.text = Qt.binding(() => Config.options.light.night.from);
                        }
                    }
                }
                ExTextField {
                    id: toField
                    visible: Config.options.light.night.automatic
                    width: 80
                    text: Config.options.light.night.to

                    Connections {
                        target: toField.input
                        function onEditingFinished() {
                            if (/^\d{1,2}:\d{2}$/.test(toField.text))
                                Config.options.light.night.to = toField.text;
                            toField.text = Qt.binding(() => Config.options.light.night.to);
                        }
                    }
                }
                ExSwitch {
                    checked: Config.options.light.night.automatic
                    onToggled: Config.options.light.night.automatic = checked
                }
            }
            SettingsCard {
                Layout.fillWidth: true
                flat: true
                text: Translation.tr("Colour temperature")
                description: Translation.tr("%1 K, lower is warmer").arg(Config.options.light.night.colorTemperature)

                // Drawn from the cool end, so the knob goes right as it warms.
                ExSlider {
                    id: warmth
                    implicitWidth: 240
                    from: 0
                    to: 3500
                    stepSize: 100
                    value: 6000 - Config.options.light.night.colorTemperature
                    // Seen as the knob moves, at most every 120 ms, and once
                    // more as it is let go.
                    onMoved: {
                        if (!warmthWrite.running)
                            warmthWrite.start();
                    }
                    onPressedChanged: {
                        if (!warmth.pressed) {
                            warmthWrite.stop();
                            Config.options.light.night.colorTemperature = 6000 - Math.round(warmth.value);
                        }
                    }

                    Timer {
                        id: warmthWrite
                        interval: 120
                        onTriggered: Config.options.light.night.colorTemperature = 6000 - Math.round(warmth.value)
                    }
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: root.colourModes.length > 1
            enabled: !root.locked
            glyph: "hdr_on"
            text: Translation.tr("Colour mode")
            description: Translation.tr("What the display is sent, offered as far as the panel says it can take it")

            SettingsChoice {
                value: root.selected?.cm ?? "srgb"
                options: root.colourModes
                onPicked: mode => root.change({ cm: mode })
            }
        }
        // With an absolute encoding, how bright and how saturated ordinary
        // content looks is a decision nothing else makes. Seen live, applied
        // with Apply.
        SettingsCard {
            Layout.fillWidth: true
            visible: (root.selected?.cm ?? "srgb") !== "srgb"
            glyph: "exposure"
            text: Translation.tr("White level of ordinary content")
            description: `${Math.round(root.selected?.sdrMaxLuminance ?? 80)} nit`

            ExSlider {
                implicitWidth: 240
                from: 50
                to: Math.max(200, Displays.peakLuminance(root.selectedName))
                stepSize: 5
                value: root.selected?.sdrMaxLuminance ?? 80
                onMoved: root.tuneSdr({ sdrMaxLuminance: Math.round(value) })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: (root.selected?.cm ?? "srgb") !== "srgb"
            glyph: "palette"
            text: Translation.tr("Saturation of ordinary content")
            description: `${(root.selected?.sdrSaturation ?? 1).toFixed(2)}x`

            ExSlider {
                implicitWidth: 240
                from: 0.5
                to: 2
                stepSize: 0.05
                value: root.selected?.sdrSaturation ?? 1
                onMoved: root.tuneSdr({ sdrSaturation: Math.round(value * 100) / 100 })
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Scale and layout")
        enabled: !root.locked && root.selected !== null

        SettingsCard {
            Layout.fillWidth: true
            visible: root.draft.length > 1
            glyph: "power_settings_new"
            text: Translation.tr("Use this display")
            description: root.selected?.enabled && root.draft.filter(entry => entry.enabled).length <= 1 ? Translation.tr("The last display in use cannot be switched off") : ""

            ExSwitch {
                enabled: !(root.selected?.enabled && root.draft.filter(entry => entry.enabled).length <= 1)
                checked: root.selected?.enabled ?? false
                onToggled: root.setEnabled(checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "zoom_in"
            text: Translation.tr("Scale")
            description: Translation.tr("How big text, apps and everything else are")

            SettingsDropdown {
                readonly property var values: {
                    const width = root.selected?.width ?? 0;
                    const height = root.selected?.height ?? 0;
                    const offered = [...new Set(root.scales.map(scale => root.cleanScale(width, height, scale)))];
                    const current = root.selected?.scale ?? 1;
                    return offered.includes(current) ? offered : [...offered, current].sort((a, b) => a - b);
                }
                model: values.map(scale => `${Math.round(scale * 100)}%`)
                currentIndex: values.indexOf(root.selected?.scale ?? 1)
                onActivated: index => root.change({ scale: values[index] })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "aspect_ratio"
            text: Translation.tr("Display resolution")

            SettingsDropdown {
                model: root.resolutionsFor(root.selectedOutput)
                currentIndex: model.indexOf(`${root.selected?.width}x${root.selected?.height}`)
                onActivated: index => {
                    const parsed = /^(\d+)x(\d+)$/.exec(model[index]);
                    if (!parsed)
                        return;
                    const rates = root.ratesFor(root.selectedOutput, model[index]);
                    root.change({
                        width: parseInt(parsed[1]),
                        height: parseInt(parsed[2]),
                        refreshRate: rates[0] ?? root.selected.refreshRate
                    });
                }
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "screen_rotation"
            text: Translation.tr("Display orientation")

            SettingsDropdown {
                // A mirrored transform, 4 to 7, set outside the page is shown
                // as it is rather than as Landscape, and kept while it is the
                // one in use.
                readonly property var options: (root.selected?.transform ?? 0) >= 4
                    ? [...root.orientations, { value: root.selected.transform, text: Translation.tr("Mirrored") }] : root.orientations
                model: options.map(option => option.text)
                currentIndex: Math.max(0, options.findIndex(option => option.value === (root.selected?.transform ?? 0)))
                onActivated: index => root.change({ transform: options[index].value })
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: Translation.tr("Advanced")
        enabled: !root.locked && root.selected !== null

        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "refresh"
            text: Translation.tr("Refresh rate")

            SettingsDropdown {
                readonly property var rates: root.ratesFor(root.selectedOutput, `${root.selected?.width}x${root.selected?.height}`)
                model: rates.map(rate => `${rate} Hz`)
                currentIndex: rates.indexOf(Math.round(root.selected?.refreshRate ?? 0))
                onActivated: index => root.change({ refreshRate: rates[index] })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "speed"
            text: Translation.tr("Variable refresh rate")
            description: Translation.tr("Fullscreen keeps it to a fullscreen window, the last narrows that to video and games")

            SettingsDropdown {
                model: root.vrrModes.map(mode => mode.text)
                currentIndex: Math.max(0, root.vrrModes.findIndex(mode => mode.value === (root.selected?.vrr ?? 0)))
                onActivated: index => root.change({ vrr: root.vrrModes[index].value, vrrOverride: true })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            enabled: root.selected?.enabled ?? false
            glyph: "gradient"
            text: Translation.tr("Colour depth")

            SettingsChoice {
                value: root.selected?.bitdepth ?? 8
                options: [
                    { value: 8, text: Translation.tr("8 bit") },
                    { value: 10, text: Translation.tr("10 bit") }
                ]
                onPicked: depth => root.change({ bitdepth: depth })
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            glyph: "align_horizontal_left"
            text: Translation.tr("Allow tearing")
            description: Translation.tr("For every display. A game may present without waiting for the refresh, trading a possible tear for lower latency")

            ExSwitch {
                checked: Displays.tearing
                onToggled: Displays.setTearing(checked)
            }
        }
        SettingsCard {
            Layout.fillWidth: true
            visible: (root.selectedOutput?.description ?? "").length > 0
            glyph: "info"
            text: Translation.tr("Display information")
            description: `${root.selectedName}  ·  ${root.selectedOutput?.description ?? ""}`
        }
    }

    // Asked over the whole window, and answered with Escape as a refusal:
    // walking away from a layout nobody confirmed has to take it back.
    Popup {
        id: keep

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 440
        modal: true
        focus: true
        closePolicy: Popup.NoAutoClose
        visible: Displays.awaitingConfirmation
        padding: 0

        Overlay.modal: Rectangle {
            color: ExLooks.colors.scrim
        }
        background: ExSurface {
            radius: ExLooks.radius.panel
            elevation: 2
        }

        // Taken before the window's own Escape, which would close it.
        Shortcut {
            sequence: "Escape"
            enabled: keep.visible
            onActivated: Displays.revert()
        }

        contentItem: ColumnLayout {
            spacing: ExLooks.spacing.m

            ExText {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.xl
                Layout.leftMargin: ExLooks.spacing.xl
                Layout.rightMargin: ExLooks.spacing.xl
                text: Translation.tr("Keep these display settings?")
                role: "title"
                wrapMode: Text.Wrap
            }
            ExText {
                Layout.fillWidth: true
                Layout.leftMargin: ExLooks.spacing.xl
                Layout.rightMargin: ExLooks.spacing.xl
                text: Translation.tr("Reverting to the previous settings in %1 s").arg(Displays.secondsLeft)
                dim: true
                wrapMode: Text.Wrap
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: ExLooks.spacing.m
                implicitHeight: buttons.implicitHeight + 2 * ExLooks.spacing.l
                color: ExLooks.colors.surfaceSunken
                bottomLeftRadius: ExLooks.radius.panel
                bottomRightRadius: ExLooks.radius.panel

                RowLayout {
                    id: buttons
                    anchors.fill: parent
                    anchors.margins: ExLooks.spacing.l
                    spacing: ExLooks.spacing.s

                    ExButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        kind: "accent"
                        text: Translation.tr("Keep changes")
                        onClicked: Displays.confirm()
                    }
                    ExButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        kind: "control"
                        text: Translation.tr("Revert")
                        onClicked: Displays.revert()
                    }
                }
            }
        }
    }
}
