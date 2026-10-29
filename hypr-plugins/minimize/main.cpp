// What minimising and maximising need from inside the compositor. The shell
// does both itself, minimising by parking windows on special workspaces and
// maximising by giving a floating window the work area, and this plugin only
// supplies what it cannot reach from outside.
//
// An application's own request to be minimised. A client asking through
// xdg_toplevel.set_minimized, or through WM_CHANGE_STATE under XWayland, has
// the request stored on its surface and then dropped: no socket event, no lua
// event. Only a request made through foreign-toplevel reaches the socket, as
// `minimized>>ADDRESS,1`, and this posts that same event for the other two.
//
// An application's own request to be maximised or put back, as
// `maximizerequest>>ADDRESS,1` or `,0`: a double click on its title bar, its
// maximise button. Hyprland would answer it with a maximise of its own, a
// kind of fullscreen that only one window per workspace can have and that is
// not raised over floating windows, so a family that maximises by itself
// suppresses that with a window rule and takes the request from here. A
// window rule leaves the request on the surface for every listener, this one
// included.
//
// A request made before the window is mapped, as an application that
// remembers being maximised makes it, is held and announced as the window
// opens: the shell has nothing to place before then. A Wayland window's
// request is gone from its surface the moment it has been heard, so the
// window is listened to from its creation rather than from its mapping, which
// heard nothing of it.
//
// Letting go of focus. A window moved to a special workspace that is not shown
// keeps keyboard focus, so typing goes on reaching a window nobody can see, and
// no dispatcher focuses nothing. hl.plugin.minimize.reset_focus() does.
//
// Telling a window how it stands: maximised or not, tiled or not. Hyprland
// tells every Wayland window as it maps that it is maximised and tiled on
// every side, which keeps applications from drawing decorations of their own,
// and an XWayland surface it never tells at all, so an X11 application drew
// itself as not maximised and its button could only ever maximise.
// hl.plugin.minimize.set_window_state(address, maximized, tiled) sets both
// and sends the window its state. Tiled means nothing to X11 and is left out.
// A GTK window told it is not maximised draws a margin for a shadow of its own,
// which Hyprland then lines up with neither its border nor its corners, so the
// shell leaves Wayland windows as Hyprland has them.
//
// A maximised window keeps its size. On Windows it fills its place until it is
// put back, and its edges cannot be pulled. Here it is an ordinary floating
// window, tagged maximized by the shell, and Hyprland resized it like any other
// from its border, from a mouse bind or at the application's request, all of
// which begin at the drag controller. A resize of a window so tagged is not
// begun there. Moving it is: pulled away, it is put back by the shell.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/EventManager.hpp>

// The C library, under C linkage.
#include <lua.hpp>

#include <algorithm>
#include <format>
#include <optional>
#include <utility>
#include <vector>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener createListener;
    CHyprSignalListener openListener;
    CFunctionHook*      dragBeginHook = nullptr;

    using DragBegin = void (*)(Layout::Supplementary::CDragStateController*, SP<Layout::ITarget>, eMouseBindMode, std::optional<Layout::eRectCorner>, bool);

    void dragBegin(Layout::Supplementary::CDragStateController* controller, SP<Layout::ITarget> target, eMouseBindMode mode, std::optional<Layout::eRectCorner> edge,
                   bool exclusiveDeviceGrab) {
        if (mode != MBIND_MOVE && target) {
            const auto window = target->window();
            if (window && window->m_ruleApplicator && window->m_ruleApplicator->m_tagKeeper.isTagged("maximized"))
                return;
        }
        reinterpret_cast<DragBegin>(dragBeginHook->m_original)(controller, std::move(target), mode, edge, exclusiveDeviceGrab);
    }

    struct SWatched {
        PHLWINDOWREF        window;
        CHyprSignalListener listener;
        /** Asked for before the window was mapped, to be announced as it opens. */
        bool                minimize = false;
        std::optional<bool> maximize;
    };
    std::vector<SWatched> watched;

    SWatched* entryFor(const PHLWINDOW& window) {
        for (auto& entry : watched)
            if (entry.window.lock() == window)
                return &entry;
        return nullptr;
    }

    void announce(const PHLWINDOWREF& ref) {
        const auto window = ref.lock();
        if (!window || !g_pEventManager)
            return;
        g_pEventManager->postEvent({.event = "minimized", .data = std::format("{:x},1", reinterpret_cast<uintptr_t>(window.get()))});
    }

    void announceMaximize(const PHLWINDOWREF& ref, bool maximize) {
        const auto window = ref.lock();
        if (!window || !g_pEventManager)
            return;
        g_pEventManager->postEvent({.event = "maximizerequest", .data = std::format("{:x},{}", reinterpret_cast<uintptr_t>(window.get()), maximize ? 1 : 0)});
    }

    // Passed on at once for a mapped window, held for one that is not yet.
    void heard(const PHLWINDOWREF& ref, bool minimize, std::optional<bool> maximize) {
        const auto window = ref.lock();
        if (!window)
            return;
        if (!window->m_isMapped) {
            if (auto* entry = entryFor(window)) {
                entry->minimize = entry->minimize || minimize;
                if (maximize.has_value())
                    entry->maximize = maximize;
            }
            return;
        }
        if (minimize)
            announce(ref);
        if (maximize.has_value())
            announceMaximize(ref, *maximize);
    }

    CHyprSignalListener listenTo(const PHLWINDOW& window) {
        const PHLWINDOWREF ref = window;

        // The request is reset once the signal has run its course, so it is
        // still there for every listener, this one included.
        if (const auto xdg = window->m_xdgSurface.lock(); xdg && xdg->m_toplevel) {
            const WP<CXDGToplevelResource> toplevel = xdg->m_toplevel;
            return toplevel->m_events.stateChanged.listen([ref, toplevel] {
                const auto current = toplevel.lock();
                if (!current)
                    return;
                heard(ref, current->m_state.requestsMinimize.value_or(false), current->m_state.requestsMaximize);
            });
        }

        // Under XWayland a request is not reset: it stays on the surface until
        // the client asks for the opposite, and every later change of state, a
        // request for fullscreen say, would announce it again. A window that
        // had minimised itself once was minimised again each time it went
        // fullscreen. So a request is spent once it is announced. Hyprland's
        // own listener was registered as the surface was created, before this
        // one, and has read it already.
        if (const auto x11 = window->m_xwaylandSurface.lock()) {
            const WP<CXWaylandSurface> surface = x11;
            return x11->m_events.stateChanged.listen([ref, surface] {
                const auto current = surface.lock();
                if (!current)
                    return;
                heard(ref, current->m_state.requestsMinimize.value_or(false), current->m_state.requestsMaximize);
                current->m_state.requestsMinimize.reset();
                current->m_state.requestsMaximize.reset();
            });
        }

        return nullptr;
    }

    // Whether a window would float if it opened now: Hyprland floats it itself,
    // as it judged when the window opened, a dialog, a window with a parent, one
    // of a fixed size, or a rule loaded now floats it. A family that tiles takes
    // every other floating window into its layout as it comes up. The rules are
    // read again for the purpose, without the one-time rules, which are gone by
    // now: what a window was given as it opened came from the family before.
    int shouldFloat(lua_State* state) {
        const std::string address = luaL_checkstring(state, 1);
        bool              floats  = false;
        for (const auto& window : Desktop::windowState()->windows()) {
            if (!window || std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) != address)
                continue;
            floats = window->m_requestsFloat;
            if (!floats && window->m_ruleApplicator) {
                window->m_ruleApplicator->readStaticRules(true);
                floats = window->m_ruleApplicator->static_.floating.value_or(false);
            }
            break;
        }
        lua_pushboolean(state, floats);
        return 1;
    }

    int resetFocus(lua_State*) {
        Desktop::focusState()->resetWindowFocus();
        return 0;
    }

    bool isTiledState(xdgToplevelState state) {
        return state == XDG_TOPLEVEL_STATE_TILED_LEFT || state == XDG_TOPLEVEL_STATE_TILED_RIGHT || state == XDG_TOPLEVEL_STATE_TILED_TOP ||
            state == XDG_TOPLEVEL_STATE_TILED_BOTTOM;
    }

    void setXdgState(const SP<CXDGToplevelResource>& toplevel, bool maximized, bool tiled) {
        auto&      states = toplevel->m_pendingApply.states;
        const auto before = states;
        std::erase_if(states, isTiledState);
        if (tiled)
            states.insert(states.end(), {XDG_TOPLEVEL_STATE_TILED_LEFT, XDG_TOPLEVEL_STATE_TILED_RIGHT, XDG_TOPLEVEL_STATE_TILED_TOP, XDG_TOPLEVEL_STATE_TILED_BOTTOM});
        const bool wasMaximized = std::ranges::find(states, XDG_TOPLEVEL_STATE_MAXIMIZED) != states.end();
        if (states == before && wasMaximized == maximized)
            return;
        // The configure is scheduled by setMaximized, and only when the
        // maximised state changes, so with the tiled states alone changed it is
        // turned over and back, which sends one configure with the lot.
        if (wasMaximized == maximized)
            toplevel->setMaximized(!maximized);
        toplevel->setMaximized(maximized);
    }

    int setWindowState(lua_State* state) {
        const std::string address   = luaL_checkstring(state, 1);
        const bool        maximized = lua_toboolean(state, 2);
        const bool        tiled     = lua_toboolean(state, 3);
        for (const auto& window : Desktop::windowState()->windows()) {
            if (!window || std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) != address)
                continue;
            if (const auto xdg = window->m_xdgSurface.lock(); xdg && xdg->m_toplevel)
                setXdgState(xdg->m_toplevel.lock(), maximized, tiled);
            else if (const auto x11 = window->m_xwaylandSurface.lock(); x11 && x11->m_maximized != maximized) {
                x11->m_maximized = maximized;
                // Sends the whole state, the maximised part with it, and
                // leaves fullscreen as it was. The state waits in the X
                // connection's buffer until something flushes it, which a
                // configure does, and one to where the window already stands
                // changes nothing: a window already as large as it is to be
                // got no configure otherwise, and never heard of its state.
                x11->setFullscreen(x11->m_fullscreen);
                x11->configure(x11->m_geometry);
            }
            break;
        }
        return 0;
    }

    void watch(const PHLWINDOW& window) {
        // Dropped along the way rather than on a destroy event: a window that
        // is gone leaves an expired reference behind, and a listener on a
        // surface that is gone never fires anyway.
        std::erase_if(watched, [](const auto& entry) { return entry.window.expired(); });

        if (entryFor(window))
            return;

        // Entered first and listened to after, so a request heard before the
        // window is mapped has somewhere to be held.
        SWatched entry;
        entry.window = window;
        watched.push_back(std::move(entry));
        if (auto listener = listenTo(window))
            entryFor(window)->listener = std::move(listener);
        else
            watched.pop_back();
    }

    // What was asked for before the window was mapped, now that it is. An X11
    // request made before this plugin listened is still on the surface, and
    // is spent here like any other.
    void announceInitial(const PHLWINDOW& window) {
        auto* entry = entryFor(window);
        bool  minimize = entry && entry->minimize;
        auto  maximize = entry ? entry->maximize : std::nullopt;
        if (const auto x11 = window->m_xwaylandSurface.lock()) {
            minimize = minimize || x11->m_state.requestsMinimize.value_or(false);
            if (!maximize.has_value())
                maximize = x11->m_state.requestsMaximize;
            x11->m_state.requestsMinimize.reset();
            x11->m_state.requestsMaximize.reset();
        }
        if (entry) {
            entry->minimize = false;
            entry->maximize.reset();
        }
        if (minimize)
            announce(window);
        if (maximize.value_or(false))
            announceMaximize(window, true);
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

    createListener = Event::bus()->m_events.window.create.listen([](const PHLWINDOW& window) { watch(window); });
    openListener   = Event::bus()->m_events.window.open.listen([](const PHLWINDOW& window) {
        watch(window);
        announceInitial(window);
    });

    HyprlandAPI::addLuaFunction(handle, "minimize", "reset_focus", resetFocus);
    HyprlandAPI::addLuaFunction(handle, "minimize", "set_window_state", setWindowState);
    HyprlandAPI::addLuaFunction(handle, "minimize", "should_float", shouldFloat);

    // Windows that were already open when the plugin came in.
    for (const auto& window : Desktop::windowState()->windows())
        if (window && window->m_isMapped)
            watch(window);

    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "dragBegin")) {
        if (match.demangled.find("CDragStateController::dragBegin") != std::string::npos) {
            target = match.address;
            break;
        }
    }
    if (target)
        dragBeginHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&dragBegin));
    if (!dragBeginHook || !dragBeginHook->hook())
        HyprlandAPI::addNotification(handle, "[minimize] could not hook the drag controller, maximised windows stay resizable", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"minimize", "Passes on requests to be minimised or maximised, keeps maximised windows from being resized, tells windows whether they are maximised or tiled, and lets go of focus for the shell's minimising", "yuki", "1.7"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    createListener.reset();
    openListener.reset();
    watched.clear();
}
