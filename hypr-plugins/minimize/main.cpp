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
// opens: the shell has nothing to place before then. A request is handed on
// once, as it is made, so the window is listened to from its creation rather
// than from its mapping, which heard nothing of it. Hyprland drops a Wayland
// window's request to be maximised made before it maps, so nothing hands that
// one on: the toplevel's own handlers of it are wrapped from the window's
// creation to its mapping, to hear it first, and Hyprland goes on dropping it.
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
// A window an environment holds at a size of its own keeps it. On Windows a
// maximised window fills its place until it is put back, and its edges cannot
// be pulled; Blueberry maximises by giving an ordinary
// floating window the work area, and Hyprland resized it like any other from
// its border, from a mouse bind or at the application's request, all of which
// begin at the drag controller. A resize of a window carrying the tag named by
// plugin:minimize:fixed_size_tag is not begun there. Moving it is: pulled
// away, it is put back by the shell. The tag is the environment's to name, in
// its compositor rules; with none named, nothing is held.
//
// Whether a window would float if it opened now, for an environment that tiles
// and takes over the windows another left floating. hl.plugin.minimize.
// should_float(address) answers with Hyprland's own judgement as the window
// opened, a dialog, a window with a parent, one of a fixed size, or with the
// rules loaded now. The rules are only read for it: nothing of them is
// applied to the window asked about.

// The Wayland backend keeps its xdg surface privately, and telling a Wayland
// window it is tiled needs the surface's toplevel. The X11 backend keeps its
// X surface privately as well, and the handlers of a toplevel's requests are
// kept privately by the protocol's own class and reached through a member the
// toplevel keeps privately. Included before anything else could include them
// without this, and after the standard headers they pull in, which redefined
// access breaks.
#include <any>
#include <array>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>
#define private public
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/desktop/view/window/WaylandBackend.hpp>
#include <hyprland/src/desktop/view/window/X11Backend.hpp>
#undef private

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/rule/Engine.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRule.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>

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

    SP<Config::Values::CStringValue> fixedSizeTag;

    using DragBegin = void (*)(Layout::Supplementary::CDragStateController*, SP<Layout::ITarget>, eMouseBindMode, std::optional<Layout::eRectCorner>, bool);

    void dragBegin(Layout::Supplementary::CDragStateController* controller, SP<Layout::ITarget> target, eMouseBindMode mode, std::optional<Layout::eRectCorner> edge,
                   bool exclusiveDeviceGrab) {
        const auto tag = fixedSizeTag ? fixedSizeTag->value() : std::string{};
        if (mode != MBIND_MOVE && target && !tag.empty()) {
            const auto window = target->window();
            if (window && window->m_ruleApplicator && window->m_ruleApplicator->m_tagKeeper.isTagged(tag))
                return;
        }
        reinterpret_cast<DragBegin>(dragBeginHook->m_original)(controller, std::move(target), mode, edge, exclusiveDeviceGrab);
    }

    using ToplevelRequest = std::function<void(CXdgToplevel*)>;

    struct SWatched {
        PHLWINDOWREF        window;
        CHyprSignalListener listener;
        /** Asked for before the window was mapped, to be announced as it opens. */
        bool                minimize = false;
        std::optional<bool> maximize;
        /** A Wayland window's own handlers of its requests to be maximised or not, while wrapped. */
        WP<CXdgToplevel>    toplevel;
        ToplevelRequest     setMaximized;
        ToplevelRequest     unsetMaximized;
    };
    std::vector<SWatched> watched;

    SWatched* entryFor(const PHLWINDOW& window) {
        for (auto& entry : watched)
            if (entry.window.lock() == window)
                return &entry;
        return nullptr;
    }

    SWatched* entryFor(const CXdgToplevel* toplevel) {
        for (auto& entry : watched)
            if (entry.toplevel.get() == toplevel)
                return &entry;
        return nullptr;
    }

    // Hears a request to be maximised or not made before the window maps,
    // then hands it to the handler it wraps, which drops it.
    void heardEarly(CXdgToplevel* toplevel, bool maximize) {
        auto* entry = entryFor(toplevel);
        if (!entry)
            return;
        if (const auto window = entry->window.lock(); window && !window->mapped())
            entry->maximize = maximize;
        const auto& original = maximize ? entry->setMaximized : entry->unsetMaximized;
        if (original)
            original(toplevel);
    }

    void wrapEarly(SWatched& entry, const PHLWINDOW& window) {
        auto* wayland = dynamic_cast<Desktop::View::CWaylandBackend*>(&window->backend());
        if (!wayland)
            return;
        const auto xdg      = wayland->m_resource.lock();
        const auto toplevel = xdg ? xdg->m_toplevel.lock() : nullptr;
        if (!toplevel || !toplevel->m_resource)
            return;
        auto& requests       = toplevel->m_resource->requests;
        entry.toplevel       = toplevel->m_resource;
        entry.setMaximized   = std::move(requests.setMaximized);
        entry.unsetMaximized = std::move(requests.unsetMaximized);
        requests.setMaximized   = [](CXdgToplevel* r) { heardEarly(r, true); };
        requests.unsetMaximized = [](CXdgToplevel* r) { heardEarly(r, false); };
    }

    // Hyprland's own handlers back in place: once the window is mapped, and
    // for every window as the plugin goes, whose code the wrappers are.
    void unwrapEarly(SWatched& entry) {
        if (const auto toplevel = entry.toplevel.lock()) {
            toplevel->requests.setMaximized   = std::move(entry.setMaximized);
            toplevel->requests.unsetMaximized = std::move(entry.unsetMaximized);
        }
        entry.toplevel.reset();
        entry.setMaximized   = nullptr;
        entry.unsetMaximized = nullptr;
    }

    void announce(const PHLWINDOWREF& ref) {
        const auto window = ref.lock();
        if (!window || !IPC::Socket2::sock())
            return;
        IPC::Socket2::sock()->postEvent({.event = "minimized", .data = std::format("{:x},1", reinterpret_cast<uintptr_t>(window.get()))});
    }

    void announceMaximize(const PHLWINDOWREF& ref, bool maximize) {
        const auto window = ref.lock();
        if (!window || !IPC::Socket2::sock())
            return;
        IPC::Socket2::sock()->postEvent({.event = "maximizerequest", .data = std::format("{:x},{}", reinterpret_cast<uintptr_t>(window.get()), maximize ? 1 : 0)});
    }

    // Passed on at once for a mapped window, held for one that is not yet.
    void heard(const PHLWINDOWREF& ref, bool minimize, std::optional<bool> maximize) {
        const auto window = ref.lock();
        if (!window)
            return;
        if (!window->mapped()) {
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

    // A request to be minimised, maximised or put back, as the window's
    // backend hands it on, Wayland and X11 alike, one request at a time.
    CHyprSignalListener listenTo(const PHLWINDOW& window) {
        const PHLWINDOWREF ref = window;
        return window->backend().m_events.stateRequest.listen([ref](Desktop::View::SBackendStateRequest request) {
            heard(ref, request.minimized.value_or(false), request.maximized);
        });
    }

    // Whether the rules loaded now float a window, the last of them to say so
    // winning, as when the rules are applied to a window opening.
    bool rulesFloat(const PHLWINDOW& window) {
        bool floats = false;
        for (const auto& rule : Desktop::Rule::ruleEngine()->rules()) {
            if (rule->type() != Desktop::Rule::RULE_TYPE_WINDOW)
                continue;
            const auto windowRule = reinterpretPointerCast<Desktop::Rule::CWindowRule>(rule);
            if (!windowRule->matches(window, true))
                continue;
            for (const auto& effect : windowRule->effects()) {
                if (effect.key == Desktop::Rule::WINDOW_RULE_EFFECT_FLOAT)
                    floats = std::get<bool>(effect.value);
                else if (effect.key == Desktop::Rule::WINDOW_RULE_EFFECT_TILE)
                    floats = !std::get<bool>(effect.value);
            }
        }
        return floats;
    }

    int shouldFloat(lua_State* state) {
        const std::string address = luaL_checkstring(state, 1);
        bool              floats  = false;
        for (const auto& window : Desktop::windowState()->windows()) {
            if (window && std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get())) == address) {
                floats = window->suggestsFloat() || rulesFloat(window);
                break;
            }
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
            if (auto* wayland = dynamic_cast<Desktop::View::CWaylandBackend*>(&window->backend())) {
                if (const auto xdg = wayland->m_resource.lock(); xdg && xdg->m_toplevel)
                    setXdgState(xdg->m_toplevel.lock(), maximized, tiled);
            } else if (auto* x11 = dynamic_cast<Desktop::View::CX11Backend*>(&window->backend())) {
                // X11 has no tiled state. Sending the whole state sends the
                // maximised part with it and leaves fullscreen as it was. The
                // state waits in the X connection's buffer until something
                // flushes it, which a configure does, and one to where the
                // window already stands changes nothing: a window already as
                // large as it is to be got no configure otherwise, and never
                // heard of its state.
                if (const auto surface = x11->m_xwaylandSurface.lock(); surface && surface->m_maximized != maximized) {
                    surface->m_maximized = maximized;
                    surface->setFullscreen(surface->m_fullscreen);
                    surface->configure(surface->m_geometry);
                }
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
        if (auto listener = listenTo(window)) {
            auto* added     = entryFor(window);
            added->listener = std::move(listener);
            if (!window->mapped())
                wrapEarly(*added, window);
        } else
            watched.pop_back();
    }

    // What was asked for before the window was mapped, now that it is. An X11
    // request made before this plugin listened is still on the surface, and
    // is spent here like any other.
    void announceInitial(const PHLWINDOW& window) {
        auto* entry = entryFor(window);
        bool  minimize = entry && entry->minimize;
        auto  maximize = entry ? entry->maximize : std::nullopt;
        if (entry) {
            unwrapEarly(*entry);
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

    fixedSizeTag = makeShared<Config::Values::CStringValue>("plugin:minimize:fixed_size_tag", "Windows with this tag are not resized", "");
    if (!HyprlandAPI::addConfigValueV2(handle, fixedSizeTag))
        HyprlandAPI::addNotification(handle, "[minimize] could not register fixed_size_tag, no window keeps its size", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    // Windows that were already open when the plugin came in.
    for (const auto& window : Desktop::windowState()->windows())
        if (window && window->mapped())
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

    return {"minimize", "Passes on requests to be minimised or maximised, keeps windows an environment holds from being resized, says whether a window would float, tells windows whether they are maximised or tiled, and lets go of focus for the shell's minimising", "yuki", "1.8"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    createListener.reset();
    openListener.reset();
    for (auto& entry : watched)
        unwrapEarly(entry);
    watched.clear();
}
