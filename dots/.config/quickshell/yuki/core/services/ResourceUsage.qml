pragma Singleton
pragma ComponentBehavior: Bound

import qs.core
import qs.core.functions
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

    // The graphics card. The one that drives the screen is read all the time,
    // at the interval and with the history the processor and memory have, so
    // its graph is there and as even as theirs when it is opened: it is awake
    // anyway. Any other card is read only while someone is looking, since a
    // card that has gone to sleep is woken by being asked, and a discrete one
    // woken every few seconds drains the battery.
    //
    // A card that says how busy it is gives that. Intel's say only how fast
    // they run, and run at their fastest under almost any load, so a clock
    // read against its top showed a card a fifth busy as full and red. For
    // those the kernel's accounts of each program's time on each engine are
    // added up instead, as intel_gpu_top and gputop do, and the clock is kept
    // beside it. A card that says neither is not shown at all.
    property int gpuWatchers: 0
    /** "busy", "engines", or empty for a card that says neither. */
    property string gpuKind: ""
    /** Whether the card drives the screen, and so is read whether or not anyone looks. */
    property bool gpuDrivesScreen: false
    readonly property bool gpuReading: root.gpuKind.length > 0 && (root.gpuDrivesScreen || root.gpuWatchers > 0)
    /** How busy the card is, from 0 to 1. */
    property real gpuUsage: 0
    /** Its clock in MHz, and its fastest, for a card read by its engines. */
    property real gpuClock: 0
    property real gpuMaxClock: 0
    property string gpuClockPath: ""
    property list<real> gpuUsageHistory: []
    property string gpuReadingPath: ""
    // Unread for a while is not a flat line, so the history starts over.
    onGpuReadingChanged: {
        if (!root.gpuReading)
            root.gpuUsageHistory = [];
    }
    /** How often everything but storage is read, in milliseconds. */
    readonly property int updateInterval: Config.options?.resources?.updateInterval ?? 3000

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
            interval = root.cpuReady ? root.updateInterval : 400
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

    // Which file says it, found once as the shell starts: busy per cent where
    // the driver keeps one, as amdgpu does, and the actual clock where it keeps
    // only that, as xe and i915 do, which are then read by their engines. Last
    // on the line, whether the card is the one the screen came up on. Looking
    // only checks that the files are there and reads what does not wake a card.
    property bool gpuSearched: false
    Process {
        id: findGpuProc
        running: !root.gpuSearched
        command: ["sh", "-c", 'for card in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do '
            + 'd="$card/device"; vga=$(cat "$d/boot_vga" 2>/dev/null || echo 0); '
            + 'if [ -r "$d/gpu_busy_percent" ]; then echo "busy $d/gpu_busy_percent 0 $vga"; exit; fi; '
            + 'f="$d/tile0/gt0/freq0"; if [ -r "$f/act_freq" ]; then echo "clock $f/act_freq $(cat "$f/rp0_freq") $vga"; exit; fi; '
            + 'if [ -r "$card/gt_act_freq_mhz" ]; then echo "clock $card/gt_act_freq_mhz $(cat "$card/gt_RP0_freq_mhz") $vga"; exit; fi; '
            + 'done']
        stdout: StdioCollector {
            id: gpuFound
            onStreamFinished: {
                const fields = gpuFound.text.trim().split(/\s+/);
                root.gpuDrivesScreen = fields[3] === "1";
                if (fields[0] === "busy" && fields[1]) {
                    root.gpuKind = "busy";
                    root.gpuReadingPath = fields[1];
                } else if (fields[0] === "clock" && fields[1] && Number(fields[2]) > 0) {
                    root.gpuKind = "engines";
                    root.gpuMaxClock = Number(fields[2]);
                    root.gpuClockPath = fields[1];
                }
                root.gpuSearched = true;
            }
        }
    }
    FileView {
        id: gpuReading
        path: root.gpuReadingPath
        blockLoading: true
    }
    Timer {
        interval: root.updateInterval
        repeat: true
        triggeredOnStart: true
        running: root.gpuReading && root.gpuKind === "busy"
        onTriggered: {
            gpuReading.reload();
            const value = Number(gpuReading.text().trim());
            if (isNaN(value))
                return;
            root.gpuUsage = Math.max(0, Math.min(1, value / 100));
            root.gpuUsageHistory = [...root.gpuUsageHistory, root.gpuUsage].slice(-root.historyLength);
        }
    }

    // The engines, added up by a helper that keeps the previous accounts and
    // says one share an interval for as long as it runs: the share of the
    // whole interval, so a burst between two readings is not lost.
    FileView {
        id: gpuClockReading
        path: root.gpuClockPath
        blockLoading: true
    }
    Process {
        id: gpuEngines
        running: root.gpuReading && root.gpuKind === "engines"
        command: ["python3", "-I", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/system/gpu_busy.py")), String(root.updateInterval / 1000)]
        stdout: SplitParser {
            onRead: line => {
                const share = Number(line.trim().split(/\s+/)[0]);
                // "none" while no program's accounts can be read: nothing to
                // draw, rather than a card shown idle.
                if (isNaN(share))
                    return;
                gpuClockReading.reload();
                const clock = Number(gpuClockReading.text().trim());
                if (!isNaN(clock))
                    root.gpuClock = clock;
                root.gpuUsage = Math.max(0, Math.min(1, share));
                root.gpuUsageHistory = [...root.gpuUsageHistory, root.gpuUsage].slice(-root.historyLength);
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
