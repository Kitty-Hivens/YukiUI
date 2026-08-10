pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * The applications that appeared on this machine lately.
 *
 * Kept as a ledger of when each one was first seen rather than read off the
 * `.desktop` files, whose dates say when a package was last written and not when
 * it arrived: a routine system update touches most of them in one go.
 *
 * The first sweep stamps everything already installed and offers none of it. A
 * fresh install therefore has an empty list, which is also true of the thing this
 * copies, and entries age out rather than accumulating.
 */
Singleton {
    id: root

    /// How long an application counts as new for.
    readonly property int days: 14
    readonly property int limit: 6

    readonly property var ledger: {
        const seen = {};
        for (const line of Persistent.states.startMenu.appFirstSeen) {
            const split = line.indexOf("=");
            if (split > 0)
                seen[line.slice(0, split)] = Number(line.slice(split + 1));
        }
        return seen;
    }

    /// Newest first, and only what arrived after the ledger was seeded.
    readonly property var entries: {
        const seededAt = Persistent.states.startMenu.seededAt;
        if (seededAt <= 0)
            return [];
        const cutoff = Date.now() - root.days * 24 * 60 * 60 * 1000;
        return [...DesktopEntries.applications.values].filter(entry => {
            const first = root.ledger[entry.id];
            return first !== undefined && first > seededAt && first >= cutoff;
        }).sort((a, b) => root.ledger[b.id] - root.ledger[a.id]).slice(0, root.limit);
    }

    /// Adds whatever is installed but unrecorded. Runs when the list of installed
    /// applications changes, which is when one can have appeared.
    function record() {
        if (!Persistent.ready)
            return;
        const now = Date.now();
        const known = root.ledger;
        const added = [];
        for (const entry of DesktopEntries.applications.values)
            if (known[entry.id] === undefined)
                added.push(`${entry.id}=${now}`);
        if (added.length === 0)
            return;
        Persistent.states.startMenu.appFirstSeen = [...Persistent.states.startMenu.appFirstSeen, ...added];
        if (Persistent.states.startMenu.seededAt <= 0)
            Persistent.states.startMenu.seededAt = now;
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.record();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.record();
        }
    }
}
