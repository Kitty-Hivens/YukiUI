import QtQuick

import qs.common.widgets
import qs.core.services
import qs.experimental.looks

// The authentication prompt, on every screen while a request is pending. The
// window handling is the shared prompt's. The card is this environment's.
FullscreenPolkitWindow {
    id: root

    /**
     * What is typed, the same on every screen. The keys go to whichever
     * screen the compositor focused, which need not be the one looked at.
     */
    property string typed: ""
    /** The last answer was refused, until something new is typed. */
    property bool failed: false

    signal refused()

    function forget() {
        root.typed = "";
        root.failed = false;
    }

    Connections {
        target: PolkitService
        // A new request can arrive while the card of the last one is still
        // leaving, and would open on what was typed and refused there.
        function onFlowChanged() {
            root.forget();
        }
        function onAuthenticationFailed() {
            root.typed = "";
            root.failed = true;
            root.refused();
        }
    }
    Connections {
        target: PolkitService.flow
        // A further question in the same request starts from an empty field,
        // not from the answer to the one before.
        function onIsResponseRequiredChanged() {
            if (PolkitService.flow.isResponseRequired)
                root.typed = "";
        }
    }

    // Room for the card to leave.
    lingerMs: ExLooks.motion.fast
    contentComponent: Component {
        ExPolkitContent {
            prompt: root
        }
    }
}
