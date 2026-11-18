// Lets a pen reach a window that holds the pointer locked.
//
// A game under Wine on Wayland locks the pointer while its window is
// fullscreen and its cursor hidden, which on one screen is always: Wine
// confines a fullscreen window's cursor by itself, and a confined hidden
// cursor becomes a lock taking relative motion only. A pen tablet moves the
// pointer to a place, not by an amount. Hyprland moves the pointer there and,
// with a lock in force, puts it straight back, so the window under the lock
// was never told anything had moved, and the pen did nothing in the game in
// any mode of the tablet driver.
//
// While a lock is in force, each place a tablet or another absolute pointing
// device moves the pointer to is told to the window as relative motion: the
// way from the place before. Wine moves its cursor by it, and the pen's place
// on the screen and the cursor's in the game stay together. They part only
// where the game stops its cursor short of the pen, at an edge, or where a
// mouse moves the cursor in between.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/protocols/RelativePointer.hpp>
#include <hyprland/src/devices/IHID.hpp>

#include <chrono>
#include <cmath>
#include <unordered_map>

namespace {
    HANDLE         handle    = nullptr;
    CFunctionHook* warpHook  = nullptr;

    // Where each device last put the pointer, kept whether a lock is in force
    // or not, so the first move under a lock is measured from where the pen
    // really was. A device is known by its address alone and never followed:
    // one that goes away leaves a stale place a new one at the same address
    // starts from, which costs one jump of the cursor.
    std::unordered_map<const IHID*, Vector2D> lastPlace;

    using WarpAbsolute = void (*)(Pointer::CPointerManager*, Vector2D, SP<IHID>, WP<Aquamarine::IOutput>);

    uint64_t nowMicroseconds() {
        return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    void warpAbsolute(Pointer::CPointerManager* manager, Vector2D abs, SP<IHID> device, WP<Aquamarine::IOutput> output) {
        reinterpret_cast<WarpAbsolute>(warpHook->m_original)(manager, abs, device, output);

        // Touch is left alone: a finger on a screen means a place, and a game
        // holding the pointer has no use for one.
        if (!device || (device->getType() != HID_TYPE_TABLET && device->getType() != HID_TYPE_POINTER))
            return;

        // Read before the lock puts the pointer back, which happens as the
        // move is handled further on, not in here.
        const Vector2D place = manager->position();
        const auto     known = lastPlace.find(device.get());
        if (known == lastPlace.end()) {
            lastPlace.emplace(device.get(), place);
            return;
        }
        const Vector2D delta = place - known->second;
        known->second        = place;
        if (!g_pInputManager || !g_pInputManager->isLocked())
            return;

        if (std::abs(delta.x) < 0.001 && std::abs(delta.y) < 0.001)
            return;

        PROTO::relativePointer->sendRelativeMotion(nowMicroseconds(), delta, delta);
        // A tablet's move ends in no pointer frame of its own, and the motion
        // waits for one. An absolute pointer's move is framed further on.
        if (device->getType() == HID_TYPE_TABLET && g_pSeatManager)
            g_pSeatManager->sendPointerFrame();
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
        HyprlandAPI::addNotification(handle, "[pen-lock] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[pen-lock] version mismatch");
    }

    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "warpAbsolute")) {
        if (match.demangled.find("CPointerManager::warpAbsolute") != std::string::npos) {
            target = match.address;
            break;
        }
    }
    if (target)
        warpHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&warpAbsolute));
    if (!warpHook || !warpHook->hook())
        HyprlandAPI::addNotification(handle, "[pen-lock] could not hook absolute pointer moves, a pen does nothing in a window holding the pointer", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"pen-lock", "Tells a window holding the pointer locked how a pen tablet moves", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    lastPlace.clear();
}
