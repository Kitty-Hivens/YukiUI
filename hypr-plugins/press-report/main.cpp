// Tells the shell where each mouse press lands, without taking it.
//
// A panel of the shell is closed by a click outside it. The only way a client
// can hear of such a click is a focus grab, and Hyprland ends a grab by eating
// the click that ends it: the window clicked on neither gets the click nor, as
// often as not, the focus. Clicking a window to leave a menu should do both.
//
// So every press is reported on the event socket, as it happens and before
// anything else sees it, with what is under the pointer:
//
//     pointerpress>>layer,<namespace>    a layer surface, or a popup of one
//     pointerpress>>window,<address>     a window, or a popup of one
//     pointerpress>>none,                nothing, or something else
//
// and the press goes on its way untouched. The shell closes its panels on a
// press that does not land on one of its own surfaces.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/desktop/view/WLSurface.hpp>
#include <hyprland/src/desktop/view/View.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/desktop/view/Popup.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>

#include <format>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener pressListener;

    std::string describe(SP<Desktop::View::IView> view) {
        if (!view)
            return "none,";
        // A popup counts as what it belongs to: a menu of the dock is the dock.
        if (const auto popup = Desktop::View::CPopup::fromView(view)) {
            const auto owner = popup->getT1Owner();
            view = owner ? owner->view() : nullptr;
            if (!view)
                return "none,";
        }
        if (const auto layer = Desktop::View::CLayerSurface::fromView(view))
            return "layer," + layer->m_namespace;
        if (const auto window = Desktop::View::CWindow::fromView(view))
            return std::format("window,0x{:x}", reinterpret_cast<uintptr_t>(window.get()));
        return "none,";
    }

    void report(const IPointer::SButtonEvent& event) {
        if (event.state != WL_POINTER_BUTTON_STATE_PRESSED || !g_pSeatManager || !IPC::Socket2::sock())
            return;
        const auto focus   = g_pSeatManager->m_state.pointerFocus.lock();
        const auto surface = focus ? Desktop::View::CWLSurface::fromResource(focus) : nullptr;
        IPC::Socket2::sock()->postEvent({.event = "pointerpress", .data = describe(surface ? surface->view() : nullptr)});
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
        HyprlandAPI::addNotification(handle, "[press-report] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[press-report] version mismatch");
    }

    // Listened to, never cancelled: the press goes on exactly as it would have.
    pressListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) { report(event); });

    return {"press-report", "Reports on the event socket where each mouse press lands, without taking it", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    pressListener.reset();
}
