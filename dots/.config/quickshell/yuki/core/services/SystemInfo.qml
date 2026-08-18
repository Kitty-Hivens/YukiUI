pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Provides some system info: distro, username, and what the machine is.
 */
Singleton {
    id: root
    property string distroName: "Unknown"
    property string distroId: "unknown"
    property string distroIcon: "linux-symbolic"
    property string username: "user"
    property string homeUrl: ""
    property string documentationUrl: ""
    property string supportUrl: ""
    property string bugReportUrl: ""
    property string privacyPolicyUrl: ""
    property string logo: ""
    property string desktopEnvironment: ""
    property string windowingSystem: ""
    property string hostname: ""
    property string kernel: ""
    property string compositorVersion: ""
    property string cpuModel: ""
    property int cpuThreads: 0
    property string deviceModel: ""

    // A board that was never given a name still answers the question, with
    // whatever the vendor left in the field. Those strings name no device.
    readonly property var dmiPlaceholders: ["to be filled by o.e.m.", "system product name", "default string", "not specified", "none", "system manufacturer", "o.e.m.", "invalid"]

    function namedDmi(value) {
        return value.length > 0 && root.dmiPlaceholders.indexOf(value.toLowerCase()) === -1;
    }

    /**
     * Lenovo puts the machine type code in product_name and the name people
     * actually use in product_version, while most other vendors do the
     * opposite and leave a bare number in the version. The one that reads
     * like a name wins.
     */
    function describeDevice(vendor, product, version) {
        const named = root.namedDmi(version) && !/^[\d.]+$/.test(version) ? version : product;
        const parts = [];
        if (root.namedDmi(vendor))
            parts.push(vendor);
        if (root.namedDmi(named))
            parts.push(named);
        return parts.join(" ");
    }

    // Registered trademarks in the middle of a product name carry nothing for
    // someone reading their own spec sheet.
    function tidyCpu(model) {
        return model.replace(/\((R|r|TM|tm)\)/g, "").replace(/\s+CPU\b/, "").replace(/\s{2,}/g, " ").trim();
    }

    function readFile(view) {
        try {
            view.reload();
            return view.text().trim();
        } catch (error) {
            return "";
        }
    }

    Timer {
        triggeredOnStart: true
        interval: 1
        running: true
        repeat: false
        onTriggered: {
            getUsername.running = true
            fileOsRelease.reload()
            const textOsRelease = fileOsRelease.text()

            // Extract the friendly name (PRETTY_NAME field, fallback to NAME)
            const prettyNameMatch = textOsRelease.match(/^PRETTY_NAME="(.+?)"/m)
            const nameMatch = textOsRelease.match(/^NAME="(.+?)"/m)
            distroName = prettyNameMatch ? prettyNameMatch[1] : (nameMatch ? nameMatch[1].replace(/Linux/i, "").trim() : "Unknown")

            // Extract the ID
            const idMatch = textOsRelease.match(/^ID="?(.+?)"?$/m)
            distroId = idMatch ? idMatch[1] : "unknown"

            // Extract additional URLs and logo
            const homeUrlMatch = textOsRelease.match(/^HOME_URL="(.+?)"/m)
            homeUrl = homeUrlMatch ? homeUrlMatch[1] : ""
            const documentationUrlMatch = textOsRelease.match(/^DOCUMENTATION_URL="(.+?)"/m)
            documentationUrl = documentationUrlMatch ? documentationUrlMatch[1] : ""
            const supportUrlMatch = textOsRelease.match(/^SUPPORT_URL="(.+?)"/m)
            supportUrl = supportUrlMatch ? supportUrlMatch[1] : ""
            const bugReportUrlMatch = textOsRelease.match(/^BUG_REPORT_URL="(.+?)"/m)
            bugReportUrl = bugReportUrlMatch ? bugReportUrlMatch[1] : ""
            const privacyPolicyUrlMatch = textOsRelease.match(/^PRIVACY_POLICY_URL="(.+?)"/m)
            privacyPolicyUrl = privacyPolicyUrlMatch ? privacyPolicyUrlMatch[1] : ""
            const logoFieldMatch = textOsRelease.match(/^LOGO="?(.+?)"?$/m)
            logo = logoFieldMatch ? logoFieldMatch[1] : ""

            // Update the distroIcon property based on distroId
            switch (distroId) {
                case "artix":
                case "arch": distroIcon = "arch-symbolic"; break;
                case "endeavouros": distroIcon = "endeavouros-symbolic"; break;
                case "cachyos": distroIcon = "cachyos-symbolic"; break;
                case "nixos": distroIcon = "nixos-symbolic"; break;
                case "fedora": distroIcon = "fedora-symbolic"; break;
                case "linuxmint":
                case "ubuntu":
                case "zorin":
                case "popos": distroIcon = "ubuntu-symbolic"; break;
                case "debian":
                case "raspbian":
                case "kali": distroIcon = "debian-symbolic"; break;
                case "funtoo":
                case "gentoo": distroIcon = "gentoo-symbolic"; break;
                default: distroIcon = "linux-symbolic"; break;
            }
            if (textOsRelease.toLowerCase().includes("nyarch")) {
                distroIcon = "nyarch-symbolic"
            }

            if (logo.trim().length === 0) {
                logo = distroIcon
            }

            hostname = root.readFile(fileHostname)
            kernel = root.readFile(fileKernel)

            const textCpuinfo = root.readFile(fileCpuinfo)
            cpuModel = root.tidyCpu(textCpuinfo.match(/^model name\s*:\s*(.+)$/m)?.[1] ?? "")
            cpuThreads = (textCpuinfo.match(/^processor\s*:/gm) ?? []).length

            // Not every machine has a DMI table, so a missing read is a normal
            // outcome here rather than a failure.
            deviceModel = root.describeDevice(root.readFile(fileDmiVendor),
                root.readFile(fileDmiProduct), root.readFile(fileDmiVersion))
        }
    }

    Process {
        id: getUsername
        command: ["whoami"]
        stdout: SplitParser {
            onRead: data => {
                root.username = data.trim()
            }
        }
    }

    Process {
        id: getDesktopEnvironment
        running: true
        command: ["bash", "-c", "echo $XDG_CURRENT_DESKTOP,$WAYLAND_DISPLAY"]
        stdout: StdioCollector {
            id: deCollector
            onStreamFinished: {
                const [desktop, wayland] = deCollector.text.split(",")
                root.desktopEnvironment = desktop.trim()
                root.windowingSystem = wayland.trim().length > 0 ? "Wayland" : "X11" // Are there others? 🤔
            }
        }
    }

    Process {
        id: getCompositorVersion
        running: true
        command: ["hyprctl", "version", "-j"]
        stdout: StdioCollector {
            id: versionCollector
            onStreamFinished: {
                try {
                    root.compositorVersion = (JSON.parse(versionCollector.text).tag ?? "").replace(/^v/, "")
                } catch (error) {
                    root.compositorVersion = ""
                }
            }
        }
    }

    FileView {
        id: fileOsRelease
        path: "/etc/os-release"
    }

    // From the kernel rather than /etc, which is free to disagree with it or
    // not exist at all.
    FileView {
        id: fileHostname
        path: "/proc/sys/kernel/hostname"
    }
    FileView {
        id: fileKernel
        path: "/proc/sys/kernel/osrelease"
    }
    FileView {
        id: fileCpuinfo
        path: "/proc/cpuinfo"
    }
    FileView {
        id: fileDmiVendor
        path: "/sys/devices/virtual/dmi/id/sys_vendor"
    }
    FileView {
        id: fileDmiProduct
        path: "/sys/devices/virtual/dmi/id/product_name"
    }
    FileView {
        id: fileDmiVersion
        path: "/sys/devices/virtual/dmi/id/product_version"
    }
}