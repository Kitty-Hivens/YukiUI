pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

Singleton {
    id: root
    property alias agent: polkitAgent
    property alias active: polkitAgent.isActive
    property alias flow: polkitAgent.flow
    property bool interactionAvailable: false
    property string cleanMessage: {
        if (!root.flow) return "";
        return root.flow.message.endsWith(".")
            ? root.flow.message.slice(0, -1)
            : root.flow.message
    }
    property string cleanPrompt: {
        const inputPrompt = PolkitService.flow?.inputPrompt.trim() ?? "";
        const cleanedInputPrompt = inputPrompt.endsWith(":") ? inputPrompt.slice(0, -1) : inputPrompt;
        const usePasswordChars = !PolkitService.flow?.responseVisible ?? true
        return cleanedInputPrompt || (usePasswordChars ? Translation.tr("Password") : Translation.tr("Input"))
    }
    /** The accounts whose password would do, users only. */
    readonly property var identities: (root.flow?.identities ?? []).filter(identity => !identity.isGroup)

    /**
     * A password was refused. Listened to here rather than on the flow: the
     * flow reports one more, for no password at all, each time the account
     * asked for changes.
     */
    signal authenticationFailed()

    // Set while the flow changes account. The flow ends the conversation
    // under the old one, which it counts as a refused password.
    property bool choosingIdentity: false

    function chooseIdentity(identity) {
        if (!root.flow || !identity || root.flow.selectedIdentity === identity)
            return;
        root.choosingIdentity = true;
        root.flow.selectedIdentity = identity;
        root.choosingIdentity = false;
        root.interactionAvailable = true;
    }

    // A request that finished while the dialog was still on screen leaves
    // nothing to answer, and the answer arrives anyway when a key was already
    // on its way down.
    function cancel() {
        root.flow?.cancelAuthenticationRequest()
    }

    function submit(response) {
        if (!root.flow)
            return;
        root.flow.submit(response)
        root.interactionAvailable = false
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            if (root.choosingIdentity)
                return;
            root.interactionAvailable = true;
            root.authenticationFailed();
        }
        // PAM can ask more than once in one go: a fingerprint and then the
        // password, or the password and then a one-time code. Each question
        // has to be answerable, not only the first.
        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired)
                root.interactionAvailable = true;
        }
    }

    PolkitAgent {
        id: polkitAgent
        onAuthenticationRequestStarted: {
            root.interactionAvailable = true;
            // The flow starts with whichever account polkit listed first,
            // which with more than one administrator need not be the one
            // signed in. Their own password is the one a person expects to
            // be asked for, wherever it would do.
            const own = root.identities.find(identity => identity.string === SystemInfo.username);
            if (own)
                root.chooseIdentity(own);
        }
    }
}
