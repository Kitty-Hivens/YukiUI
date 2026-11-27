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
// itself, and the plain feedback goes back to it once the window is no longer
// fullscreen. Not as something covers it, a notification over a game, or as its
// workspace goes out of sight: taking it back and giving it again had the
// client make all its buffers anew twice, for a notification to come and go.
//
// A client has buffers of the old kind for a few frames after that, and
// Hyprland tries them, fails to make a framebuffer of them, and has already
// changed the output's format to theirs: on a 10 bit screen with an 8 bit game
// that is a round of reallocating its own buffers in each format, and the
// screen showed a black frame as a game went to scanout. So a newly offered
// surface is not tried for a moment, in which the game is drawn by the
// compositor as it was.
//
// Leaving scanout puts the output's format back, which on a 10 bit screen with
// an 8 bit game is a modeset and the reallocation of the compositor's own
// buffers. A notification over a game left scanout and came back to it, with
// both at each end, and the game stuttered. So a game covered by a layer keeps
// the format it was shown in, and the compositor draws it in that until
// nothing covers it. The format goes back as the game is no longer shown.
//
// Hyprland changes the output's format as it leaves scanout and goes straight
// on to draw the frame, into a buffer of its swapchain, which is set to the new
// format only as the frame is committed: the frame drawn was thrown away for a
// new buffer nothing had been drawn into, and the screen showed it black. So
// the swapchain is set to the format as soon as the format changes.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/protocols/LinuxDMABUF.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/types/ContentType.hpp>

#include <chrono>
#include <unordered_map>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener preRender;
    CHyprSignalListener monitorRemoved;
    struct SOffered {
        WP<CWLSurfaceResource> surface;
        PHLWINDOWREF           window;
    };
    // Monitor -> the surface the tranche was last sent to here.
    std::unordered_map<const Monitor::CMonitor*, SOffered> sent;
    // Monitor -> until when scanout is not tried.
    std::unordered_map<const Monitor::CMonitor*, std::chrono::steady_clock::time_point> held;
    constexpr auto                                                                      HOLD = std::chrono::milliseconds(120);

    // Monitor -> the format it had before a game was shown in another, and the
    // game it is kept for.
    struct SKept {
        uint32_t     format = 0;
        PHLWINDOWREF game;
    };
    std::unordered_map<const Monitor::CMonitor*, SKept> formats;

    using Attempt              = bool (*)(Monitor::CMonitor*);
    using Leave                = void (*)(Monitor::CMonitor*);
    CFunctionHook* attemptHook = nullptr;
    CFunctionHook* leaveHook   = nullptr;

    // The fullscreen window still shown on a monitor's own workspace.
    PHLWINDOW gameOn(const PHLMONITOR& monitor) {
        const auto window = monitor->m_activeWorkspace ? Fullscreen::controller()->getFullscreenWindow(monitor->m_activeWorkspace) : nullptr;
        return window && window->mapped() && Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_FULLSCREEN) ? window : nullptr;
    }

    // The swapchain set to the format the output now has, before anything is
    // drawn for it. Left to the commit, the frame drawn went in a buffer of the
    // old format and was swapped for an empty one.
    void followFormat(Monitor::CMonitor* monitor) {
        if (monitor->m_output && monitor->m_output->swapchain)
            monitor->m_state.updateSwapchain();
    }

    // The output's own format back, when it was left in a game's.
    void restoreFormat(const PHLMONITOR& monitor) {
        const auto it = formats.find(monitor.get());
        if (it == formats.end())
            return;
        const auto format = it->second.format;
        formats.erase(it);
        monitor->m_prevDrmFormat = format;
        if (monitor->m_directScanoutIsActive || monitor->m_drmFormat == format)
            return;
        monitor->m_output->state->setFormat(format);
        monitor->m_drmFormat   = format;
        monitor->m_blurFBDirty = true;
        followFormat(monitor.get());
        monitor->m_damage.damageEntire();
        monitor->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_NEEDS_FRAME);
    }

    // The same test Hyprland makes before it sends the tranche at all.
    bool scanoutWanted(const PHLWINDOW& window) {
        static auto PDIRECTSCANOUT = CConfigValue<Config::INTEGER>("render:direct_scanout");
        return *PDIRECTSCANOUT == 1 || (*PDIRECTSCANOUT == 2 && window->getContentType() == NContentType::CONTENT_TYPE_GAME);
    }

    void check(const PHLMONITOR& monitor) {
        if (!monitor || !PROTO::linuxDma)
            return;

        SP<CWLSurfaceResource> shown;
        PHLWINDOW              shownWindow;
        if (const auto window = monitor->m_solitaryClient.lock(); window && scanoutWanted(window)) {
            const auto solitary = window->getSolitaryResource();
            const auto main     = window->wlSurface() ? window->wlSurface()->resource() : nullptr;
            if (solitary && solitary != main) {
                shown       = solitary;
                shownWindow = window;
            }
        }

        // The game the format was kept for no longer shown, or not fullscreen
        // any more: the format is over. Another fullscreen window shown
        // instead, a video on another workspace say, is not that game.
        if (const auto it = formats.find(monitor.get()); it != formats.end()) {
            const auto game = gameOn(monitor);
            if (!game || game != it->second.game.lock())
                restoreFormat(monitor);
        }

        auto& last = sent[monitor.get()];
        if (shown == last.surface.lock())
            return;
        // Nothing shown straight from a client now, while the one it was
        // offered to is still there and fullscreen: it is only out of sight.
        if (!shown && last.surface.lock()) {
            const auto window = last.window.lock();
            if (window && window->mapped() && scanoutWanted(window) && Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_FULLSCREEN))
                return;
        }
        if (const auto previous = last.surface.lock())
            PROTO::linuxDma->updateScanoutTranche(previous, nullptr);
        if (shown) {
            PROTO::linuxDma->updateScanoutTranche(shown, monitor);
            // One already shown from goes on being shown from.
            if (monitor->m_lastScanout.expired() && !monitor->m_directScanoutIsActive)
                held[monitor.get()] = std::chrono::steady_clock::now() + HOLD;
        } else
            held.erase(monitor.get());
        last = {shown, shownWindow};
    }

    // Scanout left. With a game only covered, its format is kept, and what
    // Hyprland does as it leaves is done but for putting the format back.
    void leave(Monitor::CMonitor* self) {
        const auto monitor = self->m_self.lock();
        const auto game    = monitor ? gameOn(monitor) : nullptr;
        if (!game || self->m_drmFormat == self->m_prevDrmFormat) {
            // Left for good: the output's own format, as it was before any
            // game was shown, whatever Hyprland took for it on the way in.
            if (const auto it = formats.find(self); it != formats.end()) {
                self->m_prevDrmFormat = it->second.format;
                formats.erase(it);
            }
            const auto before = self->m_drmFormat;
            reinterpret_cast<Leave>(leaveHook->m_original)(self);
            if (self->m_drmFormat != before)
                followFormat(self);
            return;
        }
        formats.try_emplace(self, SKept{self->m_prevDrmFormat, game});
        self->m_lastScanout.reset();
        self->m_previousFSWindow.reset();
        self->m_directScanoutIsActive = false;
        self->m_blurFBDirty           = true;
        self->m_damage.damageEntire();
    }

    // Before Hyprland tries to scan a window out, which is before the event
    // the check otherwise runs on.
    bool attempt(Monitor::CMonitor* self) {
        check(self->m_self.lock());
        if (const auto it = held.find(self); it != held.end()) {
            if (std::chrono::steady_clock::now() < it->second)
                return false;
            held.erase(it);
        }
        const bool scannedOut = reinterpret_cast<Attempt>(attemptHook->m_original)(self);
        // Entered from a format that was kept, Hyprland takes it for the
        // output's own, and would leave it there.
        if (const auto it = formats.find(self); it != formats.end())
            self->m_prevDrmFormat = it->second.format;
        return scannedOut;
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
    monitorRemoved = Event::bus()->m_events.monitor.removed.listen([](PHLMONITOR monitor) {
        sent.erase(monitor.get());
        held.erase(monitor.get());
        formats.erase(monitor.get());
    });

    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "attemptDirectScanout"))
        if (match.demangled.find("CMonitor::attemptDirectScanout") != std::string::npos)
            target = match.address;
    if (target)
        attemptHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&attempt));
    // Without it a game is scanned out all the same, and the screen may show a
    // black frame as it goes to it.
    const bool attempting = attemptHook && attemptHook->hook();
    if (!attempting)
        HyprlandAPI::addNotification(handle, "[scanout-feedback] could not hook direct scanout, a game may show a black frame as it goes to it", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);
    // Keeping a game's format takes both: the way in is what tells Hyprland
    // which format is the output's own. Kept without it, the output was left
    // in the game's format for good.
    void* leaveTarget = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "handleDSleave"))
        if (match.demangled.find("CMonitor::handleDSleave") != std::string::npos)
            leaveTarget = match.address;
    if (leaveTarget && attempting)
        leaveHook = HyprlandAPI::createFunctionHook(handle, leaveTarget, reinterpret_cast<void*>(&leave));
    if (!leaveHook || !leaveHook->hook())
        HyprlandAPI::addNotification(handle, "[scanout-feedback] could not hook leaving scanout, a notification over a game may make it stutter", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    return {"scanout-feedback", "Offers direct scanout to the subsurface a fullscreen window is shown from, and holds it until its buffers are made for it", "yuki", "1.2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    preRender.reset();
    monitorRemoved.reset();
    held.clear();
    // An output left in a game's format is put back, as nothing here would be
    // left to do it.
    for (const auto& monitor : State::monitorState()->monitors())
        if (monitor)
            restoreFormat(monitor);
    // What was offered is taken back, so no client keeps making buffers for a
    // scanout nothing will attempt any more.
    if (PROTO::linuxDma) {
        for (const auto& [_, offered] : sent) {
            if (const auto previous = offered.surface.lock())
                PROTO::linuxDma->updateScanoutTranche(previous, nullptr);
        }
    }
    sent.clear();
}
