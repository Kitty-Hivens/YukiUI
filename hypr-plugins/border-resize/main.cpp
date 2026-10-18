// Resizing a window by its border with the left button only, and never while a
// game holds the pointer.
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

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>

#include <linux/input-event-codes.h>

#include <string>

namespace {
    HANDLE         handle = nullptr;
    CFunctionHook* hook   = nullptr;

    using ResizeWithBorder = void (*)(CKeybindManager*, const IPointer::SButtonEvent&);

    void resizeWithBorder(CKeybindManager* manager, const IPointer::SButtonEvent& event) {
        if (event.button != BTN_LEFT || (g_pInputManager && g_pInputManager->isConstrained())) {
            if (g_pSeatManager)
                g_pSeatManager->sendPointerButton(event.timeMs, event.button, event.state);
            return;
        }
        reinterpret_cast<ResizeWithBorder>(hook->m_original)(manager, event);
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

    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "resizeWithBorder")) {
        if (match.demangled.find("CKeybindManager::resizeWithBorder") != std::string::npos) {
            target = match.address;
            break;
        }
    }
    if (!target) {
        HyprlandAPI::addNotification(handle, "[border-resize] nothing to hook in this Hyprland, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);
        return {"border-resize", "Resizes by the border with the left button only, and not while a game holds the pointer", "yuki", "1.0"};
    }

    hook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&resizeWithBorder));
    if (!hook || !hook->hook())
        HyprlandAPI::addNotification(handle, "[border-resize] could not hook, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"border-resize", "Resizes by the border with the left button only, and not while a game holds the pointer", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hooks are taken down with the plugin by Hyprland itself.
}
