pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.services
import qs.core.functions
import qs.common.widgets
import qs.ii.systemSettings
import qs.common

/**
 * Which backend answers each portal request, and how to change it.
 *
 * xdg-desktop-portal resolves an interface by walking a preference list and
 * publishes the answer nowhere -- not on the bus, not in its log. So "who draws
 * my file chooser" can only be answered by redoing the resolution, which is what
 * portals.py does and this page renders.
 *
 * Laid out around the two facts the configuration file cannot show. An interface
 * served through `default` rather than by a rule of its own is the ordinary case
 * and is kept quiet; the reason it lands where it does is said once above the
 * list rather than repeated on every row. An interface served by nobody is the
 * one worth interrupting for, so it gets its own section.
 */
Item {
    id: root

    // Asked of the shell rather than resolved against this file: the scanner
    // serves shell files through a qs:@/ scheme, so a relative URL from here is
    // not a path anything can execute.
    readonly property string helper: FileUtils.trimFileProtocol(Quickshell.shellPath("plugins/portals/portals.py"))

    property var report: null
    property bool restartNeeded: false
    property string lastError: ""
    /** The one row showing its options, or "" while none is. */
    property string openRow: ""

    readonly property var interfaces: root.report?.interfaces ?? []
    readonly property var ruled: root.interfaces.filter(row => row.explicit)
    readonly property var followed: root.interfaces.filter(row => !row.explicit && row.backend.length > 0)
    readonly property var unserved: root.interfaces.filter(row => row.backend.length === 0 && !row.disabled)
    readonly property var backends: root.report?.backends ?? []
    /** Files that exist, are not the one in force, and therefore do nothing. */
    readonly property var shadowed: (root.report?.config?.candidates ?? []).filter(entry => entry.exists && !entry.active)

    /** The default list, as the file spells it. */
    readonly property var defaultChain: {
        const row = root.interfaces.find(entry => !entry.explicit);
        return row ? row.preference : [];
    }

    Component.onCompleted: readProcess.running = true

    function reread() {
        readProcess.running = false;
        readProcess.running = true;
    }

    function setPreference(interfaceName, value) {
        root.openRow = "";
        writeProcess.running = false;
        writeProcess.command = ["python3", root.helper, "set", interfaceName, value];
        writeProcess.running = true;
    }

    /** The options one row offers: follow the default, any backend that can serve it, or nothing. */
    function optionsFor(row) {
        return [{
            displayName: Translation.tr("Default"),
            value: ""
        }].concat(row.providers.map(name => ({
            displayName: name,
            value: name
        }))).concat([{
            displayName: Translation.tr("Off"),
            value: "none"
        }]);
    }

    Process {
        id: readProcess
        command: ["python3", root.helper, "report"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.report = JSON.parse(text);
                    root.lastError = "";
                } catch (error) {
                    root.lastError = Translation.tr("Could not read the portal configuration");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.lastError = text.trim()
        }
    }

    Process {
        id: writeProcess
        onExited: code => {
            if (code === 0)
                root.restartNeeded = true;
            root.reread();
        }
    }

    Process {
        id: restartProcess
        command: ["systemctl", "--user", "restart", "xdg-desktop-portal.service"]
        onExited: {
            root.restartNeeded = false;
            root.reread();
        }
    }

    /** One interface: what serves it, and its options once asked for. */
    component InterfaceRow: ColumnLayout {
        id: interfaceRow
        required property var row
        property bool first: false

        Layout.fillWidth: true
        spacing: 0

        PageDivider {
            visible: !interfaceRow.first
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: interfaceRow.row.interface
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                }
                // Which backends were passed over is said once above each list,
                // because for almost every row it is the same sentence. What is
                // worth saying on a row is the case the group note cannot cover:
                // a preference naming a backend that is not installed at all,
                // which reads as a working rule and silently does nothing.
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: {
                        const missing = interfaceRow.row.skipped.filter(name => name.indexOf("(") !== -1);
                        return missing.length > 0 ? Translation.tr("not installed: %1").arg(missing.map(name => name.split(" ")[0]).join(", ")) : "";
                    }
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                text: interfaceRow.row.disabled ? Translation.tr("Off") : interfaceRow.row.backend
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                onClicked: root.openRow = root.openRow === interfaceRow.row.interface ? "" : interfaceRow.row.interface
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.openRow === interfaceRow.row.interface ? "expand_less" : "expand_more"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        ConfigSelectionArray {
            visible: root.openRow === interfaceRow.row.interface
            Layout.bottomMargin: visible ? 8 : 0
            currentValue: interfaceRow.row.explicit ? (interfaceRow.row.disabled ? "none" : interfaceRow.row.backend) : ""
            onSelected: newValue => root.setPreference(interfaceRow.row.interface, newValue)
            options: root.optionsFor(interfaceRow.row)
        }
    }

    StyledFlickable {
        id: pageFlick
        anchors.fill: parent
        clip: true
        contentHeight: pageColumn.implicitHeight + 32
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: pageColumn
            y: 16
            x: SystemPages.contentInset(pageFlick.width)
            width: SystemPages.contentWidth(pageFlick.width)
            spacing: 16

            SystemCard {
                Layout.fillWidth: true
                icon: "description"
                title: Translation.tr("Configuration in force")
                subtitle: root.report?.config?.active ?? ""

                PageNote {
                    visible: root.lastError.length > 0
                    text: root.lastError
                    color: Appearance.m3colors.m3error
                }

                // The commonest way this goes wrong is editing a file that is
                // never read: a packaged kde-portals.conf looks authoritative and
                // applies only under KDE.
                PageNote {
                    visible: root.shadowed.length > 0
                    text: Translation.tr("Present but not read here: %1").arg(root.shadowed.map(entry => entry.path).join(", "))
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 10
                    visible: root.restartNeeded

                    RippleButtonWithIcon {
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Restart portal service")
                        onClicked: restartProcess.running = true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A change is written but not in force. Restarting cancels whatever a portal is in the middle of.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            PageHeading {
                visible: root.unserved.length > 0
                text: Translation.tr("Nothing selected")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: root.unserved.length > 0

                // Stated as a fact rather than as a fault. Several of these are
                // interfaces a session of this kind never needs -- Clipboard and
                // RemoteDesktop belong to remote-desktop sessions, which nothing
                // on wlroots implements -- and reading "no answer" as an alarm is
                // what sent the first version looking for a broken clipboard.
                PageNote {
                    text: Translation.tr("Nothing in the preference list implements these, so an application asking for one gets no answer. Some are only wanted by a remote desktop session and are meant to be empty here.")
                }

                // Named because it is not derivable: whether a backend that
                // declares an interface can actually serve it in this session is
                // not written down anywhere. The gnome backend implements
                // RemoteDesktop through org.gnome.Mutter, which a wlroots session
                // does not have.
                PageNote {
                    text: Translation.tr("A backend offered below only declares the interface. Whether it can serve it here is another matter -- some are written against their own compositor.")
                }

                Repeater {
                    model: root.unserved
                    delegate: InterfaceRow {
                        required property var modelData
                        required property int index
                        row: modelData
                        first: index === 0
                    }
                }
            }

            PageHeading {
                visible: root.ruled.length > 0
                text: Translation.tr("Set here")
            }

            SystemCard {
                Layout.fillWidth: true
                visible: root.ruled.length > 0

                Repeater {
                    model: root.ruled
                    delegate: InterfaceRow {
                        required property var modelData
                        required property int index
                        row: modelData
                        first: index === 0
                    }
                }
            }

            PageHeading {
                text: Translation.tr("Following the default")
            }

            SystemCard {
                Layout.fillWidth: true

                // Said once, above the list, rather than on every row: the rows
                // below differ only in which of these got there first.
                PageNote {
                    text: root.defaultChain.length > 0
                        ? Translation.tr("Tried in order: %1. The first one that implements the interface answers it.").arg(root.defaultChain.join(" -> "))
                        : Translation.tr("No default is set, so an interface without a rule of its own is answered by nobody.")
                }

                Repeater {
                    model: root.followed
                    delegate: InterfaceRow {
                        required property var modelData
                        required property int index
                        row: modelData
                        first: index === 0
                    }
                }
            }
        }
    }
}
