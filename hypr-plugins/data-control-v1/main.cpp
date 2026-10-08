// Keeps the second version's event from clients of the first version of
// wlr-data-control.
//
// The primary selection came to wlr-data-control in its second version, with
// an event of its own. Hyprland 0.56 sends that event to every client of the
// protocol, as the clipboard is first handed to it and whenever the primary
// selection changes, whichever version the client asked for. A client of the
// first version has no handler for it, and libwayland ends the thread that
// reads its events. Wine's Wayland driver is such a client: its clipboard
// bridge died as it started, and nothing was copied into Windows programs or
// out of them, text included.
//
// Later Hyprland sends the event only to clients of the second version, which
// is what this does here, in the one function that sends it.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/protocols/WaylandProtocol.hpp>
#include <hyprland/src/protocols/types/DataDevice.hpp>
#include <hyprland/protocols/wlr-data-control-unstable-v1.hpp>
#include <hyprutils/os/FileDescriptor.hpp>

#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

// The device keeps its resource to itself. Opened up here only, after every
// header it needs has been read without it.
#define private public
#include <hyprland/src/protocols/DataDeviceWlr.hpp>
#undef private

namespace {
    HANDLE         handle = nullptr;
    CFunctionHook* hook   = nullptr;

    using SendSelection = void (*)(CDataDeviceWLRProtocol*, SP<CWLRDataDevice>, SP<IDataSource>, bool);

    void sendSelectionToDevice(CDataDeviceWLRProtocol* protocol, SP<CWLRDataDevice> device, SP<IDataSource> source, bool primary) {
        if (primary && device && device->m_resource && device->m_resource->version() < 2)
            return;
        reinterpret_cast<SendSelection>(hook->m_original)(protocol, device, source, primary);
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
        HyprlandAPI::addNotification(handle, "[data-control-v1] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[data-control-v1] version mismatch");
    }

    // The one function by that name in the wlr protocol, and not its
    // namesake in ext-data-control, which has the event from its first version.
    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "sendSelectionToDevice")) {
        if (match.demangled.find("CDataDeviceWLRProtocol::sendSelectionToDevice") != std::string::npos) {
            target = match.address;
            break;
        }
    }
    if (!target) {
        HyprlandAPI::addNotification(handle, "[data-control-v1] nothing to hook in this Hyprland, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);
        return {"data-control-v1", "Keeps wlr-data-control's second-version event from first-version clients", "yuki", "1.0"};
    }

    hook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&sendSelectionToDevice));
    if (!hook || !hook->hook())
        HyprlandAPI::addNotification(handle, "[data-control-v1] could not hook, left as it is", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"data-control-v1", "Keeps wlr-data-control's second-version event from first-version clients", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hooks are taken down with the plugin by Hyprland itself.
}
