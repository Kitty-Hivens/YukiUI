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
// shell leaves Wayland windows as Hyprland has them. All but those whose class
// ends as hl.plugin.minimize.literal_class_suffix(suffix) says, Wine's: told the truth
// instead, maximised only while they hold the fixed size tag, since Wine asks
// back to be maximised whenever it is told it is.
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
//
// Telling X11 applications what may be done with their windows, as EWMH has a
// window manager do in _NET_WM_ALLOWED_ACTIONS. An application that draws its
// own title bar reads it to know which of its buttons will be honoured, and
// Hyprland publishes nothing of it. What is honoured depends on the
// environment and on how the window stands, so the environment says it, in
// its compositor rules, with hl.plugin.minimize.allowed_actions({ tiled = {...},
// floating = {...}, held = {...} }), naming move, resize, minimize, maximize,
// fullscreen and close. Held is a window in fullscreen or Hyprland's maximise,
// or one carrying the fixed size tag. Only while an environment has said it
// does the root window list _NET_WM_ALLOWED_ACTIONS as supported: declared
// without the list on each window, an application takes everything for
// allowed. A reload of the rules that no longer says it takes it back.
//
// While it is said, a window Hyprland maximises is told so in its
// _NET_WM_STATE as well, and told again when it is put back. Left out, an
// application's maximise button went on offering to maximise a window that
// already was.
//
// The work area in _NET_WORKAREA, which an X11 application sizes its first
// window by, is kept current: Hyprland writes it only as the monitors are
// arranged, not as a dock takes its room or gives it back, nor when the X
// server starts later. The value is Hyprland's own reckoning, written again
// whenever the layers on a monitor are arranged.
//
// A fullscreen window focused again has the windows of its workspace that
// were let over it, by being focused while it was fullscreen, put back under
// it. Hyprland lets such a window over for good, so a fullscreen terminal
// could not be brought back over a browser, Alt+Tab included.
//
// What an X11 window says of itself before it is shown is honoured as it
// opens: maximised or fullscreen in its own _NET_WM_STATE is asked for the
// same way as a shown window asks, which Hyprland otherwise ignores, and a
// window asking to bypass the compositor, a game, is tagged "bypass" for the
// environment to leave at the size it asked for.

// The Wayland backend keeps its xdg surface privately, and telling a Wayland
// window it is tiled needs the surface's toplevel. The X11 backend keeps its
// X surface privately as well, and the handlers of a toplevel's requests are
// kept privately by the protocol's own class and reached through a member the
// toplevel keeps privately. The X window manager keeps its connection to the
// X server and its screen privately too. Included before anything else could include them
// without this, and after the standard headers they pull in, which redefined
// access breaks.
#include <any>
#include <array>
#include <bit>
#include <functional>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
#define private public
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/desktop/view/window/WaylandBackend.hpp>
#include <hyprland/src/desktop/view/window/X11Backend.hpp>
#include <hyprland/src/xwayland/XWayland.hpp>
#undef private

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/rule/Engine.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRule.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/window/WindowFullscreenPolicy.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/desktop/rule/Rule.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/state/MonitorLayoutController.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>

// The C library, under C linkage.
#include <lua.hpp>

#include <algorithm>
#include <cstring>
#include <format>
#include <string_view>
#include <optional>
#include <utility>
#include <vector>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener createListener;
    CHyprSignalListener openListener;
    CFunctionHook*      dragBeginHook = nullptr;

    SP<Config::Values::CStringValue> fixedSizeTag;
    /** Set by hl.plugin.minimize.literal_class_suffix, empty for none. */
    std::string                      literalClassSuffix;
    bool                             literalSaidThisReload = false;

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
    SP<CXDGToplevelResource> literalToplevel(const PHLWINDOW& window);

    CHyprSignalListener listenTo(const PHLWINDOW& window) {
        const PHLWINDOWREF ref = window;
        return window->backend().m_events.stateRequest.listen([ref](Desktop::View::SBackendStateRequest request) {
            // Hyprland hands on a Wayland window's request to be maximised or
            // put back as the opposite of its own maximise, which here is never
            // on, so both arrive as "maximise". A window told the truth means
            // what it asks, and what it asked is still on its toplevel while
            // the request is handed on.
            auto maximize = request.maximized;
            if (maximize.has_value())
                if (const auto toplevel = literalToplevel(ref.lock()); toplevel && toplevel->m_state.requestsMaximize.has_value())
                    maximize = toplevel->m_state.requestsMaximize;
            heard(ref, request.minimized.value_or(false), maximize);
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

    struct SActionPolicy {
        std::vector<std::string> tiled, floating, held;
    };
    std::optional<SActionPolicy> policy;
    /** Said again by the rules being read now, during a reload. */
    bool                         saidThisReload = false;
    CHyprSignalListener          floatingListener, fullscreenListener, rulesListener, preReloadListener, reloadedListener, activeListener;
    CFunctionHook*               xwaylandReadyHook = nullptr;
    CFunctionHook*               arrangeLayersHook = nullptr;
    /** Windows told they are maximised because Hyprland maximised them, to be told otherwise when it no longer does. */
    std::vector<PHLWINDOWREF>    maximizedByHyprland;

    const std::array<std::pair<const char*, std::array<const char*, 2>>, 6> ACTIONS = {{
        {"move", {"_NET_WM_ACTION_MOVE", nullptr}},
        {"resize", {"_NET_WM_ACTION_RESIZE", nullptr}},
        {"minimize", {"_NET_WM_ACTION_MINIMIZE", nullptr}},
        {"maximize", {"_NET_WM_ACTION_MAXIMIZE_HORZ", "_NET_WM_ACTION_MAXIMIZE_VERT"}},
        {"fullscreen", {"_NET_WM_ACTION_FULLSCREEN", nullptr}},
        {"close", {"_NET_WM_ACTION_CLOSE", nullptr}},
    }};

    xcb_connection_t* xConnection() {
        if (!g_pXWayland || !g_pXWayland->m_wm)
            return nullptr;
        return g_pXWayland->m_wm->getConnection();
    }

    // Interned once per X server: a new server, after Xwayland is started
    // again, numbers its atoms anew.
    xcb_atom_t atom(const char* name) {
        static xcb_connection_t*                           internedOn = nullptr;
        static std::unordered_map<std::string, xcb_atom_t> interned;
        auto*                                              connection = xConnection();
        if (!connection)
            return XCB_ATOM_NONE;
        if (connection != internedOn) {
            interned.clear();
            internedOn = connection;
        }
        if (const auto found = interned.find(name); found != interned.end())
            return found->second;
        const auto cookie = xcb_intern_atom(connection, 0, std::strlen(name), name);
        auto*      reply  = xcb_intern_atom_reply(connection, cookie, nullptr);
        if (!reply)
            return XCB_ATOM_NONE;
        const xcb_atom_t value = reply->atom;
        free(reply);
        interned.emplace(name, value);
        return value;
    }

    // Puts _NET_WM_ALLOWED_ACTIONS in the root's _NET_SUPPORTED, or takes it
    // out, leaving everything Hyprland listed there as it was.
    void declareSupport() {
        auto* connection = xConnection();
        if (!connection || !g_pXWayland->m_wm->m_screen)
            return;
        const auto root      = g_pXWayland->m_wm->m_screen->root;
        const auto supported = atom("_NET_SUPPORTED");
        const auto allowed   = atom("_NET_WM_ALLOWED_ACTIONS");
        if (supported == XCB_ATOM_NONE || allowed == XCB_ATOM_NONE)
            return;
        const auto cookie = xcb_get_property(connection, 0, root, supported, XCB_ATOM_ATOM, 0, 4096);
        auto*      reply  = xcb_get_property_reply(connection, cookie, nullptr);
        if (!reply)
            return;
        const auto*             first = static_cast<const xcb_atom_t*>(xcb_get_property_value(reply));
        std::vector<xcb_atom_t> atoms(first, first + xcb_get_property_value_length(reply) / sizeof(xcb_atom_t));
        free(reply);
        const bool listed = std::ranges::find(atoms, allowed) != atoms.end();
        if (policy.has_value() == listed)
            return;
        // Every action named before it is declared. An application that finds
        // the declaration may look its action atoms up without making them,
        // and one made only as the first window is told came too late: it had
        // taken them for unknown and read every list as allowing nothing.
        if (policy)
            for (const auto& [action, atomNames] : ACTIONS)
                for (const auto* atomName : atomNames)
                    if (atomName)
                        atom(atomName);
        if (policy)
            atoms.push_back(allowed);
        else
            std::erase(atoms, allowed);
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, root, supported, XCB_ATOM_ATOM, 32, atoms.size(), atoms.data());
        xcb_flush(connection);
    }

    SP<CXWaylandSurface> managedXSurface(const PHLWINDOW& window) {
        auto* x11 = window ? dynamic_cast<Desktop::View::CX11Backend*>(&window->backend()) : nullptr;
        if (!x11)
            return nullptr;
        const auto surface = x11->m_xwaylandSurface.lock();
        return surface && surface->m_xID && !surface->m_overrideRedirect ? surface : nullptr;
    }

    bool held(const PHLWINDOW& window) {
        if (Fullscreen::controller()->isFullscreen(window))
            return true;
        const auto tag = fixedSizeTag ? fixedSizeTag->value() : std::string{};
        return !tag.empty() && window->m_ruleApplicator && window->m_ruleApplicator->m_tagKeeper.isTagged(tag);
    }

    void sendMaximized(const SP<CXWaylandSurface>& surface, bool maximized) {
        // Sending the whole state sends the maximised part with it. It waits
        // in the X connection's buffer until a configure flushes it, and one
        // to where the window already stands changes nothing.
        surface->m_maximized = maximized;
        surface->setFullscreen(surface->m_fullscreen);
        surface->configure(surface->m_geometry);
    }

    // Tells an X11 window it is maximised while Hyprland has it maximised,
    // and not once Hyprland puts it back. A window maximised otherwise, as a
    // shell does through set_window_state, is left as the shell told it.
    void followMaximize(const PHLWINDOW& window) {
        const auto surface = managedXSurface(window);
        if (!surface)
            return;
        std::erase_if(maximizedByHyprland, [](const auto& ref) { return ref.expired(); });
        const bool told      = std::ranges::find_if(maximizedByHyprland, [&](const auto& ref) { return ref.lock() == window; }) != maximizedByHyprland.end();
        const bool maximized = policy && Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_MAXIMIZED);
        if (maximized && !told && !surface->m_maximized) {
            maximizedByHyprland.emplace_back(window);
            sendMaximized(surface, true);
        } else if (!maximized && told) {
            std::erase_if(maximizedByHyprland, [&](const auto& ref) { return ref.lock() == window; });
            if (surface->m_maximized)
                sendMaximized(surface, false);
        }
    }

    // A property of a window, as the values of format 32 it holds, empty when unset.
    std::vector<uint32_t> property(xcb_window_t window, xcb_atom_t name) {
        auto* connection = xConnection();
        if (!connection || name == XCB_ATOM_NONE)
            return {};
        const auto cookie = xcb_get_property(connection, 0, window, name, XCB_ATOM_ANY, 0, 64);
        auto*      reply  = xcb_get_property_reply(connection, cookie, nullptr);
        if (!reply)
            return {};
        std::vector<uint32_t> values;
        if (reply->format == 32) {
            const auto* first = static_cast<const uint32_t*>(xcb_get_property_value(reply));
            values.assign(first, first + xcb_get_property_value_length(reply) / sizeof(uint32_t));
        }
        free(reply);
        return values;
    }

    // Each X11 window's own _NET_WM_STATE as it asked to be shown, by window.
    // Read then because Hyprland writes the property over with its own idea of
    // the window's state as the window is mapped, before it opens.
    std::unordered_map<xcb_window_t, std::vector<uint32_t>> ownStates;
    CFunctionHook*                                          mapRequestHook = nullptr;

    using MapRequest = void (*)(void*, xcb_map_request_event_t*);

    void mapRequest(void* wm, xcb_map_request_event_t* event) {
        std::erase_if(ownStates, [](const auto& entry) { return !g_pXWayland || !g_pXWayland->m_wm || !g_pXWayland->m_wm->windowForXID(entry.first); });
        if (event)
            ownStates[event->window] = property(event->window, HYPRATOMS["_NET_WM_STATE"]);
        reinterpret_cast<MapRequest>(mapRequestHook->m_original)(wm, event);
    }

    // What an X11 window says of itself before it is shown, taken as it would
    // be if it asked once shown. Hyprland reads only whether it is modal from
    // the window's own _NET_WM_STATE, so one opening maximised or fullscreen,
    // as an application that remembers how it stood does, opened as neither.
    // Asked through the same request as a shown window's, so each environment
    // answers it its own way. A window asking to bypass the compositor, as a
    // game does, is tagged so for the environment to leave it as it asked.
    void honourOwnState(const PHLWINDOW& window) {
        const auto surface = managedXSurface(window);
        if (!surface)
            return;
        const auto bypass = property(surface->m_xID, atom("_NET_WM_BYPASS_COMPOSITOR"));
        if (!bypass.empty() && bypass.front() == 1 && window->m_ruleApplicator->m_tagKeeper.applyTag("+bypass")) {
            window->m_ruleApplicator->propertiesChanged(Desktop::Rule::RULE_PROP_TAG);
            window->presentation().refreshValues();
        }
        const auto said = ownStates.find(surface->m_xID);
        if (said == ownStates.end())
            return;
        const auto states = std::move(said->second);
        ownStates.erase(said);
        const auto has = [&](const char* name) { return std::ranges::find(states, HYPRATOMS[name]) != states.end(); };
        bool       asked  = false;
        if (has("_NET_WM_STATE_MAXIMIZED_VERT") && has("_NET_WM_STATE_MAXIMIZED_HORZ") && !surface->m_maximized) {
            surface->m_state.requestsMaximize = true;
            asked                             = true;
        }
        if (has("_NET_WM_STATE_FULLSCREEN") && !surface->m_fullscreen) {
            surface->m_state.requestsFullscreen = true;
            asked                               = true;
        }
        if (asked)
            surface->m_events.stateChanged.emit();
    }

    // Writes a window's _NET_WM_ALLOWED_ACTIONS as the environment has it for
    // how the window stands now, or takes it away when nothing is said.
    void publish(const PHLWINDOW& window) {
        const auto surface    = managedXSurface(window);
        auto*      connection = xConnection();
        if (!surface || !connection)
            return;
        const auto property = atom("_NET_WM_ALLOWED_ACTIONS");
        if (property == XCB_ATOM_NONE)
            return;
        if (!policy) {
            xcb_delete_property(connection, surface->m_xID, property);
            xcb_flush(connection);
            return;
        }
        const auto&             names = held(window) ? policy->held : window->isFloating() ? policy->floating : policy->tiled;
        std::vector<xcb_atom_t> atoms;
        for (const auto& name : names)
            for (const auto& [action, atomNames] : ACTIONS)
                if (name == action)
                    for (const auto* atomName : atomNames)
                        if (atomName)
                            atoms.push_back(atom(atomName));
        xcb_change_property(connection, XCB_PROP_MODE_REPLACE, surface->m_xID, property, XCB_ATOM_ATOM, 32, atoms.size(), atoms.data());
        xcb_flush(connection);
    }

    // The toplevel of a Wayland window whose class ends as the environment
    // names through literal_class_suffix, compared without case, or null for
    // any other window.
    SP<CXDGToplevelResource> literalToplevel(const PHLWINDOW& window) {
        const auto& suffix = literalClassSuffix;
        auto*      wayland = window ? dynamic_cast<Desktop::View::CWaylandBackend*>(&window->backend()) : nullptr;
        if (suffix.empty() || !wayland)
            return nullptr;
        const auto& id = window->metadata().appID();
        if (id.size() < suffix.size() ||
            !std::equal(suffix.rbegin(), suffix.rend(), id.rbegin(), [](char a, char b) { return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b)); }))
            return nullptr;
        const auto xdg = wayland->m_resource.lock();
        return xdg ? xdg->m_toplevel.lock() : nullptr;
    }

    // Tells such a window it is maximised only while the environment holds it
    // maximised, by the fixed size tag, and tiled all the while. Hyprland tells
    // every Wayland window it is maximised as it maps, and Wine takes that
    // literally: it asks back to be maximised, once as a window opens and
    // again and again while one is fullscreen. A shell that answers requests
    // to maximise maximised a splash screen with it. Said as the window opens,
    // before the configure Hyprland sends with it goes out, and again whenever
    // its fullscreen state or its tags change.
    void tellLiteral(const PHLWINDOW& window) {
        const auto toplevel = literalToplevel(window);
        if (!toplevel)
            return;
        const auto tag       = fixedSizeTag ? fixedSizeTag->value() : std::string{};
        const bool maximized = !tag.empty() && window->m_ruleApplicator && window->m_ruleApplicator->m_tagKeeper.isTagged(tag);
        setXdgState(toplevel, maximized, true);
    }

    void refresh(const PHLWINDOW& window) {
        if (!window || !window->mapped())
            return;
        followMaximize(window);
        tellLiteral(window);
        publish(window);
    }

    void refreshAll() {
        declareSupport();
        for (const auto& window : Desktop::windowState()->windows())
            refresh(window);
    }

    std::vector<std::string> actionList(lua_State* state, int table, const char* key) {
        std::vector<std::string> names;
        lua_getfield(state, table, key);
        if (lua_istable(state, -1)) {
            const auto count = lua_rawlen(state, -1);
            for (lua_Integer i = 1; i <= static_cast<lua_Integer>(count); ++i) {
                lua_rawgeti(state, -1, i);
                const char* name = lua_tostring(state, -1);
                if (!name || std::ranges::none_of(ACTIONS, [&](const auto& action) { return std::string_view{action.first} == name; }))
                    luaL_error(state, "allowed_actions: %s lists %s, which is none of move, resize, minimize, maximize, fullscreen, close", key, name ? name : "something that is not a name");
                names.emplace_back(name);
                lua_pop(state, 1);
            }
        } else if (!lua_isnil(state, -1))
            luaL_error(state, "allowed_actions: %s is not a list", key);
        lua_pop(state, 1);
        return names;
    }

    int allowedActions(lua_State* state) {
        if (lua_isnoneornil(state, 1))
            policy.reset();
        else {
            luaL_checktype(state, 1, LUA_TTABLE);
            policy = SActionPolicy{
                .tiled    = actionList(state, 1, "tiled"),
                .floating = actionList(state, 1, "floating"),
                .held     = actionList(state, 1, "held"),
            };
        }
        saidThisReload = true;
        refreshAll();
        return 0;
    }

    // The work area as X11 applications read it, in _NET_WORKAREA, kept to
    // what Hyprland would say there now. Hyprland works it out only as the
    // monitors are arranged, so a dock that came up or went away afterwards,
    // or an X server started later, left it saying the whole screen or
    // nothing. An application sizing its first window by it opened under the
    // dock, and Hyprland then pushed it up past the top of the screen. Same
    // reckoning as Hyprland's, one monitor or none, written only when it
    // changes.
    void writeWorkArea() {
        if (!g_pXWayland || !g_pXWayland->m_wm || !g_pXWayland->m_wm->getConnection())
            return;
        static xcb_connection_t*   writtenOn = nullptr;
        static std::optional<CBox> written;
        const auto                 area = State::monitorLayoutController()->calculateUnifiedX11WorkArea();
        if (writtenOn == g_pXWayland->m_wm->getConnection() && written == area)
            return;
        writtenOn = g_pXWayland->m_wm->getConnection();
        written   = area;
        if (area)
            g_pXWayland->m_wm->updateWorkArea(area->x, area->y, area->w, area->h);
        else
            g_pXWayland->m_wm->updateWorkArea(0, 0, 0, 0);
    }

    using XwaylandReady = int (*)(void*, int, uint32_t);

    // The X window manager is made once Xwayland is ready, and writes the
    // root's _NET_SUPPORTED as it starts, but no work area. Both said after
    // it, before an application that asked for Xwayland reads them.
    int xwaylandReady(void* server, int fd, uint32_t mask) {
        const int result = reinterpret_cast<XwaylandReady>(xwaylandReadyHook->m_original)(server, fd, mask);
        declareSupport();
        writeWorkArea();
        return result;
    }

    using ArrangeLayers = void (*)(void*, const MONITORID&);

    // Where the room the layers take on a monitor is reckoned, a dock's
    // included, and the only place it changes but for the monitors' own.
    void arrangeLayers(void* renderer, const MONITORID& monitor) {
        reinterpret_cast<ArrangeLayers>(arrangeLayersHook->m_original)(renderer, monitor);
        writeWorkArea();
    }

    // A window focused over a fullscreen one on its workspace is let draw over
    // it, and stays so: Hyprland takes that back only as a window is made
    // fullscreen again, not as the fullscreen window is focused again. Once a
    // browser had been brought up over a fullscreen terminal, nothing brought
    // the terminal back over the browser, Alt+Tab included. Focused again, the
    // fullscreen window has the others put back under it, as they were when
    // it went fullscreen, pinned ones excepted, their order left as it was.
    void coverWithFullscreen(const PHLWINDOW& window) {
        if (!window || !window->m_workspace)
            return;
        const auto fullscreen = Fullscreen::controller()->getFullscreenWindow(window->m_workspace);
        if (fullscreen != window || Fullscreen::controller()->layoutManagedFS(fullscreen))
            return;
        for (const auto& other : Desktop::windowState()->windows()) {
            if (!other || other == window || other->m_workspace != window->m_workspace || (other->m_state & Desktop::View::WINDOW_STATE_PINNED) ||
                !other->fullscreenPolicy().allowedOverFullscreen())
                continue;
            other->fullscreenPolicy().setAllowedOverFullscreen(false);
            other->updateFullscreenInputState();
            *other->presentation().alpha(Desktop::View::WINDOW_ALPHA_FULLSCREEN) = 0.F;
            g_pHyprRenderer->damageWindow(other);
        }
    }

    // hl.plugin.minimize.literal_class_suffix(".exe"), or with nothing to say
    // none. Said by the environment in its compositor rules, and taken back by
    // a reload of the rules that no longer says it. A window already open is
    // told the truth at once; one let go of is left as it was told last.
    int literalSuffix(lua_State* state) {
        literalClassSuffix    = lua_isnoneornil(state, 1) ? std::string{} : std::string{luaL_checkstring(state, 1)};
        literalSaidThisReload = true;
        for (const auto& window : Desktop::windowState()->windows())
            if (window && window->mapped())
                tellLiteral(window);
        return 0;
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
                if (const auto surface = x11->m_xwaylandSurface.lock(); surface && surface->m_maximized != maximized)
                    sendMaximized(surface, maximized);
                publish(window);
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
        tellLiteral(window);
        announceInitial(window);
        honourOwnState(window);
        refresh(window);
    });
    activeListener     = Event::bus()->m_events.window.active.listen([](const PHLWINDOW& window, Desktop::eFocusReason) { coverWithFullscreen(window); });
    floatingListener   = Event::bus()->m_events.window.floating.listen([](const PHLWINDOW& window) { refresh(window); });
    fullscreenListener = Event::bus()->m_events.window.fullscreen.listen([](const PHLWINDOW& window) { refresh(window); });
    // A tag given or taken, the fixed size tag among them.
    rulesListener     = Event::bus()->m_events.window.updateRules.listen([](const PHLWINDOW& window) { refresh(window); });
    preReloadListener = Event::bus()->m_events.config.preReload.listen([] {
        saidThisReload        = false;
        literalSaidThisReload = false;
    });
    reloadedListener  = Event::bus()->m_events.config.reloaded.listen([] {
        if (!saidThisReload && policy) {
            policy.reset();
            refreshAll();
        }
        if (!literalSaidThisReload && !literalClassSuffix.empty())
            literalClassSuffix.clear();
    });

    HyprlandAPI::addLuaFunction(handle, "minimize", "reset_focus", resetFocus);
    HyprlandAPI::addLuaFunction(handle, "minimize", "set_window_state", setWindowState);
    HyprlandAPI::addLuaFunction(handle, "minimize", "should_float", shouldFloat);
    HyprlandAPI::addLuaFunction(handle, "minimize", "allowed_actions", allowedActions);
    HyprlandAPI::addLuaFunction(handle, "minimize", "literal_class_suffix", literalSuffix);

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

    void* ready = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "ready")) {
        if (match.demangled.find("CXWaylandServer::ready") != std::string::npos) {
            ready = match.address;
            break;
        }
    }
    if (ready)
        xwaylandReadyHook = HyprlandAPI::createFunctionHook(handle, ready, reinterpret_cast<void*>(&xwaylandReady));
    if (!xwaylandReadyHook || !xwaylandReadyHook->hook())
        HyprlandAPI::addNotification(handle, "[minimize] could not hook Xwayland starting, X11 applications started first may not see the allowed actions", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    void* mapRequestAt = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "handleMapRequest")) {
        if (match.demangled.find("CXWM::handleMapRequest") != std::string::npos) {
            mapRequestAt = match.address;
            break;
        }
    }
    if (mapRequestAt)
        mapRequestHook = HyprlandAPI::createFunctionHook(handle, mapRequestAt, reinterpret_cast<void*>(&mapRequest));
    if (!mapRequestHook || !mapRequestHook->hook())
        HyprlandAPI::addNotification(handle, "[minimize] could not hook X11 windows being shown, a window opening maximised or fullscreen opens as neither", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    void* arrange = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "arrangeLayersForMonitor")) {
        if (match.demangled.find("IHyprRenderer::arrangeLayersForMonitor") != std::string::npos) {
            arrange = match.address;
            break;
        }
    }
    if (arrange)
        arrangeLayersHook = HyprlandAPI::createFunctionHook(handle, arrange, reinterpret_cast<void*>(&arrangeLayers));
    if (!arrangeLayersHook || !arrangeLayersHook->hook())
        HyprlandAPI::addNotification(handle, "[minimize] could not hook the layer arrangement, X11 applications may see a stale work area", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);
    writeWorkArea();

    return {"minimize", "Passes on requests to be minimised or maximised, keeps windows an environment holds from being resized, says whether a window would float, tells windows whether they are maximised or tiled and what may be done with them, keeps the X11 work area current, and lets go of focus for the shell's minimising", "yuki", "1.11"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    createListener.reset();
    openListener.reset();
    floatingListener.reset();
    fullscreenListener.reset();
    activeListener.reset();
    rulesListener.reset();
    preReloadListener.reset();
    reloadedListener.reset();
    // What was said is taken back, so nothing is promised once nothing keeps
    // it. A window told it is maximised stays told: it still is.
    policy.reset();
    maximizedByHyprland.clear();
    declareSupport();
    for (const auto& window : Desktop::windowState()->windows())
        publish(window);
    for (auto& entry : watched)
        unwrapEarly(entry);
    watched.clear();
}
