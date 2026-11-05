import QtQuick
import Quickshell
import Quickshell.Io

// Who is signed in, as the system knows them, and the changes AccountsService
// makes for them. Read from the passwd database rather than from that service, so
// a machine without it still has an answer; written through it, because writing
// that database takes root.
Scope {
    id: root

    property string realName: ""
    property bool administrator: false
    /** Bumped when the picture has been replaced, for what draws it to read it again. */
    property int pictureRevision: 0
    /** What the last change came to, or empty. */
    property string failure: ""
    readonly property bool busy: nameWriter.running || pictureWriter.running

    function setRealName(name: string) {
        root.failure = "";
        nameWriter.wanted = name;
        nameWriter.running = true;
    }

    function setPicture(path: string) {
        root.failure = "";
        pictureWriter.source = path;
        pictureWriter.running = true;
    }

    readonly property string userObject: `/org/freedesktop/Accounts/User$(id -u)`

    Process {
        id: reader
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5; id -nG"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.realName = (lines[0] ?? "").split(",")[0].trim();
                const groups = (lines[1] ?? "").trim().split(/\s+/);
                root.administrator = groups.includes("wheel") || groups.includes("sudo");
            }
        }
    }

    Process {
        id: nameWriter
        property string wanted: ""
        command: ["sh", "-c", `busctl --system call org.freedesktop.Accounts "${root.userObject}" org.freedesktop.Accounts.User SetRealName s "$1"`, "set-name", nameWriter.wanted]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.failure = text.trim();
            }
        }
        onExited: reader.running = true
    }

    // Brought down to what an avatar needs first: the service refuses a file over
    // a megabyte, which is any photo.
    Process {
        id: pictureWriter
        property string source: ""
        command: ["sh", "-c", `made="$(mktemp --suffix=.png)" && magick "$1" -auto-orient -thumbnail 512x512^ -gravity center -extent 512x512 "$made" && busctl --system call org.freedesktop.Accounts "${root.userObject}" org.freedesktop.Accounts.User SetIconFile s "$made"; status=$?; rm -f "$made"; exit $status`, "set-picture", pictureWriter.source]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.failure = text.trim().split("\n").pop();
            }
        }
        onExited: exitCode => {
            if (exitCode === 0)
                root.pictureRevision++;
        }
    }
}
