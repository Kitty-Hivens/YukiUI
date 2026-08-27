pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root

    // Zero means not read yet. A placeholder total meant the arithmetic came out
    // at a full machine, so anything that opened before the first reading landed
    // showed a red hundred per cent of memory nobody was using.
    property real memoryTotal: 0
    property real memoryFree: 0
    readonly property real memoryUsed: memoryTotal - memoryFree
    readonly property real memoryUsedPercentage: memoryTotal > 0 ? memoryUsed / memoryTotal : 0
    property real swapTotal: 0
    property real swapFree: 0
    readonly property real swapUsed: swapTotal - swapFree
    readonly property real swapUsedPercentage: swapTotal > 0 ? swapUsed / swapTotal : 0
    property real cpuUsage: 0
    property var previousCpuStats

    /** Whether memory has been read at all. */
    readonly property bool ready: root.memoryTotal > 0
    /** Whether the processor has been read twice, which is what a figure for it takes. */
    property bool cpuReady: false

    // Reading a filesystem costs a process, unlike /proc, and nothing in the
    // shell itself shows storage. Whoever displays it counts itself in, and the
    // reading runs while anyone is still watching.
    property int storageWatchers: 0
    readonly property bool storagePolling: root.storageWatchers > 0
    property string storagePath: "/"
    property real storageTotal: 0
    property real storageUsed: 0
    readonly property real storageUsedPercentage: storageTotal > 0 ? storageUsed / storageTotal : 0

    readonly property string maxAvailableMemoryString: root.ready ? root.kbToGbString(root.memoryTotal) : ""
    readonly property string maxAvailableSwapString: root.swapTotal > 0 ? root.kbToGbString(root.swapTotal) : ""
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    // Nothing goes into a graph before it is a reading: a placeholder drawn into
    // the history is a spike that never happened, and it stays on screen for a
    // minute after it stops being wrong.
    function updateHistories() {
        if (!root.ready)
            return;
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        if (root.cpuReady)
            updateCpuUsageHistory()
    }

    Timer {
        // The first readings come quickly and the configured interval takes over
        // once they are in: a processor figure needs two of them, and a bar or a
        // window that has just opened should not sit on a dash for three seconds.
        // The interval is read from the config on every tick because it is
        // assigned here rather than bound -- and because a hardcoded 1 once meant
        // both /proc files were read a thousand times a second, which is load the
        // shell makes for itself and then reports as the machine's.
        interval: 400
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 0)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 0)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            // All ten fields of the line, not the first seven: steal and the guest
            // counters belong in the total too.
            const cpuLine = textStat.match(/^cpu\s+(.*)/)
            if (cpuLine) {
                const stats = cpuLine[1].trim().split(/\s+/).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                // Waiting on a disk is not the processor being busy. Counting iowait
                // as work is what makes a machine reading a slow disk look pinned.
                const idle = stats[3] + (stats[4] ?? 0)

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    if (totalDiff > 0) {
                        cpuUsage = 1 - idleDiff / totalDiff
                        root.cpuReady = true
                    }
                }

                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = root.cpuReady ? (Config.options?.resources?.updateInterval ?? 3000) : 400
        }
    }

    // Read on the spot rather than in the background: two small files in /proc,
    // against a first frame drawn from whatever had not arrived yet.
    FileView { id: fileMeminfo; path: "/proc/meminfo"; blockLoading: true }
    FileView { id: fileStat; path: "/proc/stat"; blockLoading: true }

    Timer {
        interval: 60000
        triggeredOnStart: true
        repeat: true
        running: root.storagePolling
        onTriggered: readStorageProc.running = true
    }

    Process {
        id: readStorageProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["df", "-Pk", root.storagePath]
        stdout: StdioCollector {
            id: storageCollector
            onStreamFinished: {
                // POSIX output, so the last line is the filesystem itself:
                // device, 1K-blocks, used, available, capacity, mount point.
                const fields = storageCollector.text.trim().split("\n").pop().trim().split(/\s+/);
                if (fields.length < 4)
                    return;
                root.storageTotal = Number(fields[1]);
                root.storageUsed = Number(fields[2]);
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
