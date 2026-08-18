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
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats

    // Reading a filesystem costs a process, unlike /proc, and nothing in the
    // shell itself shows storage. Whoever displays it counts itself in, and the
    // reading runs while anyone is still watching.
    property int storageWatchers: 0
    readonly property bool storagePolling: root.storageWatchers > 0
    property string storagePath: "/"
    property real storageTotal: 0
    property real storageUsed: 0
    readonly property real storageUsedPercentage: storageTotal > 0 ? storageUsed / storageTotal : 0

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
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
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
        // The configured interval, which was being ignored: a hardcoded 1 meant both
        // /proc files were read a thousand times a second, which is load the shell
        // makes for itself and then reports as the machine's.
        interval: Config?.options.resources.updateInterval ?? 3000
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
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
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }

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
