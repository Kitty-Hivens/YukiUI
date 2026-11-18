// Hands the shell the icon a window gives itself, for an application the
// shell finds no desktop entry for.
//
// A Wayland window gives its icon through xdg-toplevel-icon-v1, which Hyprland
// does not take: it draws no icons anywhere. This plugin takes it. An X11
// window carries its icon in _NET_WM_ICON, which only a client of the X server
// can read, and the compositor is the one client that always is.
//
// Either way the icon is written for the shell under yuki-window-icons in its
// runtime folder, YUKI_RUNTIME_DIR or XDG_RUNTIME_DIR, by the window's class lowercased with
// anything but letters, digits, dots, dashes and underscores made an
// underscore: <class>.png for a picture, the largest given, and <class>.name
// for the name of an icon in the theme. Written whole and renamed into place,
// so the shell never reads half a file. A window that takes its icon back
// takes the files away. They outlive the window otherwise, for a pinned
// application with no window open.

// The XWayland window manager keeps its connection and screen privately, the
// X11 backend its surface and the Wayland backend its xdg surface. Included before anything else could include
// them, after the standard headers they pull in, which redefined access breaks.
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
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/protocols/types/WLBuffer.hpp>
#include <hyprland/src/protocols/types/Buffer.hpp>

#include <cairo.h>
#include <drm_fourcc.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>

#include "xdg-toplevel-icon-v1-server-protocol.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <format>

namespace {
    HANDLE              handle = nullptr;
    CHyprSignalListener openListener;
    CFunctionHook*      propertyNotifyHook = nullptr;
    wl_global*          manager            = nullptr;

    // Where the shell keeps its runtime files: YUKI_RUNTIME_DIR, as a second
    // shell beside the session's is given, or the session's runtime folder.
    std::filesystem::path iconDir() {
        for (const char* name : {"YUKI_RUNTIME_DIR", "XDG_RUNTIME_DIR"})
            if (const char* value = std::getenv(name); value && *value)
                return std::filesystem::path(value) / "yuki-window-icons";
        return "/tmp/yuki-window-icons";
    }

    std::string keyOf(const std::string& appClass) {
        std::string key;
        for (const unsigned char c : appClass) {
            const auto lower = static_cast<char>(std::tolower(c));
            key += std::isalnum(c) || lower == '.' || lower == '-' || lower == '_' ? lower : '_';
        }
        return key;
    }

    /** A square picture, its pixels premultiplied ARGB32, as cairo takes them. */
    struct SImage {
        int                   size = 0;
        std::vector<uint32_t> pixels;
    };

    void writeName(const std::string& key, const std::string& name) {
        std::error_code error;
        std::filesystem::create_directories(iconDir(), error);
        const auto target = iconDir() / (key + ".name");
        const auto staged = iconDir() / (key + ".name.new");
        {
            std::ofstream out(staged, std::ios::trunc);
            out << name;
        }
        std::filesystem::rename(staged, target, error);
    }

    void writeImage(const std::string& key, const SImage& image) {
        std::error_code error;
        std::filesystem::create_directories(iconDir(), error);
        const auto target  = iconDir() / (key + ".png");
        const auto staged  = iconDir() / (key + ".png.new");
        auto       pixels  = image.pixels;
        auto*      surface = cairo_image_surface_create_for_data(reinterpret_cast<unsigned char*>(pixels.data()), CAIRO_FORMAT_ARGB32, image.size, image.size,
                                                                 image.size * 4);
        const bool written = cairo_surface_write_to_png(surface, staged.c_str()) == CAIRO_STATUS_SUCCESS;
        cairo_surface_destroy(surface);
        if (written)
            std::filesystem::rename(staged, target, error);
    }

    void forget(const std::string& key) {
        std::error_code error;
        std::filesystem::remove(iconDir() / (key + ".png"), error);
        std::filesystem::remove(iconDir() / (key + ".name"), error);
    }

    xcb_atom_t iconAtom() {
        static xcb_connection_t* internedOn = nullptr;
        static xcb_atom_t        atom       = XCB_ATOM_NONE;
        auto* connection = g_pXWayland && g_pXWayland->m_wm ? g_pXWayland->m_wm->getConnection() : nullptr;
        if (!connection)
            return XCB_ATOM_NONE;
        if (connection != internedOn) {
            internedOn        = connection;
            const auto cookie = xcb_intern_atom(connection, 0, std::strlen("_NET_WM_ICON"), "_NET_WM_ICON");
            auto*      reply  = xcb_intern_atom_reply(connection, cookie, nullptr);
            atom              = reply ? reply->atom : static_cast<xcb_atom_t>(XCB_ATOM_NONE);
            free(reply);
        }
        return atom;
    }

    // The largest square picture in a _NET_WM_ICON, which lists pictures as a
    // width, a height and that many pixels, ARGB and not premultiplied. One
    // that is not square is centred on a square of transparency.
    std::optional<SImage> largestIcon(const uint32_t* data, size_t length) {
        std::optional<SImage> best;
        size_t                at = 0;
        while (at + 2 <= length) {
            const size_t width = data[at], height = data[at + 1];
            at += 2;
            if (width == 0 || height == 0 || width > 1024 || height > 1024 || at + width * height > length)
                break;
            const size_t side = std::max(width, height);
            if (!best || static_cast<int>(side) > best->size) {
                SImage image{.size = static_cast<int>(side), .pixels = std::vector<uint32_t>(side * side, 0)};
                const size_t left = (side - width) / 2, top = (side - height) / 2;
                for (size_t y = 0; y < height; ++y)
                    for (size_t x = 0; x < width; ++x) {
                        const uint32_t pixel = data[at + y * width + x];
                        const uint32_t alpha = pixel >> 24;
                        const auto     scale = [alpha](uint32_t channel) { return (channel * alpha + 127) / 255; };
                        image.pixels[(top + y) * side + left + x] =
                            (alpha << 24) | (scale((pixel >> 16) & 0xff) << 16) | (scale((pixel >> 8) & 0xff) << 8) | scale(pixel & 0xff);
                    }
                best = std::move(image);
            }
            at += width * height;
        }
        return best;
    }

    SP<CXWaylandSurface> xSurfaceOf(const PHLWINDOW& window) {
        auto* x11 = window ? dynamic_cast<Desktop::View::CX11Backend*>(&window->backend()) : nullptr;
        return x11 ? x11->m_xwaylandSurface.lock() : nullptr;
    }

    void readX11Icon(const PHLWINDOW& window) {
        const auto surface    = xSurfaceOf(window);
        auto*      connection = g_pXWayland && g_pXWayland->m_wm ? g_pXWayland->m_wm->getConnection() : nullptr;
        const auto atom       = iconAtom();
        if (!surface || !connection || atom == XCB_ATOM_NONE || surface->m_overrideRedirect)
            return;
        const auto appClass = window->metadata().appID();
        if (appClass.empty())
            return;
        // Up to a 1024 pixel picture and its smaller ones.
        const auto cookie = xcb_get_property(connection, 0, surface->m_xID, atom, XCB_ATOM_CARDINAL, 0, 4 * 1024 * 1024);
        auto*      reply  = xcb_get_property_reply(connection, cookie, nullptr);
        if (!reply)
            return;
        if (reply->format == 32 && xcb_get_property_value_length(reply) > 0) {
            const auto image = largestIcon(static_cast<const uint32_t*>(xcb_get_property_value(reply)), xcb_get_property_value_length(reply) / sizeof(uint32_t));
            if (image)
                writeImage(keyOf(appClass), *image);
        }
        free(reply);
    }

    using PropertyNotify = void (*)(void*, xcb_property_notify_event_t*);

    // An X11 application often gives its icon after it has shown its window,
    // and may change it later.
    void propertyNotify(void* wm, xcb_property_notify_event_t* event) {
        reinterpret_cast<PropertyNotify>(propertyNotifyHook->m_original)(wm, event);
        if (!event || event->atom != iconAtom() || !g_pXWayland || !g_pXWayland->m_wm)
            return;
        const auto surface = g_pXWayland->m_wm->windowForXID(event->window);
        if (!surface)
            return;
        for (const auto& window : Desktop::windowState()->windows())
            if (window && window->mapped() && xSurfaceOf(window) == surface)
                readX11Icon(window);
    }

    /** What an icon object holds until it is given to a window, after which it may not change. */
    struct SIcon {
        std::string         name;
        std::vector<SImage> images;
        bool                given = false;
    };

    std::vector<wl_resource*> liveResources;

    void forgetResource(wl_resource* resource) {
        std::erase(liveResources, resource);
    }

    SIcon* iconOf(wl_resource* resource) {
        return static_cast<SIcon*>(wl_resource_get_user_data(resource));
    }

    void iconDestroy(wl_client*, wl_resource* resource) {
        wl_resource_destroy(resource);
    }

    void iconSetName(wl_client*, wl_resource* resource, const char* name) {
        auto* icon = iconOf(resource);
        if (icon->given) {
            wl_resource_post_error(resource, XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE, "the icon was already given to a window");
            return;
        }
        icon->name = name ? name : "";
    }

    void iconAddBuffer(wl_client*, wl_resource* resource, wl_resource* bufferResource, int32_t) {
        auto* icon = iconOf(resource);
        if (icon->given) {
            wl_resource_post_error(resource, XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE, "the icon was already given to a window");
            return;
        }
        // Hyprland keeps shared memory buffers of its own, which libwayland's
        // wl_shm_buffer_get does not know.
        const auto wlBuffer = CWLBufferResource::fromResource(bufferResource);
        const auto buffer   = wlBuffer ? wlBuffer->m_buffer.lock() : nullptr;
        const auto shm      = buffer ? buffer->shm() : Aquamarine::SSHMAttrs{};
        if (!shm.success) {
            wl_resource_post_error(resource, XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER, "the buffer is not shared memory");
            return;
        }
        const int  width  = static_cast<int>(shm.size.x);
        const int  height = static_cast<int>(shm.size.y);
        const bool opaque = shm.format == DRM_FORMAT_XRGB8888;
        if (width != height || width <= 0 || width > 1024 || (shm.format != DRM_FORMAT_ARGB8888 && !opaque)) {
            wl_resource_post_error(resource, XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER, "the buffer is not a square ARGB8888 or XRGB8888 picture");
            return;
        }
        // Copied now: the client may reuse the buffer once the request is done.
        const auto [data, format, length] = buffer->beginDataPtr(0);
        if (!data || length < static_cast<size_t>(shm.stride) * height) {
            buffer->endDataPtr();
            wl_resource_post_error(resource, XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER, "the buffer could not be read");
            return;
        }
        SImage image{.size = width, .pixels = std::vector<uint32_t>(static_cast<size_t>(width) * height)};
        for (int y = 0; y < height; ++y) {
            std::memcpy(&image.pixels[static_cast<size_t>(y) * width], data + static_cast<size_t>(y) * shm.stride, static_cast<size_t>(width) * 4);
            if (opaque)
                for (int x = 0; x < width; ++x)
                    image.pixels[static_cast<size_t>(y) * width + x] |= 0xff000000;
        }
        buffer->endDataPtr();
        icon->images.push_back(std::move(image));
    }

    const struct xdg_toplevel_icon_v1_interface iconImplementation = {
        .destroy    = iconDestroy,
        .set_name   = iconSetName,
        .add_buffer = iconAddBuffer,
    };

    void iconResourceDestroyed(wl_resource* resource) {
        forgetResource(resource);
        delete iconOf(resource);
    }

    void managerDestroy(wl_client*, wl_resource* resource) {
        wl_resource_destroy(resource);
    }

    void managerCreateIcon(wl_client* client, wl_resource* resource, uint32_t id) {
        auto* icon = wl_resource_create(client, &xdg_toplevel_icon_v1_interface, wl_resource_get_version(resource), id);
        if (!icon) {
            wl_client_post_no_memory(client);
            return;
        }
        wl_resource_set_implementation(icon, &iconImplementation, new SIcon, iconResourceDestroyed);
        liveResources.push_back(icon);
    }

    void giveIcon(const PHLWINDOW& window, const SIcon& icon) {
        const auto key = keyOf(window->metadata().appID());
        if (key.empty())
            return;
        forget(key);
        if (!icon.name.empty())
            writeName(key, icon.name);
        const auto largest = std::ranges::max_element(icon.images, {}, &SImage::size);
        if (largest != icon.images.end())
            writeImage(key, *largest);
    }

    /**
     * Icons given before their window was shown, as a toolkit may give one as
     * it makes the window. Hyprland has no window for the toplevel then, nor
     * a class for it: the icon waits for the window to open.
     */
    std::vector<std::pair<WP<CXDGToplevelResource>, SIcon>> waiting;

    SP<CXDGToplevelResource> toplevelOf(const PHLWINDOW& window) {
        auto* wayland = window ? dynamic_cast<Desktop::View::CWaylandBackend*>(&window->backend()) : nullptr;
        const auto xdg = wayland ? wayland->m_resource.lock() : nullptr;
        return xdg ? xdg->m_toplevel.lock() : nullptr;
    }

    void giveWaiting(const PHLWINDOW& window) {
        std::erase_if(waiting, [](const auto& entry) { return entry.first.expired(); });
        const auto toplevel = toplevelOf(window);
        if (!toplevel)
            return;
        const auto found = std::ranges::find_if(waiting, [&](const auto& entry) { return entry.first.lock() == toplevel; });
        if (found == waiting.end())
            return;
        giveIcon(window, found->second);
        waiting.erase(found);
    }

    void managerSetIcon(wl_client*, wl_resource*, wl_resource* toplevelResource, wl_resource* iconResource) {
        const auto toplevel = CXDGToplevelResource::fromResource(toplevelResource);
        if (!toplevel)
            return;
        std::erase_if(waiting, [&](const auto& entry) { return entry.first.expired() || entry.first.lock() == toplevel; });
        auto*      icon   = iconResource ? iconOf(iconResource) : nullptr;
        const auto window = toplevel->m_window.lock();
        if (icon)
            icon->given = true;
        if (!window || !window->mapped()) {
            if (icon)
                waiting.emplace_back(toplevel, *icon);
            return;
        }
        if (icon)
            giveIcon(window, *icon);
        else
            forget(keyOf(window->metadata().appID()));
    }

    const struct xdg_toplevel_icon_manager_v1_interface managerImplementation = {
        .destroy     = managerDestroy,
        .create_icon = managerCreateIcon,
        .set_icon    = managerSetIcon,
    };

    void managerBind(wl_client* client, void*, uint32_t version, uint32_t id) {
        auto* resource = wl_resource_create(client, &xdg_toplevel_icon_manager_v1_interface, std::min<uint32_t>(version, 1), id);
        if (!resource) {
            wl_client_post_no_memory(client);
            return;
        }
        wl_resource_set_implementation(resource, &managerImplementation, nullptr, forgetResource);
        liveResources.push_back(resource);
        // The sizes the dock draws icons at, at one and two times.
        xdg_toplevel_icon_manager_v1_send_icon_size(resource, 64);
        xdg_toplevel_icon_manager_v1_send_icon_size(resource, 128);
        xdg_toplevel_icon_manager_v1_send_done(resource);
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
        HyprlandAPI::addNotification(handle, "[window-icons] built against another Hyprland, not loaded", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[window-icons] version mismatch");
    }

    manager = wl_global_create(g_pCompositor->m_wlDisplay, &xdg_toplevel_icon_manager_v1_interface, 1, nullptr, managerBind);
    if (!manager)
        HyprlandAPI::addNotification(handle, "[window-icons] could not offer xdg-toplevel-icon, Wayland windows give no icons", CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    openListener = Event::bus()->m_events.window.open.listen([](const PHLWINDOW& window) {
        readX11Icon(window);
        giveWaiting(window);
    });

    void* target = nullptr;
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "handlePropertyNotify")) {
        if (match.demangled.find("CXWM::handlePropertyNotify") != std::string::npos) {
            target = match.address;
            break;
        }
    }
    if (target)
        propertyNotifyHook = HyprlandAPI::createFunctionHook(handle, target, reinterpret_cast<void*>(&propertyNotify));
    if (!propertyNotifyHook || !propertyNotifyHook->hook())
        HyprlandAPI::addNotification(handle, "[window-icons] could not hook X11 property changes, an icon given after a window shows is missed",
                                     CHyprColor{1.0, 0.6, 0.2, 1.0}, 5000);

    // Windows already open when the plugin came in.
    for (const auto& window : Desktop::windowState()->windows())
        if (window && window->mapped())
            readX11Icon(window);

    return {"window-icons", "Hands the shell the icons windows give themselves, through xdg-toplevel-icon and _NET_WM_ICON", "yuki", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    openListener.reset();
    // The objects clients hold point into this plugin's code, which goes with
    // it. Taken away first, so a request after the plugin has gone is refused
    // by the compositor rather than run into nothing.
    if (manager)
        wl_global_destroy(manager);
    manager = nullptr;
    const auto live = liveResources;
    for (auto* resource : live)
        wl_resource_destroy(resource);
    liveResources.clear();
    waiting.clear();
}
