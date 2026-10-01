// What minimising needs from inside the compositor. The shell does the
// minimising itself, by parking windows on special workspaces, and this plugin
// only supplies the two things it cannot reach from outside.
//
// An application's own request to be minimised. A client asking through
// xdg_toplevel.set_minimized, or through WM_CHANGE_STATE under XWayland, has
// the request stored on its surface and then dropped: no socket event, no lua
// event. Only a request made through foreign-toplevel reaches the socket, as
// `minimized>>ADDRESS,1`, and this posts that same event for the other two.
//
// Letting go of focus. A window moved to a special workspace that is not shown
// keeps keyboard focus, so typing goes on reaching a window nobody can see, and
// no dispatcher focuses nothing. hl.plugin.minimize.reset_focus() does.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/EventManager.hpp>

#include <format>
#include <utility>
#include <vector>

namespace {
    HANDLE                                                  handle = nullptr;
    CHyprSignalListener                                     openListener;
    std::vector<std::pair<PHLWINDOWREF, CHyprSignalListener>> watched;

    void announce(const PHLWINDOWREF& ref) {
        const auto window = ref.lock();
        if (!window || !g_pEventManager)
            return;
        g_pEventManager->postEvent({.event = "minimized", .data = std::format("{:x},1", reinterpret_cast<uintptr_t>(window.get()))});
    }

    CHyprSignalListener listenTo(const PHLWINDOW& window) {
        const PHLWINDOWREF ref = window;

        // The request is reset once the signal has run its course, so it is
        // still there for every listener, this one included.
        if (const auto xdg = window->m_xdgSurface.lock(); xdg && xdg->m_toplevel) {
            const WP<CXDGToplevelResource> toplevel = xdg->m_toplevel;
            return toplevel->m_events.stateChanged.listen([ref, toplevel] {
                if (const auto current = toplevel.lock(); current && current->m_state.requestsMinimize.value_or(false))
                    announce(ref);
            });
        }

        if (const auto x11 = window->m_xwaylandSurface.lock()) {
            const WP<CXWaylandSurface> surface = x11;
            return x11->m_events.stateChanged.listen([ref, surface] {
                if (const auto current = surface.lock(); current && current->m_state.requestsMinimize.value_or(false))
                    announce(ref);
            });
        }

        return nullptr;
    }

    int resetFocus(lua_State*) {
        Desktop::focusState()->resetWindowFocus();
        return 0;
    }

    void watch(const PHLWINDOW& window) {
        // Dropped along the way rather than on a destroy event: a window that
        // is gone leaves an expired reference behind, and a listener on a
        // surface that is gone never fires anyway.
        std::erase_if(watched, [](const auto& entry) { return entry.first.expired(); });

        for (const auto& [ref, listener] : watched) {
            if (ref.lock() == window)
                return;
        }

        if (auto listener = listenTo(window))
            watched.emplace_back(window, std::move(listener));
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
        HyprlandAPI::addNotification(handle, "[minimize] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[minimize] version mismatch");
    }

    openListener = Event::bus()->m_events.window.open.listen([](const PHLWINDOW& window) { watch(window); });

    HyprlandAPI::addLuaFunction(handle, "minimize", "reset_focus", resetFocus);

    // Windows that were already open when the plugin came in.
    for (const auto& window : Desktop::windowState()->windows())
        if (window && window->m_isMapped)
            watch(window);

    return {"minimize", "Passes on requests to be minimised and lets go of focus for the shell's minimising", "yuki", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    openListener.reset();
    watched.clear();
}
