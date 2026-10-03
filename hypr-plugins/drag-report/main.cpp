// Tells the shell when a window is being moved or resized with the mouse, and
// where the pointer is meanwhile, without changing anything about the drag.
//
// Snapping a window to an edge or a corner needs to know that a drag is going
// on, to show where the window would go, and where it ended, to put it there.
// Hyprland says nothing about either on its socket: a floating window moving
// raises no event at all. Its drag controller knows, so after every motion and
// every button of the mouse, on the next turn of the event loop, once Hyprland
// has dealt with it, this looks at the controller and reports what changed:
//
//     windowdrag>>begin,<address>,move|resize,<x>,<y>,<w>,<h>
//                                                 picked up, past the threshold,
//                                                 and where the window stood
//                                                 before it, global coordinates
//     windowdrag>>move,<x>,<y>                    the pointer, while moving it,
//                                                 at most about thirty times a
//                                                 second, global coordinates
//     windowdrag>>end,<address>,move|resize,<x>,<y>
//
// A drag the threshold has not been passed for is not reported: a click on a
// title bar is not a drag.
//
// hl.plugin.drag_report.regrab(width, height) gives the window being moved a
// new size under the pointer and goes on dragging it from there, the way a
// maximised or snapped window on Windows takes back its own size as it is
// pulled away. Resized from outside, the window kept being placed from where
// the drag began and slid out from under the pointer, and where a drag began
// is the controller's own. So the window is placed with the pointer at the
// share of its width where it was taken hold of, and as far below its top as
// that point was, and the drag is begun again from there, in the same mode and
// with the same grab. Where it was taken hold of is the last press: until the
// threshold is passed the window has not moved, and the pointer is already
// somewhere else.
//
// Where the window stood before the drag is taken as the button goes down,
// once Hyprland has dealt with the press and given the window clicked the
// focus. By the time the drag is reported the window has moved already, by
// the first step of the drag, and a window dragged by its own title bar
// starts its drag later still, when the application asks for it.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>

// The C library, under C linkage.
#include <lua.hpp>

#include <algorithm>
#include <chrono>
#include <format>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener moveListener;
    CHyprSignalListener buttonListener;

    bool                  dragging = false;
    std::string           draggedAddress;
    std::string           draggedMode;
    // What is waiting for the next turn of the loop, by its number there, so
    // it can be taken back as the plugin is unloaded: its code goes with the
    // plugin, and run after that it would end the compositor.
    uint64_t              checkLater = 0;
    uint64_t              pressLater = 0;
    bool                  regrabbing  = false;
    Vector2D              lastPress;
    PHLWINDOWREF          pressWindow;
    CBox                  pressBox;
    std::chrono::steady_clock::time_point lastPosition;

    void post(const std::string& data) {
        if (g_pEventManager)
            g_pEventManager->postEvent({.event = "windowdrag", .data = data});
    }

    std::string pointer() {
        const auto at = g_pInputManager ? g_pInputManager->getMouseCoordsInternal() : Vector2D{};
        return std::format("{},{}", static_cast<int>(at.x), static_cast<int>(at.y));
    }

    void check() {
        checkLater = 0;
        if (!g_layoutManager || regrabbing)
            return;
        const auto& controller = g_layoutManager->dragController();
        const auto  target     = controller ? controller->target() : nullptr;
        const auto  window     = target ? target->window() : nullptr;
        const bool  picked     = window && controller->dragThresholdReached();

        if (picked && !dragging) {
            dragging       = true;
            draggedAddress = std::format("0x{:x}", reinterpret_cast<uintptr_t>(window.get()));
            draggedMode    = controller->mode() == MBIND_MOVE ? "move" : "resize";
            lastPosition   = std::chrono::steady_clock::now();
            const CBox before = pressWindow.lock() == window ? pressBox : target->position();
            post(std::format("begin,{},{},{},{},{},{}", draggedAddress, draggedMode, static_cast<int>(before.x), static_cast<int>(before.y),
                             static_cast<int>(before.w), static_cast<int>(before.h)));
            return;
        }
        if (!picked && dragging && !target) {
            dragging = false;
            post(std::format("end,{},{},{}", draggedAddress, draggedMode, pointer()));
            return;
        }
        if (dragging && draggedMode == "move") {
            const auto now = std::chrono::steady_clock::now();
            if (now - lastPosition >= std::chrono::milliseconds(33)) {
                lastPosition = now;
                post("move," + pointer());
            }
        }
    }

    int regrab(lua_State* state) {
        const double width  = luaL_checknumber(state, 1);
        const double height = luaL_checknumber(state, 2);
        if (!g_layoutManager || !g_pInputManager || width < 1 || height < 1)
            return 0;
        const auto& controller = g_layoutManager->dragController();
        const auto  target     = controller ? controller->target() : nullptr;
        if (!target || controller->mode() != MBIND_MOVE)
            return 0;

        const auto   box   = target->position();
        const auto   mouse = g_pInputManager->getMouseCoordsInternal();
        const bool   held  = box.containsPoint(lastPress);
        const auto   from  = held ? lastPress : mouse;
        const double share = box.w > 0 ? std::clamp((from.x - box.x) / box.w, 0.0, 1.0) : 0.5;
        const double below = std::clamp(from.y - box.y, 0.0, std::max(0.0, height - 1));
        target->setPositionGlobal(CBox{mouse.x - share * width, mouse.y - below, width, height});

        const auto mode = controller->mode();
        const bool grab = controller->exclusiveDeviceGrab();
        regrabbing      = true;
        controller->dragEnd();
        controller->dragBegin(target, mode, std::nullopt, grab);
        regrabbing = false;
        return 0;
    }

    // The window the press went to, as it stood then.
    void notePress() {
        pressLater        = 0;
        const auto window = Desktop::focusState()->window();
        pressWindow       = window;
        if (window && window->m_target)
            pressBox = window->m_target->position();
    }

    // Once per turn of the loop, however many events arrived in it.
    void checkSoon() {
        if (checkLater != 0 || !g_pEventLoopManager)
            return;
        checkLater = g_pEventLoopManager->doLater([] { check(); });
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
        HyprlandAPI::addNotification(handle, "[drag-report] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[drag-report] version mismatch");
    }

    // Listened to, never cancelled.
    moveListener   = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo&) { checkSoon(); });
    buttonListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) {
        if (event.state == WL_POINTER_BUTTON_STATE_PRESSED && g_pInputManager) {
            lastPress = g_pInputManager->getMouseCoordsInternal();
            if (g_pEventLoopManager && pressLater == 0)
                pressLater = g_pEventLoopManager->doLater([] { notePress(); });
        }
        checkSoon();
    });

    HyprlandAPI::addLuaFunction(handle, "drag_report", "regrab", regrab);

    return {"drag-report", "Reports on the event socket when a window is moved or resized with the mouse", "yuki", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    moveListener.reset();
    buttonListener.reset();
    if (g_pEventLoopManager) {
        if (checkLater != 0)
            g_pEventLoopManager->removeDoLater(checkLater);
        if (pressLater != 0)
            g_pEventLoopManager->removeDoLater(pressLater);
    }
}
