// Resizing a window by its border with the left button only, and never while a
// game holds the pointer, and the resize cursor shown only where a resize can
// happen.
//
// Hyprland starts a resize on any button pressed in the grab area round a
// window, and does so before it asks whether the focused window holds the
// pointer, which it asks before every other thing a click can do. A game
// that had locked the pointer with the cursor left near a picture-in-picture
// window pinned over it lost every click there to resizing that window, which
// took the focus, and with it the game's hold on the pointer. A right click
// near any window resized it as well, where Windows resizes with the left
// button alone.
//
// Such a press now goes on as any other does, to the surface holding the
// pointer: the game, which holds it. Otherwise nothing holds it in the grab
// area round a window, and a right press there does nothing, as a right press
// on the edge of a window does nothing on Windows.
//
// A window an environment holds at a size of its own, which the minimize
// plugin keeps from being resized, carries the tag named by
// plugin:border_resize:fixed_size_tag, the environment's to name. A press by
// its border goes on as an ordinary press: refused further on, a resize
// begun there swallowed the press, and the strip round a maximised window
// took no clicks at all.
//
// Hyprland shows the resize cursor on every side of every window, judged by
// the shape of the window alone. A window held at its size showed it all
// round, and so did a tiled window on its sides against the edge of the
// screen, which the layout does not move. The cursor now leaves out the sides
// that cannot be pulled: every side of a window held at its size, and the
// sides of a tiled window with no tiled neighbour beyond them on its workspace.
//
// hl.plugin.border_resize.cursor() gives the shape the cursor is overridden
// with, or an empty string, for the tests to read.

// The direction of the border cursor is kept privately by the input manager,
// and the hook below has to read what Hyprland made of the window first. The
// shape the cursor is overridden with is private as well. Included before
// anything else could include them without this, and after the standard
// headers they pull in, which redefined access breaks.
#include <any>
#include <array>
#include <functional>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
#define private public
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>

// The C library, under C linkage.
#include <lua.hpp>

#include <linux/input-event-codes.h>

#include <string>

namespace {
    HANDLE         handle     = nullptr;
    CFunctionHook* hook       = nullptr;
    CFunctionHook* cursorHook = nullptr;

    SP<Config::Values::CStringValue> fixedSizeTag;

    using ResizeWithBorder      = void (*)(CKeybindManager*, const IPointer::SButtonEvent&);
    using SetCursorIconOnBorder = void (*)(CInputManager*, PHLWINDOW);

    bool heldAtSize(const PHLWINDOW& window) {
        const auto tag = fixedSizeTag ? fixedSizeTag->value() : std::string{};
        return window && !tag.empty() && window->m_ruleApplicator && window->m_ruleApplicator->m_tagKeeper.isTagged(tag);
    }

    // The window whose border a press is on, found as the resize itself finds it.
    PHLWINDOW windowUnderCursor() {
        if (!g_pInputManager)
            return nullptr;
        using namespace Desktop::View;
        return Desktop::viewState()->hitTest().windowAt(g_pInputManager->getMouseCoordsInternal(), RESERVED_EXTENTS | INPUT_EXTENTS | ALLOW_FLOATING);
    }

    void resizeWithBorder(CKeybindManager* manager, const IPointer::SButtonEvent& event) {
        if (event.button != BTN_LEFT || (g_pInputManager && g_pInputManager->isConstrained()) || heldAtSize(windowUnderCursor())) {
            if (g_pSeatManager)
                g_pSeatManager->sendPointerButton(event.timeMs, event.button, event.state);
            return;
        }
        reinterpret_cast<ResizeWithBorder>(hook->m_original)(manager, event);
    }

    enum : uint8_t {
        SIDE_UP    = 1 << 0,
        SIDE_DOWN  = 1 << 1,
        SIDE_LEFT  = 1 << 2,
        SIDE_RIGHT = 1 << 3,
        SIDE_ALL   = SIDE_UP | SIDE_DOWN | SIDE_LEFT | SIDE_RIGHT,
    };

    uint8_t sidesOf(eBorderIconDirection direction) {
        switch (direction) {
            case BORDERICON_UP: return SIDE_UP;
            case BORDERICON_DOWN: return SIDE_DOWN;
            case BORDERICON_LEFT: return SIDE_LEFT;
            case BORDERICON_RIGHT: return SIDE_RIGHT;
            case BORDERICON_UP_LEFT: return SIDE_UP | SIDE_LEFT;
            case BORDERICON_DOWN_LEFT: return SIDE_DOWN | SIDE_LEFT;
            case BORDERICON_UP_RIGHT: return SIDE_UP | SIDE_RIGHT;
            case BORDERICON_DOWN_RIGHT: return SIDE_DOWN | SIDE_RIGHT;
            default: return 0;
        }
    }

    eBorderIconDirection directionOf(uint8_t sides) {
        switch (sides) {
            case SIDE_UP: return BORDERICON_UP;
            case SIDE_DOWN: return BORDERICON_DOWN;
            case SIDE_LEFT: return BORDERICON_LEFT;
            case SIDE_RIGHT: return BORDERICON_RIGHT;
            case SIDE_UP | SIDE_LEFT: return BORDERICON_UP_LEFT;
            case SIDE_DOWN | SIDE_LEFT: return BORDERICON_DOWN_LEFT;
            case SIDE_UP | SIDE_RIGHT: return BORDERICON_UP_RIGHT;
            case SIDE_DOWN | SIDE_RIGHT: return BORDERICON_DOWN_RIGHT;
            default: return BORDERICON_NONE;
        }
    }

    // How far a neighbour may stand from a side and still be the one that side
    // is shared with: twice the gap between tiles and the borders of both, for
    // gaps of up to about twenty pixels, which the layouts here keep under.
    constexpr double NEIGHBOUR_REACH = 48;

    // The sides of a window that pulling moves.
    uint8_t pullableSides(const PHLWINDOW& window) {
        if (heldAtSize(window))
            return 0;
        if (window->m_isFloating)
            return SIDE_ALL;

        const auto box   = window->getWindowMainSurfaceBox();
        uint8_t    sides = 0;
        for (const auto& other : Desktop::windowState()->windows()) {
            if (!other || other == window || !other->m_isMapped || other->isHidden() || other->m_isFloating || other->m_workspace != window->m_workspace)
                continue;
            const auto o         = other->getWindowMainSurfaceBox();
            const bool besideY   = o.y < box.y + box.h && o.y + o.h > box.y;
            const bool besideX   = o.x < box.x + box.w && o.x + o.w > box.x;
            const auto right     = box.x + box.w;
            const auto bottom    = box.y + box.h;
            if (besideY && o.x >= right - 1 && o.x - right <= NEIGHBOUR_REACH)
                sides |= SIDE_RIGHT;
            if (besideY && o.x + o.w <= box.x + 1 && box.x - (o.x + o.w) <= NEIGHBOUR_REACH)
                sides |= SIDE_LEFT;
            if (besideX && o.y >= bottom - 1 && o.y - bottom <= NEIGHBOUR_REACH)
                sides |= SIDE_DOWN;
            if (besideX && o.y + o.h <= box.y + 1 && box.y - (o.y + o.h) <= NEIGHBOUR_REACH)
                sides |= SIDE_UP;
        }
        return sides;
    }

    void showDirection(eBorderIconDirection direction) {
        using namespace Pointer::Cursor;
        switch (direction) {
            case BORDERICON_NONE: overrideController->unsetOverride(CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_UP: overrideController->setOverride("top_side", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_DOWN: overrideController->setOverride("bottom_side", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_LEFT: overrideController->setOverride("left_side", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_RIGHT: overrideController->setOverride("right_side", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_UP_LEFT: overrideController->setOverride("top_left_corner", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_DOWN_LEFT: overrideController->setOverride("bottom_left_corner", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_UP_RIGHT: overrideController->setOverride("top_right_corner", CURSOR_OVERRIDE_WINDOW_EDGE); break;
            case BORDERICON_DOWN_RIGHT: overrideController->setOverride("bottom_right_corner", CURSOR_OVERRIDE_WINDOW_EDGE); break;
        }
    }

    // What the cursor shows now, the sides that cannot be pulled left out.
    eBorderIconDirection shown = BORDERICON_NONE;

    // Hyprland keeps the direction it worked out from the shape of the window,
    // so it goes on setting the cursor only when that changes. The cursor is
    // set again here when Hyprland has just set it, or when what is left of
    // the direction changed without it, a neighbour closing say.
    void setCursorIconOnBorder(CInputManager* manager, PHLWINDOW window) {
        const auto before = manager->m_borderIconDirection;
        reinterpret_cast<SetCursorIconOnBorder>(cursorHook->m_original)(manager, window);
        const auto raw = manager->m_borderIconDirection;
        if (!window)
            return;
        const auto kept = directionOf(sidesOf(raw) & pullableSides(window));
        if (raw != before) {
            if (kept != raw)
                showDirection(kept);
        } else if (kept != shown)
            showDirection(kept);
        shown = kept;
    }

    int cursor(lua_State* state) {
        lua_pushstring(state, Pointer::Cursor::overrideController->m_overrideShape.c_str());
        return 1;
    }

    void* find(const std::string& name, const std::string& qualified) {
        for (const auto& match : HyprlandAPI::findFunctionsByName(handle, name))
            if (match.demangled.find(qualified) != std::string::npos)
                return match.address;
        return nullptr;
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
        HyprlandAPI::addNotification(handle, "[border-resize] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[border-resize] version mismatch");
    }

    if (void* target = find("resizeWithBorder", "CKeybindManager::resizeWithBorder"))
        hook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&resizeWithBorder));
    if (!hook || !hook->hook())
        HyprlandAPI::addNotification(handle, "[border-resize] could not hook the border press, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    if (void* target = find("setCursorIconOnBorder", "CInputManager::setCursorIconOnBorder"))
        cursorHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&setCursorIconOnBorder));
    if (!cursorHook || !cursorHook->hook())
        HyprlandAPI::addNotification(handle, "[border-resize] could not hook the border cursor, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    HyprlandAPI::addLuaFunction(handle, "border_resize", "cursor", cursor);

    fixedSizeTag = makeShared<Config::Values::CStringValue>("plugin:border_resize:fixed_size_tag", "Windows with this tag show no resize cursor and are not resized by their border", "");
    if (!HyprlandAPI::addConfigValueV2(handle, fixedSizeTag))
        HyprlandAPI::addNotification(handle, "[border-resize] could not register fixed_size_tag", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"border-resize", "Resizes by the border with the left button only and not while a game holds the pointer, and shows the resize cursor only where a resize can happen", "yuki", "1.2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hooks are taken down with the plugin by Hyprland itself.
}
