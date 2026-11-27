import QtQuick

import qs.core.services

// For a while: watches the shell's main thread for a few seconds after an
// application is started, and writes down every stretch it was held up for.
// Starting one sometimes left the launcher standing still until the
// application's window came, and the start itself takes a millisecond or two,
// so what holds it up comes after. Taken out once that is known.
QtObject {
    id: root

    /** How long a stretch counts as held up, in milliseconds. */
    readonly property int threshold: 80
    property string app: ""
    property real since: 0
    property real last: 0
    property var held: []

    readonly property Connections onLaunch: Connections {
        target: AppLaunch
        function onLaunched(id) {
            root.app = id;
            root.since = Date.now();
            root.last = root.since;
            root.held = [];
            ticker.restart();
            end.restart();
        }
    }

    readonly property Timer ticker: Timer {
        id: ticker
        interval: 10
        repeat: true
        onTriggered: {
            const now = Date.now();
            if (now - root.last > root.threshold)
                root.held.push(`${now - root.last} ms at +${root.last - root.since} ms`);
            root.last = now;
        }
    }

    readonly property Timer end: Timer {
        id: end
        interval: 4000
        onTriggered: {
            ticker.stop();
            if (root.held.length > 0)
                console.warn(`[LaunchWatch] after starting ${root.app} the shell was held up: ${root.held.join(", ")}`);
            else
                console.log(`[LaunchWatch] after starting ${root.app} the shell was never held up past ${root.threshold} ms`);
        }
    }
}
