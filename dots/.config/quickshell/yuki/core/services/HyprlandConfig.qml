pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.core
import qs.core.functions

/**
 * Configs Hyprland
 */
Singleton {
    id: root
    
    signal reloaded()

    // Woken from shell.qml. Everything else here is reached from the settings or
    // from the right sidebar, so without this the singleton does not exist until
    // one of those is opened -- and the watch below, which has to be running from
    // the start, would not be watching.
    function load() {}

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    function set(key: string, value: var) {
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} --set "${key}" "${value}"` //
        ])
    }
    
    function setMany(entries: var) {
        let args = ""
        for (let key in entries) {
            args += `--set "${key}" "${entries[key]}" `
        }
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}` //
        ])
    }
    
    function reset(key: string) {
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} --reset "${key}"` //
        ])
    }
    
    function resetMany(keys: list<string>) {
        let args = ""
        for (let i = 0; i < keys.length; i++) {
            args += `--reset "${keys[i]}" `
        }
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}` //
        ])
    }

    /**
     * Ask the compositor to read its config again after a setting it reads changed.
     *
     * The blur rule decides from appearance.transparency.enable whether panels
     * are see-through and worth blurring behind, and it reads that when the
     * config is parsed. Changing the setting here reparses nothing, so the
     * compositor went on believing whatever had been true at the last reload:
     * turn transparency on and the panels became see-through with nothing behind
     * them, which is worse than either state on its own.
     *
     * Not fired for the value simply becoming known at startup -- the compositor
     * read the same file for itself when it started.
     */
    property bool seeThroughKnown: false
    readonly property bool panelsAreSeeThrough: Config.options?.appearance.transparency.enable ?? false
    onPanelsAreSeeThroughChanged: {
        if (!root.seeThroughKnown) {
            root.seeThroughKnown = true;
            return;
        }
        Quickshell.execDetached(["hyprctl", "reload"]);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}
