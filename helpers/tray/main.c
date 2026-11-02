// Keeps the tray's icons across a restart of the shell.
//
//     yuki-tray
//
// A program registers its tray icon once, with whoever answers on the session
// bus as org.kde.StatusNotifierWatcher, and many never register it again: they
// do not watch for a new watcher to appear. The shell answers as that watcher
// itself, so every restart of the shell lost those icons for good.
//
// This answers from outside the shell, for the whole session. Started while
// the shell holds the name, it waits in the bus's queue for it and keeps a
// copy of what is registered there, so that when the shell lets go of the
// name, by restarting or dying, this one takes it over with every icon. The
// shell that comes up next finds the name taken and reads the icons from
// here, which its tray does with any watcher that is not its own.
//
// One runs at a time. A second one leaves at once.

#include <stdio.h>
#include <string.h>

#include <gio/gio.h>

#define WATCHER "org.kde.StatusNotifierWatcher"
#define WATCHER_PATH "/StatusNotifierWatcher"
#define KEEPER "org.yuki.TrayKeeper"

static const char *introspection =
    "<node>"
    "  <interface name='org.kde.StatusNotifierWatcher'>"
    "    <method name='RegisterStatusNotifierItem'><arg name='service' type='s' direction='in'/></method>"
    "    <method name='RegisterStatusNotifierHost'><arg name='service' type='s' direction='in'/></method>"
    "    <property name='RegisteredStatusNotifierItems' type='as' access='read'/>"
    "    <property name='IsStatusNotifierHostRegistered' type='b' access='read'/>"
    "    <property name='ProtocolVersion' type='i' access='read'/>"
    "    <signal name='StatusNotifierItemRegistered'><arg type='s'/></signal>"
    "    <signal name='StatusNotifierItemUnregistered'><arg type='s'/></signal>"
    "    <signal name='StatusNotifierHostRegistered'/>"
    "    <signal name='StatusNotifierHostUnregistered'/>"
    "  </interface>"
    "</node>";

static GDBusConnection *bus;
// Each registered icon as "service/path", the form the shell's watcher uses.
static GPtrArray *items;
// The bus names of the hosts, the trays that show the icons.
static GPtrArray *hosts;
// Whether this one holds the watcher's name. Until it does it only copies.
static gboolean holding;

static gboolean contains(GPtrArray *list, const char *value) {
    for (guint i = 0; i < list->len; i++)
        if (strcmp(list->pdata[i], value) == 0)
            return TRUE;
    return FALSE;
}

/** The bus name an icon lives at: what comes before the path. */
static gboolean belongs_to(const char *item, const char *service) {
    size_t length = strlen(service);
    return strncmp(item, service, length) == 0 && (item[length] == '/' || item[length] == '\0');
}

static void emit(const char *signal, GVariant *parameters) {
    if (!holding) {
        if (parameters)
            g_variant_unref(g_variant_ref_sink(parameters));
        return;
    }
    g_dbus_connection_emit_signal(bus, NULL, WATCHER_PATH, WATCHER, signal, parameters, NULL);
}

static void add_item(const char *item) {
    if (contains(items, item))
        return;
    g_ptr_array_add(items, g_strdup(item));
    emit("StatusNotifierItemRegistered", g_variant_new("(s)", item));
}

static void remove_item(const char *item) {
    for (guint i = 0; i < items->len; i++) {
        if (strcmp(items->pdata[i], item) == 0) {
            emit("StatusNotifierItemUnregistered", g_variant_new("(s)", item));
            g_ptr_array_remove_index(items, i);
            return;
        }
    }
}

/** An icon registered by path alone is at its sender, and one by name alone at the usual path. */
static char *qualified(const char *item, const char *sender) {
    if (item[0] == '/')
        return g_strconcat(sender, item, NULL);
    if (!strchr(item, '/'))
        return g_strconcat(item, "/StatusNotifierItem", NULL);
    return g_strdup(item);
}

// The watcher, as it answers once it holds the name.

static void on_method(GDBusConnection *connection, const char *sender, const char *path, const char *interface,
                      const char *method, GVariant *parameters, GDBusMethodInvocation *invocation, gpointer data) {
    (void)connection, (void)path, (void)interface, (void)data;
    const char *argument;
    g_variant_get(parameters, "(&s)", &argument);
    if (strcmp(method, "RegisterStatusNotifierItem") == 0) {
        char *item = qualified(argument, sender);
        add_item(item);
        g_free(item);
    } else if (strcmp(method, "RegisterStatusNotifierHost") == 0) {
        // Registered by the name it gave, or by its connection when it gave a path.
        const char *host = argument[0] == '/' ? sender : argument;
        if (!contains(hosts, host)) {
            g_ptr_array_add(hosts, g_strdup(host));
            emit("StatusNotifierHostRegistered", NULL);
        }
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}

static GVariant *on_property(GDBusConnection *connection, const char *sender, const char *path, const char *interface,
                             const char *property, GError **error, gpointer data) {
    (void)connection, (void)sender, (void)path, (void)interface, (void)error, (void)data;
    if (strcmp(property, "RegisteredStatusNotifierItems") == 0) {
        GVariantBuilder list;
        g_variant_builder_init(&list, G_VARIANT_TYPE("as"));
        for (guint i = 0; i < items->len; i++)
            g_variant_builder_add(&list, "s", (const char *)items->pdata[i]);
        return g_variant_builder_end(&list);
    }
    // There is always a tray to show the icons: some programs register theirs
    // only once they are told there is one, and a host may come a moment later.
    if (strcmp(property, "IsStatusNotifierHostRegistered") == 0)
        return g_variant_new_boolean(TRUE);
    if (strcmp(property, "ProtocolVersion") == 0)
        return g_variant_new_int32(0);
    return NULL;
}

static const GDBusInterfaceVTable vtable = { on_method, on_property, NULL, { 0 } };

// The copy kept while another watcher holds the name.

static void on_copied(GObject *source, GAsyncResult *result, gpointer data) {
    (void)source, (void)data;
    GError *error = NULL;
    GVariant *reply = g_dbus_connection_call_finish(bus, result, &error);
    if (!reply) {
        g_error_free(error);
        return;
    }
    if (holding) {
        g_variant_unref(reply);
        return;
    }
    GVariant *value;
    g_variant_get(reply, "(v)", &value);
    GVariantIter iter;
    const char *item;
    g_variant_iter_init(&iter, value);
    while (g_variant_iter_next(&iter, "&s", &item))
        add_item(item);
    g_variant_unref(value);
    g_variant_unref(reply);
}

/** Reads what the watcher holding the name has registered. */
static void copy_watcher(void) {
    g_dbus_connection_call(bus, WATCHER, WATCHER_PATH, "org.freedesktop.DBus.Properties", "Get",
                           g_variant_new("(ss)", WATCHER, "RegisteredStatusNotifierItems"), G_VARIANT_TYPE("(v)"),
                           G_DBUS_CALL_FLAGS_NONE, -1, NULL, on_copied, NULL);
}

// Signals from the watcher holding the name, which this one's own signals
// also reach once it holds it, and which are then left alone.
static void on_watcher_signal(GDBusConnection *connection, const char *sender, const char *path, const char *interface,
                              const char *signal, GVariant *parameters, gpointer data) {
    (void)connection, (void)sender, (void)path, (void)interface, (void)data;
    if (holding)
        return;
    const char *item;
    g_variant_get(parameters, "(&s)", &item);
    if (strcmp(signal, "StatusNotifierItemRegistered") == 0)
        add_item(item);
    else
        remove_item(item);
}

// A program leaving the bus takes its icons with it, a tray its host.
static void on_owner_changed(GDBusConnection *connection, const char *sender, const char *path, const char *interface,
                             const char *signal, GVariant *parameters, gpointer data) {
    (void)connection, (void)sender, (void)path, (void)interface, (void)signal, (void)data;
    const char *name, *before, *after;
    g_variant_get(parameters, "(&s&s&s)", &name, &before, &after);
    if (strcmp(name, WATCHER) == 0) {
        // Another watcher took the name: what it holds is copied afresh.
        if (after[0] != '\0' && !holding)
            copy_watcher();
        return;
    }
    if (after[0] != '\0')
        return;
    for (guint i = items->len; i > 0; i--) {
        const char *item = items->pdata[i - 1];
        if (belongs_to(item, name)) {
            char *gone = g_strdup(item);
            remove_item(gone);
            g_free(gone);
        }
    }
    for (guint i = 0; i < hosts->len; i++) {
        if (strcmp(hosts->pdata[i], name) == 0) {
            g_ptr_array_remove_index(hosts, i);
            emit("StatusNotifierHostUnregistered", NULL);
            break;
        }
    }
}

static void on_acquired(GDBusConnection *connection, const char *name, gpointer data) {
    (void)connection, (void)name, (void)data;
    holding = TRUE;
    fprintf(stderr, "yuki-tray: holding %s with %u icons\n", WATCHER, items->len);
}

static void on_lost(GDBusConnection *connection, const char *name, gpointer data) {
    (void)connection, (void)name, (void)data;
    // Queued behind another watcher, or pushed out by one: copied from it
    // until the name is free.
    if (holding)
        fprintf(stderr, "yuki-tray: lost %s\n", WATCHER);
    holding = FALSE;
    copy_watcher();
}

int main(void) {
    GError *error = NULL;
    bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        fprintf(stderr, "yuki-tray: no session bus: %s\n", error->message);
        return 1;
    }

    // One keeper per session.
    GVariant *reply = g_dbus_connection_call_sync(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                                                  "org.freedesktop.DBus", "RequestName",
                                                  g_variant_new("(su)", KEEPER, 4 /* do not queue */),
                                                  G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, &error);
    if (!reply) {
        fprintf(stderr, "yuki-tray: %s\n", error->message);
        return 1;
    }
    guint32 answer;
    g_variant_get(reply, "(u)", &answer);
    g_variant_unref(reply);
    if (answer != 1)
        return 0;

    items = g_ptr_array_new_with_free_func(g_free);
    hosts = g_ptr_array_new_with_free_func(g_free);

    GDBusNodeInfo *node = g_dbus_node_info_new_for_xml(introspection, &error);
    if (!node || !g_dbus_connection_register_object(bus, WATCHER_PATH, node->interfaces[0], &vtable, NULL, NULL, &error)) {
        fprintf(stderr, "yuki-tray: %s\n", error->message);
        return 1;
    }

    // Subscribed to before anything is read, so nothing falls between.
    g_dbus_connection_signal_subscribe(bus, "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                                       "/org/freedesktop/DBus", NULL, G_DBUS_SIGNAL_FLAGS_NONE, on_owner_changed,
                                       NULL, NULL);
    g_dbus_connection_signal_subscribe(bus, WATCHER, WATCHER, "StatusNotifierItemRegistered", WATCHER_PATH, NULL,
                                       G_DBUS_SIGNAL_FLAGS_NONE, on_watcher_signal, NULL, NULL);
    g_dbus_connection_signal_subscribe(bus, WATCHER, WATCHER, "StatusNotifierItemUnregistered", WATCHER_PATH, NULL,
                                       G_DBUS_SIGNAL_FLAGS_NONE, on_watcher_signal, NULL, NULL);

    // Queued for the name rather than taking it: the shell's own watcher
    // cannot be pushed out, and does not need to be while it lives.
    g_bus_own_name_on_connection(bus, WATCHER, G_BUS_NAME_OWNER_FLAGS_NONE, on_acquired, on_lost, NULL, NULL);

    g_main_loop_run(g_main_loop_new(NULL, FALSE));
    return 0;
}
