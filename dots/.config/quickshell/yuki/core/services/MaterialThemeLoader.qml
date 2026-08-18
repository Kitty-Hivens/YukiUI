pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import qs.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    function reapplyTheme() {
        themeFileView.reload()
    }

    /// HSL lightness of a "#rrggbb", taken from the file rather than read back off
    /// m3background. With transitions on that property answers with the colour it is
    /// currently animating through, which for the whole of the change is still the
    /// outgoing theme's, so asking it which theme this is would always be a step late.
    function paletteIsDark(hex) {
        const digits = String(hex).replace("#", "");
        if (digits.length < 6)
            return Appearance.m3colors.darkmode;
        const r = parseInt(digits.substr(0, 2), 16) / 255;
        const g = parseInt(digits.substr(2, 2), 16) / 255;
        const b = parseInt(digits.substr(4, 2), 16) / 255;
        return (Math.max(r, g, b) + Math.min(r, g, b)) / 2 < 0.5;
    }

    function applyColors(fileContent) {
        const json = JSON.parse(fileContent)
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                // Convert snake_case to CamelCase
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const m3Key = `m3${camelCaseKey}`
                Appearance.m3colors[m3Key] = json[key]
            }
        }

        const dark = root.paletteIsDark(json["background"])
        if (!Appearance.m3colors.transitionsEnabled) {
            // The first palette of the session replaces the colours declared in
            // Appearance, and fading that in would make every start look like a theme
            // change. Transitions begin after it.
            Appearance.m3colors.darkmode = dark
            Appearance.m3colors.transitionsEnabled = true
        } else if (dark !== Appearance.m3colors.darkmode) {
            // Halfway, where the colours are furthest from both themes. Whatever picks
            // an asset or a branch by this flag -- icon variants, the syntax theme --
            // swaps under cover rather than snapping against the outgoing colours.
            darkmodeFlip.pendingDark = dark
            darkmodeFlip.restart()
        }
    }

    Timer {
        id: darkmodeFlip
        property bool pendingDark: false
        interval: Appearance.m3colors.transitionDuration / 2
        repeat: false
        onTriggered: Appearance.m3colors.darkmode = darkmodeFlip.pendingDark
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            const fileContent = themeFileView.text()
            root.applyColors(fileContent)
        }
        onLoadFailed: root.resetFilePathNextTime();
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", currentlyDark ? "light" : "dark", "--noswitch"]);
    }

    GlobalShortcut {
        name: "toggleLightDark"
        description: "Toggles between dark theme and light theme"

        onPressed: {
            root.toggleLightDark();
        }
    }

    IpcHandler {
        target: "theme"

        function toggleLightDark(): void {
            root.toggleLightDark();
        }
    }
}
