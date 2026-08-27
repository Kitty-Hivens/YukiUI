pragma Singleton
import Quickshell
import qs.core.services
import qs.core

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        closeAllWindows();
        Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
    }

    /**
     * The system settings, opened on the page a button is about.
     *
     * The page is named by key rather than by path, so a caller does not have to
     * know where the window lives -- and so the answer cannot go stale in a config
     * file, which is what happened to the sound button when the shell moved
     * directories. A command named in the config still wins: that is how someone
     * puts pavucontrol, or anything else, back.
     */
    function openSystemSettings(page, externalCommand = "") {
        if (externalCommand.length > 0) {
            Quickshell.execDetached(["bash", "-c", externalCommand]);
            return;
        }
        Quickshell.execDetached(["env", `YUKIUI_SETTINGS_PAGE=${page}`, "qs", "-p", Quickshell.shellPath("systemSettings.qml")]);
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
    }

    function reboot() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
    }

    function rebootToFirmware() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
    }
}
