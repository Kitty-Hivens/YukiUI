pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.core
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string time: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
    property string shortDate: Qt.locale().toString(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM")
    property string date: Qt.locale().toString(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: Qt.locale().toString(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: Qt.locale().toString(clock.date, "dddd, MMMM dd")
    property string uptime: "0m"

    Timer {
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            fileUptime.reload();
            const textUptime = fileUptime.text();
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);

            // Convert seconds to days, hours, and minutes
            const days = Math.floor(uptimeSeconds / 86400);
            const hours = Math.floor((uptimeSeconds % 86400) / 3600);
            const minutes = Math.floor((uptimeSeconds % 3600) / 60);

            // Only the two largest units that have a value. This is read at a
            // glance rather than measured, and a machine that has been up for
            // days is not telling anyone anything with its minutes.
            const parts = [];
            if (days > 0)
                parts.push(`${days}d`);
            if (hours > 0)
                parts.push(`${hours}h`);
            if (minutes > 0)
                parts.push(`${minutes}m`);
            if (parts.length === 0)
                parts.push("0m");
            uptime = parts.slice(0, 2).join(", ");
            // Settles at a minute, which is the finest this string distinguishes.
            // At the resource poll it re-read /proc and rebuilt the same text
            // twenty times for each change it could actually show.
            interval = 60000;
        }
    }

    FileView {
        id: fileUptime

        path: "/proc/uptime"
    }
}
