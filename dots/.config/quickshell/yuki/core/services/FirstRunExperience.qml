pragma Singleton

import QtQml
import qs.core
import qs.core.functions
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string firstRunFilePath: `${Directories.state}/user/first_run.txt`
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string firstRunNotifSummary: "Welcome!"
    property string firstRunNotifBody: "Hit Super+/ for a list of keybinds"
    property string defaultWallpaperPath: FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`)

    /**
     * The welcome window of the environment that is up, or empty.
     *
     * Each environment names its own in its manifest, and one that names none
     * is not greeted with somebody else's: the welcome that used to open for
     * everybody was Illogical Impulse's, and a desktop installed without it
     * would have opened a window that is not on the disk.
     */
    readonly property string welcomeQmlPath: {
        const welcome = Environments.manifests[Environments.activeId]?.welcome ?? "";
        return welcome.length > 0 ? FileUtils.trimFileProtocol(Quickshell.shellPath(welcome)) : "";
    }
    /** A first run waiting for the environment to come up, to know whose welcome to open. */
    property bool greetingPending: false

    function load() {
        firstRunFileView.reload()
    }

    function enableNextTime() {
        Quickshell.execDetached(["rm", "-f", root.firstRunFilePath])
    }
    function disableNextTime() {
        Quickshell.execDetached(["bash", "-c", 'printf "%s\n" "$1" > "$2"', "first-run", root.firstRunFileContent, root.firstRunFilePath])
    }

    function handleFirstRun() {
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])
        root.greetingPending = true;
        root.greet();
    }

    function greet() {
        if (!root.greetingPending || Environments.activeId.length === 0)
            return;
        root.greetingPending = false;
        if (root.welcomeQmlPath.length > 0)
            Quickshell.execDetached(["qs", "-p", root.welcomeQmlPath]);
    }

    Connections {
        target: Environments
        function onActiveIdChanged() {
            root.greet();
        }
    }

    FileView {
        id: firstRunFileView
        path: Qt.resolvedUrl(firstRunFilePath)
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                firstRunFileView.setText(root.firstRunFileContent)
                root.handleFirstRun()
            }
        }
    }
}
