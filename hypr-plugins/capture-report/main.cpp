// Tells the shell which programs are taking the screen from the compositor.
//
// Hyprland says on its event socket that the screen began or stopped being
// taken, and which part of it, but not by whom: the client is kept on the
// capture session and nowhere else. A program taking the screen through the
// portal is named by PipeWire, but one taking it straight from the compositor,
// a screen recorder or a screenshot tool, is named nowhere.
//
// So whenever a capture starts or stops, every program taking the screen at
// that moment is reported on the event socket, as one list:
//
//     capturers>>[{"pid":1234,"name":"wf-recorder","type":"monitor","target":"eDP-1"}]
//
// The whole list each time rather than what started and what stopped, so a
// shell that missed one hears the truth with the next. The shell asks for it
// again as it starts with hl.plugin.capture_report.announce().

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/protocols/types/Buffer.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/Renderer.hpp>

#include <wayland-server-core.h>
#include <lua.hpp>

#include <format>
#include <fstream>
#include <string>

// The session keeps its client, its kind and its target to itself. Opened up
// here only, after every header it needs has been read without it.
#define private public
#include <hyprland/src/managers/screenshare/ScreenshareManager.hpp>
#undef private

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener stateListener;
    // The report waiting for the next turn of the loop, by its number there,
    // so it can be taken back as the plugin is unloaded: its code goes with
    // the plugin. Several changes in one turn need one report.
    uint64_t            announceLater = 0;

    std::string processName(pid_t pid) {
        std::ifstream file(std::format("/proc/{}/comm", pid));
        std::string   name;
        std::getline(file, name);
        return name;
    }

    std::string jsonString(const std::string& text) {
        std::string out = "\"";
        for (const unsigned char c : text) {
            if (c == '"' || c == '\\')
                out += std::format("\\{}", static_cast<char>(c));
            else if (c < 0x20)
                out += std::format("\\u{:04x}", c);
            else
                out += static_cast<char>(c);
        }
        return out + "\"";
    }

    std::string capturers() {
        std::string out   = "[";
        bool        first = true;
        const auto& manager = Screenshare::mgr();
        if (manager) {
            for (const auto& weak : manager->m_sessions) {
                // Owned by unique pointers, so read through the weak one as it
                // is: locking a weak pointer over a unique one is refused, and
                // the refusal ends the compositor.
                if (!weak.valid())
                    continue;
                const auto* session = weak.get();
                if (!session || session->m_stopped || !session->m_sharing || !session->m_client)
                    continue;
                pid_t pid = 0;
                uid_t uid = 0;
                gid_t gid = 0;
                wl_client_get_credentials(session->m_client, &pid, &uid, &gid);
                out += std::format("{}{{\"pid\":{},\"name\":{},\"type\":\"{}\",\"target\":{}}}", first ? "" : ",", pid,
                                   jsonString(processName(pid)), session->m_type, jsonString(session->m_name));
                first = false;
            }
        }
        return out + "]";
    }

    // On the next turn of the loop, once the session that started or stopped
    // has settled whether it is sharing.
    void announceSoon() {
        if (!g_pEventLoopManager || announceLater != 0)
            return;
        announceLater = g_pEventLoopManager->doLater([] {
            announceLater = 0;
            if (IPC::Socket2::sock())
                IPC::Socket2::sock()->postEvent({.event = "capturers", .data = capturers()});
        });
    }

    int announce(lua_State*) {
        announceSoon();
        return 0;
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
        HyprlandAPI::addNotification(handle, "[capture-report] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[capture-report] version mismatch");
    }

    stateListener = Event::bus()->m_events.screenshare.state.listen([](bool, uint8_t, const std::string&) { announceSoon(); });
    HyprlandAPI::addLuaFunction(handle, "capture_report", "announce", announce);

    return {"capture-report", "Reports on the event socket which programs are taking the screen", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    stateListener.reset();
    if (g_pEventLoopManager && announceLater != 0)
        g_pEventLoopManager->removeDoLater(announceLater);
}
