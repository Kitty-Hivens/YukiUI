import QtQuick
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.services

// The disks the system and the home folder are on, each once, for a page to list.
Scope {
    id: root

    /** { target, size, used, share }, in bytes. */
    property var disks: []

    /** "12,3 GB", in the units a disk is sold in and the shell's own numbers. */
    function bytes(value: real): string {
        const units = [Translation.tr("B"), Translation.tr("KB"), Translation.tr("MB"), Translation.tr("GB"), Translation.tr("TB")];
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000;
            unit++;
        }
        const digits = value >= 100 || unit === 0 ? 0 : 1;
        return `${Number(value).toLocaleString(Qt.locale(Translation.languageCode), "f", digits)} ${units[unit]}`;
    }

    Process {
        running: true
        // Told apart by the device, not by where it is mounted: a home on a
        // subvolume of the system's disk is the same disk twice.
        command: ["df", "-B1", "--output=source,size,used,target", "/", Directories.home.replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set();
                root.disks = text.trim().split("\n").slice(1).map(line => line.trim().split(/\s+/))
                    .filter(fields => fields.length >= 4 && !seen.has(fields[0]) && seen.add(fields[0]))
                    .map(fields => ({
                        size: Number(fields[1]),
                        used: Number(fields[2]),
                        share: Number(fields[1]) > 0 ? Number(fields[2]) / Number(fields[1]) : 0,
                        target: fields.slice(3).join(" ")
                    }));
            }
        }
    }
}
