// Tells a panel that appears under a still pointer that the pointer is on it.
//
// Hyprland works out which surface the pointer is over when the pointer moves.
// A layer surface that maps under a pointer standing still, a sidebar or any
// other panel opened from the keyboard or from a click that did not move the
// mouse, never gets the pointer: no enter, no hover, and clicks go on to
// whatever was under the pointer before, until the mouse is nudged. The same
// happens the other way when a panel goes away.
//
// This works it out again whenever a layer surface opens or closes, the same
// way moving the mouse would, and does nothing else. It stays out of the way
// while an application has the pointer locked or confined.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener openedListener;
    CHyprSignalListener closedListener;

    // Deferred to the next turn of the event loop, once the surface has its
    // place on the screen, rather than while it is still being mapped.
    void refocusSoon() {
        if (!g_pEventLoopManager)
            return;
        g_pEventLoopManager->doLater([] {
            // Not while an application holds the pointer, a game with raw
            // input above all. A volume display opening over it must not move
            // the pointer's focus away from what has it locked.
            if (!g_pInputManager || g_pInputManager->isConstrained() || g_pInputManager->isLocked())
                return;
            g_pInputManager->simulateMouseMovement();
        });
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    handle = h;

    const std::string serverHash = __hyprland_api_get_hash();
    const std::string clientHash = __hyprland_api_get_client_hash();
    if (serverHash != clientHash) {
        HyprlandAPI::addNotification(handle, "[layer-refocus] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[layer-refocus] version mismatch");
    }

    openedListener = Event::bus()->m_events.layer.opened.listen([](const PHLLS&) { refocusSoon(); });
    closedListener = Event::bus()->m_events.layer.closed.listen([](const PHLLS&) { refocusSoon(); });

    return {"layer-refocus", "Gives the pointer to a panel that appears under it without the mouse moving", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    openedListener.reset();
    closedListener.reset();
}
