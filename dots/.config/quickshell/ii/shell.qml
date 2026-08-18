//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"

// Environments, named here for one reason only: to be registered.
//
// An import builds nothing. What it does is send the scanner through the tree,
// which is how the qmldir the engine resolves types from comes to exist at all
// -- a directory nobody imports is a directory whose types are "not installed",
// however it is loaded later.
//
// Which one comes up, and whether one comes up at all, is decided at runtime
// from the manifests. An environment that is not on disk costs a warning from
// the scanner and is then simply absent.
import "environments/ii"
import "environments/waffle"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every environment
    ReloadPopup {}

    Component.onCompleted: {
        Plugins.load()
        Environments.load()
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        GameMode.load()
        Idle.load()
        HyprlandConfig.load()
    }


    // Environments
    //
    // The list, what may be switched to and what is built all come from the same
    // scan of the manifests, so there is no second table to keep in agreement
    // with the first -- which is what used to let the config name an environment
    // that no loader answered to, leaving the shell up and empty.
    function cycleEnvironment() {
        const ids = Environments.offeredIds;
        if (ids.length === 0)
            return;
        const currentIndex = ids.indexOf(Config.options.panelFamily);
        Config.options.panelFamily = ids[(currentIndex + 1) % ids.length];
    }

    // The config file is written to while the shell starts, and every write is read
    // back. The environment name reads as its default in the middle of that, which was
    // enough to build the other environment, let it claim the ipc targets both
    // register, and tear it down again -- leaving the one actually in use with
    // handlers that are registered but never reached.
    //
    // Resolved rather than taken as written: a name that is not installed comes
    // back as the fallback, so an environment removed from disk costs its panels
    // and not the whole desktop. The config keeps what it said, so putting the
    // environment back brings it back.
    property string requestedEnvironment: Config.ready ? Environments.resolve(Config.options.panelFamily) : ""
    property string settledEnvironment: ""
    property string pendingEnvironment: ""
    onRequestedEnvironmentChanged: environmentSettleTimer.restart()
    onSettledEnvironmentChanged: Environments.activeId = root.settledEnvironment

    Timer {
        id: environmentSettleTimer
        interval: 100
        onTriggered: {
            root.pendingEnvironment = root.requestedEnvironment
            root.settledEnvironment = ""
            environmentSwapTimer.restart()
        }
    }

    // The swap takes two beats, so that for one of them no environment is alive. An
    // IpcHandler registers once, when it is built: one raised while the one it
    // replaces still holds `search` and `session` is refused those targets for good,
    // and the keybinds that call them go on reaching the environment being torn down.
    Timer {
        id: environmentSwapTimer
        interval: 1
        onTriggered: root.settledEnvironment = root.pendingEnvironment
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cycleEnvironment()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cycleEnvironment()
    }
}
