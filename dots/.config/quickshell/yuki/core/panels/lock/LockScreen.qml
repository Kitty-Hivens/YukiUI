pragma ComponentBehavior: Bound
import qs
import qs.core.services
import qs.core
import qs.core.functions
import qs.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext
    // How long the surfaces get to animate away between the right password and
    // the lock letting go. None by default: the lock goes at once.
    property int releaseDelay: 0
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"
        Loader {
            active: GlobalStates.screenLocked
            anchors.fill: parent
            opacity: active ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            sourceComponent: root.lockSurface
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    lockContext.reset();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            if (root.releaseDelay > 0) {
                lockContext.releasing = true;
                releaseTimer.restart();
            } else {
                root.release();
            }
        }
    }

    Timer {
        id: releaseTimer
        interval: root.releaseDelay
        onTriggered: root.release()
    }

    function release() {
        // Unlock the screen before exiting, or the compositor will display a
        // fallback lock you can't interact with.
        GlobalStates.screenLocked = false;

        // Reset
        lockContext.reset();

        // Post-unlock actions
        if (lockContext.alsoInhibitIdle) {
            lockContext.alsoInhibitIdle = false;
            Idle.toggleInhibit(true);
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    // Watched rather than fired and forgotten. Nothing checked that hyprlock
    // had started, so where it is not installed or fails to come up, asking to
    // lock did nothing at all and said nothing about it -- and a screen that
    // only looks locked is the one failure this must not have.
    Process {
        id: hyprlockProc
        command: ["bash", "-c", "pidof hyprlock || hyprlock"]
        onExited: exitCode => {
            if (exitCode === 0)
                return;
            console.log("[LockScreen] hyprlock did not start, exit", exitCode, "-- locking with the built-in screen instead");
            GlobalStates.screenLocked = true;
        }
    }

    function lock() {
        // Asked for while the lock was on its way out after the right
        // password, by the idle daemon before sleep say: the lock stays
        // rather than letting go once its surfaces have left.
        if (lockContext.releasing) {
            releaseTimer.stop();
            lockContext.alsoInhibitIdle = false;
            lockContext.reset();
            lockContext.tryFingerUnlock();
            return;
        }
        if (Config.options.lock.useHyprlock) {
            hyprlockProc.running = true;
            return;
        }
        GlobalStates.screenLocked = true;
    }

    /**
     * Set while the lock was asked for without any way in, as it is before
     * sleep. The compositor counts the session locked on the lock's first
     * frame, and the idle daemon lets the machine sleep on that, so a lock
     * that fades in over the desktop went to sleep see-through. A surface
     * that animates its way in reads this and comes up whole instead.
     */
    property bool immediate: false

    function lockNow() {
        if (!Config.options.lock.useHyprlock)
            root.immediate = true;
        root.lock();
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                root.immediate = false;
        }
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    GlobalShortcut {
        name: "lockNow"
        description: "Locks the screen at once, without the lock's way in. For before sleep"

        onPressed: {
            root.lockNow()
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringDataIfUnlocked();
        }
    }
    // Both singletons may already be ready here, so onReadyChanged may never fire.
    Component.onCompleted: root.initIfReady()

    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
