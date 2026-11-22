// Tells the surface a fullscreen window is shown from that its buffers can go
// straight to the screen, whenever that surface changes.
//
// For direct scanout a buffer has to be made for the display. The client makes
// it so only when the dmabuf feedback of its surface offers a scanout tranche,
// and on the xe kernel driver a buffer made without it cannot become a
// framebuffer at all once the GPU has drawn into it. Hyprland sends that
// tranche once, as a window goes fullscreen, to the surface it would show
// then. Wine draws OpenGL into a subsurface that comes up after that, so the
// tranche never reached it, no buffer of a Wine game could be scanned out,
// and the compositor drew every frame of it again itself.
//
// Checked as each monitor is about to render. The tranche goes to the surface
// shown when it is not the window's main surface, which Hyprland looks after
// itself, and the plain feedback goes back to it once it no longer is.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/LinuxDMABUF.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/types/ContentType.hpp>

#include <unordered_map>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener preRender;
    CHyprSignalListener monitorRemoved;
    // Monitor -> the surface the tranche was last sent to here.
    std::unordered_map<const Monitor::CMonitor*, WP<CWLSurfaceResource>> sent;

    // The same test Hyprland makes before it sends the tranche at all.
    bool scanoutWanted(const PHLWINDOW& window) {
        static auto PDIRECTSCANOUT = CConfigValue<Config::INTEGER>("render:direct_scanout");
        return *PDIRECTSCANOUT == 1 || (*PDIRECTSCANOUT == 2 && window->getContentType() == NContentType::CONTENT_TYPE_GAME);
    }

    void check(const PHLMONITOR& monitor) {
        if (!monitor || !PROTO::linuxDma)
            return;

        SP<CWLSurfaceResource> shown;
        if (const auto window = monitor->m_solitaryClient.lock(); window && scanoutWanted(window)) {
            const auto solitary = window->getSolitaryResource();
            const auto main     = window->wlSurface() ? window->wlSurface()->resource() : nullptr;
            if (solitary && solitary != main)
                shown = solitary;
        }

        auto& last = sent[monitor.get()];
        if (shown == last.lock())
            return;
        if (const auto previous = last.lock())
            PROTO::linuxDma->updateScanoutTranche(previous, nullptr);
        if (shown)
            PROTO::linuxDma->updateScanoutTranche(shown, monitor);
        last = shown;
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
        HyprlandAPI::addNotification(handle, "[scanout-feedback] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[scanout-feedback] version mismatch");
    }

    preRender      = Event::bus()->m_events.render.pre.listen([](PHLMONITOR monitor) { check(monitor); });
    monitorRemoved = Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR monitor) { sent.erase(monitor.get()); });

    return {"scanout-feedback", "Offers direct scanout to the subsurface a fullscreen window is shown from", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    preRender.reset();
    monitorRemoved.reset();
    // What was offered is taken back, so no client keeps making buffers for a
    // scanout nothing will attempt any more.
    if (PROTO::linuxDma) {
        for (const auto& [_, surface] : sent) {
            if (const auto previous = surface.lock())
                PROTO::linuxDma->updateScanoutTranche(previous, nullptr);
        }
    }
    sent.clear();
}
