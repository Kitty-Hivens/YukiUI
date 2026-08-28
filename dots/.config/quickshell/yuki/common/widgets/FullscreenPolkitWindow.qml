pragma ComponentBehavior: Bound
import qs.core.services
import QtQuick

/** The authentication prompt, on every screen, for as long as one is pending. */
FullscreenPromptWindow {
    name: "polkit"
    active: PolkitService.active
}
